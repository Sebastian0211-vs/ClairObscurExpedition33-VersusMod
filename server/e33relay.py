#!/usr/bin/env python3
"""E33 Versus relay server: rooms of two players, newline-delimited JSON over TCP. Python 3.8+, stdlib only.

The server knows nothing about the game. It pairs a host and a guest in a room and forwards their messages.
Run:  python3 e33relay.py --port 33033 [--key SECRET] [--log-dir logs] [--http-port 33034 --admin-key ADMIN]
Protocol (one JSON object per line):
  client -> server  {"t":"hello","name":"Seb","ver":1,"key":"SECRET"}
                    {"t":"rooms"} | {"t":"create"} | {"t":"join","room":"ABCD"} | {"t":"leave"} | {"t":"ping"}
                    {"t":"msg", ...}   (anything else in the object is forwarded to the other player)
                    {"t":"log","id","part","parts","name","reason","text"}   (a player's game log, stored on the server)
  server -> client  {"t":"welcome","motd":...} {"t":"rooms","rooms":[{"room","host","players"}]}
                    {"t":"joined","room","role":"host"|"guest","peer":name|null} {"t":"peer_joined","name"}
                    {"t":"peer_left"} {"t":"msg","from":name,...} {"t":"pong"} {"t":"error","why"} {"t":"log_ok","id","part"}

Logs (--log-dir, default ./logs): rooms/<utc>_<ROOM>.jsonl = every event and relayed message of a room (pings
excluded), players/<utc>_<ROOM>_<player>_<reason>.log = game logs uploaded by players, relay.log = server events.
Files older than --log-days are deleted. --http-port + --admin-key serve a password-protected page listing them
(browser login: any user name, password = admin key).
"""
import argparse, asyncio, base64, datetime, html, json, logging, os, random, re, string, time, urllib.parse
from logging.handlers import RotatingFileHandler

PROTO = 1
MAX_LINE = 256 * 1024          # one message (a full state snapshot fits easily)
IDLE_TIMEOUT = 120             # seconds without any line (clients ping every 20 s)
UPLOAD_MAX = 4 * 1024 * 1024   # bytes of uploaded game logs per connection
SAFE = re.compile(r"[^A-Za-z0-9_.-]+")
log = logging.getLogger("e33relay")


class Player:
    def __init__(self, reader, writer):
        self.reader, self.writer = reader, writer
        self.name, self.room, self.ok, self.mod = "?", None, False, "?"
        self.addr = writer.get_extra_info("peername")
        self.uploads, self.uploaded = {}, 0

    async def send(self, obj):
        try:
            self.writer.write((json.dumps(obj, separators=(",", ":")) + "\n").encode())
            await self.writer.drain()
        except (ConnectionError, RuntimeError):
            pass


def utc_stamp():
    return datetime.datetime.utcnow().strftime("%Y%m%d-%H%M%S")


class Logs:
    """Log files under one folder; every write is best effort (a full disk must never stop the relay)."""

    def __init__(self, root, days):
        self.root, self.days = root, days
        if root:
            try:
                for sub in ("rooms", "players"):
                    os.makedirs(os.path.join(root, sub), exist_ok=True)
            except OSError as e:   # never refuse to relay because of logs
                print(f"log folder {root!r} unusable ({e}): logging off", flush=True)
                self.root = ""

    def path(self, sub, name):
        return os.path.join(self.root, sub, SAFE.sub("_", name)) if self.root else None

    def append(self, path, text):
        if not path:
            return
        try:
            with open(path, "a", encoding="utf-8") as f:
                f.write(text)
        except OSError as e:
            log.warning("log write failed: %s", e)

    def cleanup(self):
        if not self.root or self.days <= 0:
            return
        limit = time.time() - self.days * 86400
        for sub in ("rooms", "players"):
            d = os.path.join(self.root, sub)
            for n in os.listdir(d):
                fp = os.path.join(d, n)
                try:
                    if os.path.getmtime(fp) < limit:
                        os.remove(fp)
                except OSError:
                    pass

    def listing(self):
        out = []
        if not self.root:
            return out
        for sub in ("rooms", "players"):
            d = os.path.join(self.root, sub)
            for n in os.listdir(d):
                st = os.stat(os.path.join(d, n))
                out.append((st.st_mtime, sub, n, st.st_size))
        return sorted(out, reverse=True)


class Room:
    def __init__(self, code, host, logs):
        self.code, self.host, self.guest, self.created = code, host, None, time.time()
        self.logs, self.logpath = logs, logs.path("rooms", f"{utc_stamp()}_{code}.jsonl")

    def record(self, ev, p=None, m=None):
        """One line per room event: who did what (relayed game messages in full; pings never reach here)."""
        line = {"ts": round(time.time(), 3), "ev": ev}
        if p is not None:
            line["who"], line["role"] = p.name, ("host" if p is self.host else "guest")
        if m is not None:
            line["m"] = m
        self.logs.append(self.logpath, json.dumps(line, separators=(",", ":")) + "\n")

    def players(self):
        return [p for p in (self.host, self.guest) if p]

    def other(self, p):
        return self.guest if p is self.host else self.host


class Relay:
    def __init__(self, key, motd, logs):
        self.key, self.motd, self.rooms, self.logs = key, motd, {}, logs

    def new_code(self):
        while True:
            code = "".join(random.choice("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") for _ in range(4))
            if code not in self.rooms:
                return code

    async def leave(self, p):
        r = p.room
        if not r:
            return
        r.record("left", p)
        p.room = None
        other = r.other(p)
        if p is r.host:
            r.host, r.guest = r.guest, None      # guest becomes host if the host leaves
        else:
            r.guest = None
        if other:
            await other.send({"t": "peer_left"})
            if r.host is other:
                await other.send({"t": "joined", "room": r.code, "role": "host", "peer": None})
        if not r.players():
            self.rooms.pop(r.code, None)
            r.record("closed")
            log.info("room %s closed", r.code)

    async def handle(self, p, m):
        t = m.get("t")
        if t == "hello":
            if self.key and m.get("key") != self.key:
                await p.send({"t": "error", "why": "bad server key"}); return False
            if m.get("ver") != PROTO:
                await p.send({"t": "error", "why": f"protocol {m.get('ver')} != server {PROTO}, update the mod"}); return False
            p.name, p.ok = str(m.get("name") or "player")[:24], True
            p.mod = str(m.get("mod") or "?")[:24]
            await p.send({"t": "welcome", "motd": self.motd, "proto": PROTO})
            log.info("%s hello as %s (mod %s)", p.addr, p.name, p.mod)
            return True
        if not p.ok:
            await p.send({"t": "error", "why": "say hello first"}); return False
        if t == "ping":
            await p.send({"t": "pong", "time": time.time()})
        elif t == "rooms":
            await p.send({"t": "rooms", "rooms": [{"room": r.code, "host": r.host.name, "players": len(r.players())}
                                                   for r in self.rooms.values() if r.host]})
        elif t == "create":
            await self.leave(p)
            r = Room(self.new_code(), p, self.logs); self.rooms[r.code] = r; p.room = r
            r.record("created", p, {"mod": p.mod})
            await p.send({"t": "joined", "room": r.code, "role": "host", "peer": None})
            log.info("%s created room %s", p.name, r.code)
        elif t == "join":
            r = self.rooms.get(str(m.get("room", "")).upper())
            if not r:
                await p.send({"t": "error", "why": "no such room"})
            elif r.guest:
                await p.send({"t": "error", "why": "room is full"})
            else:
                await self.leave(p)
                r.guest, p.room = p, r
                r.record("joined", p, {"mod": p.mod})
                await p.send({"t": "joined", "room": r.code, "role": "guest", "peer": r.host.name})
                await r.host.send({"t": "peer_joined", "name": p.name})
                log.info("%s joined room %s", p.name, r.code)
        elif t == "leave":
            await self.leave(p)
        elif t == "msg":
            other = p.room and p.room.other(p)
            if p.room:
                p.room.record("msg", p, m)
            if other:
                m["from"] = p.name
                await other.send(m)
            else:
                await p.send({"t": "error", "why": "nobody to send to"})
        elif t == "log":
            await self.upload(p, m)
        else:
            await p.send({"t": "error", "why": f"unknown type {t}"})
        return True

    async def upload(self, p, m):
        """A player's game log, sent in parts (each part fits MAX_LINE). Stored under players/."""
        text, uid = str(m.get("text") or ""), str(m.get("id") or "0")[:32]
        p.uploaded += len(text)
        if p.uploaded > UPLOAD_MAX or not self.logs.root:
            await p.send({"t": "error", "why": "log upload refused (limit reached or logging off)"})
            return
        path = p.uploads.get(uid)
        if not path:
            room = p.room.code if p.room else "noroom"
            reason = SAFE.sub("_", str(m.get("reason") or "manual"))[:24]
            path = self.logs.path("players", f"{utc_stamp()}_{room}_{p.name}_{reason}.log")
            p.uploads[uid] = path
            self.logs.append(path, f"# {m.get('name') or 'log'} from {p.name} (mod {p.mod}), room {room}, reason {reason}\n")
            if p.room:
                p.room.record("log_upload", p, {"file": os.path.basename(path), "reason": reason})
        self.logs.append(path, text)
        await p.send({"t": "log_ok", "id": uid, "part": m.get("part"), "parts": m.get("parts")})
        if m.get("part") == m.get("parts"):
            log.info("%s uploaded %s", p.name, os.path.basename(path))

    async def client(self, reader, writer):
        p = Player(reader, writer)
        try:
            while True:
                line = await asyncio.wait_for(reader.readline(), IDLE_TIMEOUT)
                if not line:
                    break
                if len(line) > MAX_LINE:
                    await p.send({"t": "error", "why": "message too large"}); break
                try:
                    m = json.loads(line)
                    if not isinstance(m, dict):
                        raise ValueError("not an object")
                except ValueError:
                    await p.send({"t": "error", "why": "bad json"}); continue
                if not await self.handle(p, m):
                    break
        except (asyncio.TimeoutError, ConnectionError, asyncio.LimitOverrunError, ValueError):
            pass
        finally:
            await self.leave(p)
            writer.close()
            if p.ok:   # anonymous connections (health checks, port scans) are not worth a log line
                log.info("%s (%s) disconnected", p.addr, p.name)


class LogPage:
    """GET /  (listing)  and  GET /f/<rooms|players>/<file>  (one file). HTTP Basic auth: password = admin key."""

    def __init__(self, logs, admin_key):
        self.logs, self.admin_key = logs, admin_key

    def authorized(self, headers):
        auth = headers.get("authorization", "")
        if not auth.lower().startswith("basic "):
            return False
        try:
            return base64.b64decode(auth[6:]).decode("utf-8", "replace").split(":", 1)[-1] == self.admin_key
        except ValueError:
            return False

    async def client(self, reader, writer):
        try:
            req = (await asyncio.wait_for(reader.readline(), 10)).decode("latin-1").split()
            headers = {}
            while True:
                line = (await asyncio.wait_for(reader.readline(), 10)).decode("latin-1").strip()
                if not line:
                    break
                k, _, v = line.partition(":")
                headers[k.strip().lower()] = v.strip()
            if len(req) < 2 or req[0] != "GET":
                return await self.reply(writer, 405, "text/plain", b"GET only")
            if not self.authorized(headers):
                return await self.reply(writer, 401, "text/plain", b"login: any user name, password = admin key",
                                        {"WWW-Authenticate": 'Basic realm="E33 Versus logs"'})
            url = urllib.parse.urlsplit(req[1])
            parts = [urllib.parse.unquote(x) for x in url.path.split("/") if x]
            if parts[:1] == ["f"]:
                ok = len(parts) == 3 and parts[1] in ("rooms", "players") and SAFE.sub("_", parts[2]) == parts[2]
                fp = os.path.join(self.logs.root, parts[1], parts[2]) if ok else None
                if not (fp and os.path.isfile(fp)):
                    return await self.reply(writer, 404, "text/plain", b"no such file")
                with open(fp, "rb") as f:
                    return await self.reply(writer, 200, "text/plain; charset=utf-8", f.read())
            rows = "".join(
                f'<tr><td>{datetime.datetime.utcfromtimestamp(t).strftime("%Y-%m-%d %H:%M:%S")}</td><td>{sub}</td>'
                f'<td><a href="/f/{sub}/{urllib.parse.quote(n)}">{html.escape(n)}</a></td><td>{size // 1024 + 1} KB</td></tr>'
                for t, sub, n, size in self.logs.listing())
            page = ("<!doctype html><meta charset=utf-8><title>E33 Versus logs</title>"
                    "<style>body{font:14px system-ui;margin:16px}td,th{padding:2px 10px;text-align:left}</style>"
                    "<h1>E33 Versus logs</h1><p>Newest first, times UTC. rooms = relayed messages of a room, "
                    "players = game logs uploaded by players.</p>"
                    f"<table><tr><th>modified</th><th>kind</th><th>file</th><th>size</th></tr>{rows}</table>")
            await self.reply(writer, 200, "text/html; charset=utf-8", page.encode())
        except (asyncio.TimeoutError, ConnectionError, OSError, ValueError):
            pass
        finally:
            writer.close()

    @staticmethod
    async def reply(writer, code, ctype, body, extra=None):
        reason = {200: "OK", 401: "Unauthorized", 404: "Not Found", 405: "Method Not Allowed"}.get(code, "")
        head = f"HTTP/1.0 {code} {reason}\r\nContent-Type: {ctype}\r\nContent-Length: {len(body)}\r\n"
        for k, v in (extra or {}).items():
            head += f"{k}: {v}\r\n"
        writer.write((head + "Connection: close\r\n\r\n").encode() + body)
        await writer.drain()


async def cleanup_loop(logs):
    while True:
        logs.cleanup()
        await asyncio.sleep(6 * 3600)


async def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    # defaults from the environment so the Docker image is configured with E33_PORT / E33_KEY / E33_MOTD
    ap.add_argument("--host", default=os.environ.get("E33_HOST", "0.0.0.0"))
    ap.add_argument("--port", type=int, default=int(os.environ.get("E33_PORT", "33033")))
    ap.add_argument("--key", default=os.environ.get("E33_KEY", ""), help="optional shared secret players must enter")
    ap.add_argument("--motd", default=os.environ.get("E33_MOTD", "E33 Versus relay"))
    ap.add_argument("--log-dir", default=os.environ.get("E33_LOG_DIR", "logs"), help="log folder ('' = no logs)")
    ap.add_argument("--log-days", type=int, default=int(os.environ.get("E33_LOG_DAYS", "30")))
    ap.add_argument("--http-port", type=int, default=int(os.environ.get("E33_HTTP_PORT", "0")), help="log page port (0 = off)")
    ap.add_argument("--admin-key", default=os.environ.get("E33_ADMIN_KEY", ""), help="password of the log page")
    a = ap.parse_args()
    logs = Logs(a.log_dir, a.log_days)
    handlers = [logging.StreamHandler()]
    if logs.root:
        handlers.append(RotatingFileHandler(os.path.join(logs.root, "relay.log"), maxBytes=5_000_000, backupCount=3))
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", handlers=handlers)
    relay = Relay(a.key, a.motd, logs)
    server = await asyncio.start_server(relay.client, a.host, a.port, limit=MAX_LINE + 1)
    log.info("listening on %s:%d (key %s, logs %s)", a.host, a.port, "set" if a.key else "none", logs.root or "off")
    tasks = [asyncio.ensure_future(cleanup_loop(logs))]
    if a.http_port and logs.root:
        if not a.admin_key:
            log.warning("--http-port given without --admin-key: log page NOT started")
        else:
            page = await asyncio.start_server(LogPage(logs, a.admin_key).client, a.host, a.http_port)
            tasks.append(asyncio.ensure_future(page.serve_forever()))
            log.info("log page on port %d", a.http_port)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
