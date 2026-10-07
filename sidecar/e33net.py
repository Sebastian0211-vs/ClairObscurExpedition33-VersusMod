#!/usr/bin/env python3
"""E33 Versus network sidecar (runs next to the game; the game's Lua has no sockets). Python 3.8+, stdlib only.

Game <-> sidecar through two append-only JSON-lines files in BRIDGE (--bridge: the mod passes ue4ss/Mods/E33Versus/data/net)
(UE4SS Lua cannot list directories, so each side remembers how far it has read):
  out.jsonl        appended by the game, one JSON object per line. Local commands:
                     {"t":"connect","host":"1.2.3.4","port":33033,"name":"Seb","key":""}
                     {"t":"disconnect"}  {"t":"quit"}
                   anything else is sent to the relay as-is ({"t":"create"}, {"t":"msg",...}, ...).
  in.jsonl         appended here for the game: every relay message, plus {"t":"net","state":...} events.
                   The game empties both files before launching the sidecar; the sidecar never truncates them.
  status.json      {"state":"offline|connecting|online","room","role","peer","ping_ms","server"}
  alive            the game touches it every few seconds; once it is stale for 30 s the sidecar exits if the game
                   process is gone (a save load can keep it stale for minutes), or after 15 min regardless.
Run: pythonw e33net.py [--bridge DIR]
"""
import argparse, json, os, socket, subprocess, threading, time

PROTO = 1


class Net:
    def __init__(self, bridge):
        self.dir = bridge
        os.makedirs(bridge, exist_ok=True)
        self.out_path, self.in_path = os.path.join(bridge, "out.jsonl"), os.path.join(bridge, "in.jsonl")
        # The GAME empties both files before launching us; we never truncate (a request the game wrote
        # while we were starting up must not be lost). Read out.jsonl from the beginning.
        for pth in (self.out_path, self.in_path):
            open(pth, "a").close()
        self.out_off = 0
        self.sock, self.lock = None, threading.Lock()
        self.seq = int(time.time() * 1000)
        self.status = {"state": "offline", "room": None, "role": None, "peer": None, "ping_ms": None, "server": None}
        self.ping_sent = None
        self.write_status()

    # ---- files ----
    def atomic(self, path, obj):
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(obj, f, separators=(",", ":"))
        os.replace(tmp, path)

    def to_game(self, obj):
        line = json.dumps(obj, separators=(",", ":"), ensure_ascii=True) + "\n"
        with self.lock:
            with open(self.in_path, "a", encoding="utf-8") as f:
                f.write(line)

    def write_status(self):
        self.atomic(os.path.join(self.dir, "status.json"), self.status)

    def event(self, state, **kw):
        self.status["state"] = state
        self.status.update(kw)
        self.write_status()
        self.to_game({"t": "net", "state": state, **kw})

    # ---- socket ----
    def send(self, obj):
        s = self.sock
        if not s:
            self.to_game({"t": "error", "why": "not connected"}); return
        try:
            s.sendall((json.dumps(obj, separators=(",", ":")) + "\n").encode())
        except OSError as e:
            self.drop(f"send failed: {e}")

    def connect(self, host, port, name, key):
        self.disconnect(quiet=True)
        self.event("connecting", server=f"{host}:{port}", room=None, role=None, peer=None)
        try:
            s = socket.create_connection((host, int(port)), timeout=8)
            s.settimeout(None)
            s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        except OSError as e:
            self.event("offline", error=f"cannot reach {host}:{port} ({e})"); return
        self.sock = s
        threading.Thread(target=self.reader, args=(s,), daemon=True).start()
        self.send({"t": "hello", "name": name, "ver": PROTO, "key": key})

    def reader(self, s):
        buf = b""
        try:
            while True:
                chunk = s.recv(65536)
                if not chunk:
                    break
                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    try:
                        m = json.loads(line)
                    except ValueError:
                        continue
                    self.on_server(m)
        except OSError:
            pass
        if s is self.sock:
            self.drop("server closed the connection")

    def on_server(self, m):
        t = m.get("t")
        if t == "welcome":
            self.event("online", motd=m.get("motd"), error=None)
        elif t == "joined":
            self.status.update(room=m.get("room"), role=m.get("role"), peer=m.get("peer")); self.write_status()
        elif t == "peer_joined":
            self.status["peer"] = m.get("name"); self.write_status()
        elif t == "peer_left":
            self.status["peer"] = None; self.write_status()
        elif t == "pong":
            if self.ping_sent:
                self.status["ping_ms"] = round((time.time() - self.ping_sent) * 1000); self.write_status()
            return
        self.to_game(m)

    def drop(self, why):
        self.disconnect(quiet=True)
        self.event("offline", error=why, room=None, role=None, peer=None)

    def disconnect(self, quiet=False):
        s, self.sock = self.sock, None
        if s:
            try:
                s.close()
            except OSError:
                pass
        if not quiet:
            self.event("offline", error=None, room=None, role=None, peer=None)

    def read_out(self):
        """Complete new lines of out.jsonl since the last read (a partial last line waits for the next pass)."""
        try:
            with open(self.out_path, "rb") as f:
                f.seek(self.out_off)
                data = f.read()
        except OSError:
            return []
        end = data.rfind(b"\n")
        if end < 0:
            return []
        self.out_off += end + 1
        out = []
        for line in data[:end].split(b"\n"):
            try:
                m = json.loads(line)
                if isinstance(m, dict):
                    out.append(m)
            except ValueError:
                pass
        return out

    # ---- main loop ----
    GAME_EXE = "SandFall-Win64-Shipping.exe"

    def game_running(self, now):
        """True while the game process exists (checked at most every 5 s). Non-Windows: assume yes."""
        if now - getattr(self, "_game_at", 0) < 5:
            return self._game_up
        self._game_at = now
        try:
            out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq " + self.GAME_EXE, "/NH"], capture_output=True,
                                 stdin=subprocess.DEVNULL, text=True, timeout=10,
                                 creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0)).stdout
            self._game_up = self.GAME_EXE.lower() in out.lower()
        except (OSError, subprocess.SubprocessError):
            self._game_up = True
        return self._game_up

    def run(self):
        last_ping, started = 0, time.time()
        while True:
            for m in self.read_out():
                t = m.get("t")
                if t == "connect":
                    self.connect(m.get("host"), m.get("port", 33033), m.get("name", "player"), m.get("key", ""))
                elif t == "disconnect":
                    self.disconnect()
                elif t == "quit":
                    self.disconnect(quiet=True); self.event("offline"); return
                else:
                    self.send(m)
            now = time.time()
            if self.sock and now - last_ping > 20:
                last_ping, self.ping_sent = now, now
                self.send({"t": "ping"})
            alive = os.path.join(self.dir, "alive")
            try:
                idle = now - os.path.getmtime(alive)
            except OSError:
                idle = now - started
            # The game's Lua does not run while a save loads or the save list is open, so "alive" can go stale for
            # minutes in a normal match start. Leave only when the game process is really gone (or after 15 min).
            if idle > 30 and (idle > 900 or not self.game_running(now)):
                self.disconnect(quiet=True); self.event("offline", error="game closed"); return
            time.sleep(0.05)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--bridge", required=True, help="folder shared with the game (Mods/E33Versus/data/net)")
    Net(ap.parse_args().bridge).run()
