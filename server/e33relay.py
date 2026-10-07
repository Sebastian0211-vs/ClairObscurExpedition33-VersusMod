#!/usr/bin/env python3
"""E33 Versus relay server: rooms of two players, newline-delimited JSON over TCP. Python 3.8+, stdlib only.

The server knows nothing about the game. It pairs a host and a guest in a room and forwards their messages.
Run:  python3 e33relay.py --port 33033 [--key SECRET]
Protocol (one JSON object per line):
  client -> server  {"t":"hello","name":"Seb","ver":1,"key":"SECRET"}
                    {"t":"rooms"} | {"t":"create"} | {"t":"join","room":"ABCD"} | {"t":"leave"} | {"t":"ping"}
                    {"t":"msg", ...}   (anything else in the object is forwarded to the other player)
  server -> client  {"t":"welcome","motd":...} {"t":"rooms","rooms":[{"room","host","players"}]}
                    {"t":"joined","room","role":"host"|"guest","peer":name|null} {"t":"peer_joined","name"}
                    {"t":"peer_left"} {"t":"msg","from":name,...} {"t":"pong"} {"t":"error","why"}
"""
import argparse, asyncio, json, logging, os, random, string, time

PROTO = 1
MAX_LINE = 256 * 1024          # one message (a full state snapshot fits easily)
IDLE_TIMEOUT = 120             # seconds without any line (clients ping every 20 s)
log = logging.getLogger("e33relay")


class Player:
    def __init__(self, reader, writer):
        self.reader, self.writer = reader, writer
        self.name, self.room, self.ok = "?", None, False
        self.addr = writer.get_extra_info("peername")

    async def send(self, obj):
        try:
            self.writer.write((json.dumps(obj, separators=(",", ":")) + "\n").encode())
            await self.writer.drain()
        except (ConnectionError, RuntimeError):
            pass


class Room:
    def __init__(self, code, host):
        self.code, self.host, self.guest, self.created = code, host, None, time.time()

    def players(self):
        return [p for p in (self.host, self.guest) if p]

    def other(self, p):
        return self.guest if p is self.host else self.host


class Relay:
    def __init__(self, key, motd):
        self.key, self.motd, self.rooms = key, motd, {}

    def new_code(self):
        while True:
            code = "".join(random.choice("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") for _ in range(4))
            if code not in self.rooms:
                return code

    async def leave(self, p):
        r = p.room
        if not r:
            return
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
            log.info("room %s closed", r.code)

    async def handle(self, p, m):
        t = m.get("t")
        if t == "hello":
            if self.key and m.get("key") != self.key:
                await p.send({"t": "error", "why": "bad server key"}); return False
            if m.get("ver") != PROTO:
                await p.send({"t": "error", "why": f"protocol {m.get('ver')} != server {PROTO}, update the mod"}); return False
            p.name, p.ok = str(m.get("name") or "player")[:24], True
            await p.send({"t": "welcome", "motd": self.motd, "proto": PROTO})
            log.info("%s hello as %s", p.addr, p.name)
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
            r = Room(self.new_code(), p); self.rooms[r.code] = r; p.room = r
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
                await p.send({"t": "joined", "room": r.code, "role": "guest", "peer": r.host.name})
                await r.host.send({"t": "peer_joined", "name": p.name})
                log.info("%s joined room %s", p.name, r.code)
        elif t == "leave":
            await self.leave(p)
        elif t == "msg":
            other = p.room and p.room.other(p)
            if other:
                m["from"] = p.name
                await other.send(m)
            else:
                await p.send({"t": "error", "why": "nobody to send to"})
        else:
            await p.send({"t": "error", "why": f"unknown type {t}"})
        return True

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


async def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    # defaults from the environment so the Docker image is configured with E33_PORT / E33_KEY / E33_MOTD
    ap.add_argument("--host", default=os.environ.get("E33_HOST", "0.0.0.0"))
    ap.add_argument("--port", type=int, default=int(os.environ.get("E33_PORT", "33033")))
    ap.add_argument("--key", default=os.environ.get("E33_KEY", ""), help="optional shared secret players must enter")
    ap.add_argument("--motd", default=os.environ.get("E33_MOTD", "E33 Versus relay"))
    a = ap.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")
    relay = Relay(a.key, a.motd)
    server = await asyncio.start_server(relay.client, a.host, a.port, limit=MAX_LINE + 1)
    log.info("listening on %s:%d (key %s)", a.host, a.port, "set" if a.key else "none")
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
