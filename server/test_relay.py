#!/usr/bin/env python3
"""Integration test for the relay: two clients say hello, one creates a room, the other joins, a message is relayed,
a game log is uploaded; with a log-page port + admin key, the page must refuse a request without the password and
list the room log and the uploaded log with it.
Usage: python test_relay.py [host] [port] [key] [log_page_port admin_key]   (exit code 0 = pass)"""
import base64, json, socket, sys, time, urllib.error, urllib.request

HOST = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 33033
KEY = sys.argv[3] if len(sys.argv) > 3 else ""
HTTP_PORT = int(sys.argv[4]) if len(sys.argv) > 4 else 0
ADMIN = sys.argv[5] if len(sys.argv) > 5 else ""


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
    b.send({"t": "log", "id": "t1", "part": 1, "parts": 1, "name": "versus.log", "reason": "test", "text": "12:00:00 VS test line\n"})
    b.wait(lambda m: m.get("t") == "log_ok" and m.get("id") == "t1", "log_ok for the upload")
    print("PASS: room %s, message relayed, log uploaded" % room)
    if HTTP_PORT:
        base = "http://%s:%d/" % (HOST, HTTP_PORT)
        try:
            urllib.request.urlopen(base, timeout=5)
            raise SystemExit("FAIL: log page answered without the password")
        except urllib.error.HTTPError as e:
            if e.code != 401:
                raise SystemExit("FAIL: log page without password: HTTP %d" % e.code)
        req = urllib.request.Request(base, headers={"Authorization": "Basic " + base64.b64encode(("admin:" + ADMIN).encode()).decode()})
        page = urllib.request.urlopen(req, timeout=5).read().decode()
        if "_" + room + ".jsonl" not in page or "_Guest_test.log" not in page:
            raise SystemExit("FAIL: log page does not list the room log and the upload")
        name = page.split('href="/f/players/')[1].split('"')[0]
        req = urllib.request.Request(base + "f/players/" + name, headers=req.headers)
        if "VS test line" not in urllib.request.urlopen(req, timeout=5).read().decode():
            raise SystemExit("FAIL: uploaded log content")
        print("PASS: log page (401 without password, listing + file with it)")


if __name__ == "__main__":
    main()
