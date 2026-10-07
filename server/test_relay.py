#!/usr/bin/env python3
"""Integration test for the relay: two clients say hello, one creates a room, the other joins, a message is relayed.
Usage: python test_relay.py [host] [port] [key]   (exit code 0 = pass)"""
import json, socket, sys, time

HOST = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 33033
KEY = sys.argv[3] if len(sys.argv) > 3 else ""


class Client:
    def __init__(self, name):
        self.s = socket.create_connection((HOST, PORT), 5)
        self.s.settimeout(5)
        self.buf = b""
        self.send({"t": "hello", "name": name, "ver": 1, "key": KEY})

    def send(self, o):
        self.s.sendall((json.dumps(o) + "\n").encode())

    def wait(self, pred, what):
        end = time.time() + 5
        while time.time() < end:
            while b"\n" in self.buf:
                line, self.buf = self.buf.split(b"\n", 1)
                m = json.loads(line)
                if pred(m):
                    return m
            try:
                data = self.s.recv(65536)
                if not data:  # Connection closed by server
                    raise SystemExit("FAIL: connection closed by server while waiting for " + what)
                self.buf += data
            except ConnectionResetError as e:
                raise SystemExit("FAIL: connection reset by server while waiting for " + what) from e
        raise SystemExit("FAIL: no " + what)


def main():
    for i in range(30):   # the server may still be starting (CI, docker)
        try:
            a = Client("Host"); break
        except OSError:
            time.sleep(1)
    else:
        raise SystemExit("FAIL: cannot connect to %s:%d" % (HOST, PORT))
    b = Client("Guest")
    a.wait(lambda m: m.get("t") == "welcome", "welcome for host")
    b.wait(lambda m: m.get("t") == "welcome", "welcome for guest")
    a.send({"t": "create"})
    room = a.wait(lambda m: m.get("t") == "joined", "room for host")["room"]
    b.send({"t": "join", "room": room})
    b.wait(lambda m: m.get("t") == "joined", "join for guest")
    a.send({"t": "msg", "k": "team", "side": "A", "units": [{"kind": "enemy", "row": "AS_Mime"}]})
    m = b.wait(lambda m: m.get("t") == "msg" and m.get("k") == "team", "relayed message")
    assert m["units"][0]["row"] == "AS_Mime" and m.get("from") == "Host", m
    print("PASS: room %s, message relayed" % room)


if __name__ == "__main__":
    main()
