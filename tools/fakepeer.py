#!/usr/bin/env python3
"""Fake online opponent for solo testing: joins a room as the guest, picks enemy units, readies, loads,
and plays its units (side B) with random moves/targets taken from the host's "turn" messages.
Usage: python fakepeer.py --host 127.0.0.1 --port 33033 [--key K] [--room CODE] [--units CZ_ChromaLune,Goblu]"""
import argparse, json, random, socket, threading, time


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1"); ap.add_argument("--port", type=int, default=33033)
    ap.add_argument("--key", default=""); ap.add_argument("--room", default="")
    ap.add_argument("--units", default="CZ_ChromaLune")
    ap.add_argument("--item", action="store_true", help="first own turn: use a Healing Tint on itself (item sync test)")
    ap.add_argument("--parry", action="store_true", help="defender: report every hit of the host's monster moves as parried")
    a = ap.parse_args()
    s = socket.create_connection((a.host, a.port))
    lock = threading.Lock()

    def send(o):
        with lock:
            s.sendall((json.dumps(o) + "\n").encode())
        if o.get("t") != "ping":
            print(">>", o, flush=True)

    def msg(k, **kw):
        send({"t": "msg", "k": k, **kw})

    send({"t": "hello", "name": "FakePeer", "ver": 1, "key": a.key})

    def pinger():   # the relay drops connections that are silent for 120 s
        while True:
            time.sleep(20)
            try:
                send({"t": "ping"})
            except OSError:
                return
    threading.Thread(target=pinger, daemon=True).start()
    # --units CZ_ChromaLune,hero:Maelle
    team = [({"kind": "hero", "id": r[5:]} if r.startswith("hero:") else {"kind": "enemy", "row": r}) for r in a.units.split(",") if r]
    last_hero = {"atype": None}
    buf = b""
    while True:
        chunk = s.recv(65536)
        if not chunk:
            print("server closed"); return
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            m = json.loads(line)
            if m.get("t") != "pong":
                print("<<", m, flush=True)
            t, k = m.get("t"), m.get("k")
            if t == "welcome":
                send({"t": "join", "room": a.room} if a.room else {"t": "rooms"})
            elif t == "rooms":
                free = [r for r in m.get("rooms", []) if r["players"] < 2]
                if free:
                    send({"t": "join", "room": free[0]["room"]})
                else:
                    time.sleep(2); send({"t": "rooms"})
            elif t == "peer_left" or (t == "joined" and m.get("role") == "host"):
                # opponent left: leave the empty room and look for another one
                send({"t": "leave"}); time.sleep(2); send({"t": "rooms"})
            elif t == "joined":
                time.sleep(1)
                msg("team", side="B", units=team)
                msg("ready", side="B", ready=True)
            elif k == "go":
                time.sleep(1); msg("loaded")
                # our units' stat sheet (each PC is the truth for its own units); easy-to-spot values
                time.sleep(25); msg("stats", units={"B1": {"stats": {"1": 5000, "3": 999, "8": 777}, "hp": 4321}})
            elif k == "act" and m.get("kind") == "move" and a.parry and str(m.get("target", "")).startswith("B"):
                # we "defend": the attack starts here (began), then one outcome per hit right after each hit
                time.sleep(0.5); msg("began", actor=m["uid"])
                for n in range(1, 13):
                    send({"t": "msg", "k": "hit", "uid": m["target"], "n": n, "def": "parry", "actor": m["uid"]})
            elif k == "act" and m.get("kind") == "hero":
                last_hero["atype"] = m.get("atype")      # learn the host's action type numbers
            elif k == "turn" and str(m.get("uid", "")).startswith("B") and m.get("hero"):
                time.sleep(2)
                msg("act", uid=m["uid"], kind="hero", atype=last_hero["atype"] if last_hero["atype"] is not None else 1,
                    secondary=None, targets=[random.choice(m["targets"])])
            elif k == "turn" and str(m.get("uid", "")).startswith("B") and a.item:
                a.item = False; time.sleep(2)
                msg("act", uid=m["uid"], kind="item", item="Consumable_Health_Level0", targets=[m["uid"]])
            elif k == "turn" and str(m.get("uid", "")).startswith("B") and m.get("moves"):
                time.sleep(2)
                msg("act", uid=m["uid"], kind="move", move=random.choice(m["moves"]), target=random.choice(m["targets"]))
            elif t == "ping":
                pass


if __name__ == "__main__":
    main()
