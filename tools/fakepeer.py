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
    ap.add_argument("--desync", action="store_true", help="when it owns a turn's state, send back the host's last snapshot with A1's shield set to 7")
    ap.add_argument("--wrongactor", action="store_true", help="once (3rd turn or later, when it owns the state): name another unit as the one acting")
    ap.add_argument("--endfirst", type=int, default=0, help="at this turn message: claim the match ended with side B winning")
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
    snaps = {"units": None, "ns": set()}
    turns_seen, flags = [0], {}
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
            # state protocol (handled before the reactions below, which may also apply to the same message)
            if k == "snap":
                msg("ack", n=m.get("n"), final=m.get("final"))
                if not m.get("final"):
                    snaps["units"] = m.get("units"); snaps["ns"].add(m.get("n"))
            if k == "turn":
                turns_seen[0] += 1
            if k == "turn" and m.get("n") not in snaps["ns"]:
                # the host did not send this turn's state, so it waits for ours (we own it). We hold no real state:
                # an empty snapshot releases the host's turn; --desync plants a difference on A1 (from the host's last
                # snapshot), --wrongactor (once) names another unit as the one acting this turn.
                units = {}
                if a.desync and snaps["units"] and "A1" in snaps["units"]:
                    units["A1"] = json.loads(json.dumps(snaps["units"]["A1"])); units["A1"]["shield"] = 7
                actor = m.get("uid")
                if a.wrongactor and not flags.get("wrong") and turns_seen[0] >= 3:
                    flags["wrong"] = True
                    actor = "B1" if actor != "B1" else "A1"
                msg("snap", n=m.get("n"), actor=actor, units=units)
            if k == "turn" and a.endfirst and turns_seen[0] == a.endfirst and not flags.get("ended"):
                # claim the match is over (we won) before the host's own end check: the host must end the same way
                flags["ended"] = True
                msg("end", winner="B", n=m.get("n"), owner=True, why="fakepeer --endfirst")
            if k == "end" and not flags.get("ended"):
                flags["ended"] = True
                msg("end", winner=m.get("winner"), n=m.get("n"), owner=False, why="fakepeer agrees")
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
                time.sleep(15); msg("stats", units={"B1": {"stats": {"1": 5000, "3": 30, "8": 100}, "hp": 5000}})
            elif k == "act" and m.get("kind") == "move" and a.parry and str(m.get("target", "")).startswith("B"):
                # we "defend": the attack starts here (began), then one outcome per hit right after each hit
                time.sleep(0.5); msg("began", actor=m["uid"])
                base_hp = ((snaps["units"] or {}).get(m["target"]) or {}).get("hp") or 20000
                for n in range(1, 13):
                    send({"t": "msg", "k": "hit", "uid": m["target"], "n": n, "def": "parry", "actor": m["uid"]})
                    # the hit's result as the defender saw it (planted: 1 HP per hit, so the attacker visibly applies it)
                    send({"t": "msg", "k": "hitres", "uid": m["target"], "n": n, "actor": m["uid"], "hp": base_hp - n, "shield": 0})
            elif k == "act" and m.get("kind") == "hero":
                last_hero["atype"] = m.get("atype")      # learn the host's action type numbers
            elif k == "turn" and str(m.get("uid", "")).startswith("B") and m.get("hero"):
                time.sleep(2)
                target = random.choice(m["targets"])
                msg("act", uid=m["uid"], n=m.get("n"), kind="hero", atype=last_hero["atype"] if last_hero["atype"] is not None else 1,
                    secondary=None, targets=[target])
                # our hero's hit results (we are the truth for our hero's attack): planted 1 HP per hit
                base_hp = ((snaps["units"] or {}).get(target) or {}).get("hp") or 300
                if base_hp:
                    for n in range(1, 6):
                        msg("hitres", uid=target, n=n, actor=m["uid"], hp=base_hp - n, shield=0, hero=True)
            elif k == "turn" and str(m.get("uid", "")).startswith("B") and a.item:
                a.item = False; time.sleep(2)
                msg("act", uid=m["uid"], n=m.get("n"), kind="item", item="Consumable_Health_Level0", targets=[m["uid"]])
            elif k == "turn" and str(m.get("uid", "")).startswith("B") and m.get("moves"):
                time.sleep(2)
                msg("act", uid=m["uid"], n=m.get("n"), kind="move", move=random.choice(m["moves"]), target=random.choice(m["targets"]))
            elif t == "ping":
                pass


if __name__ == "__main__":
    main()
