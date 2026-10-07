# E33 Versus relay server

Pairs two players in a room and forwards their messages. It never runs the game and stores nothing.
Python 3 standard library only; one TCP port (default `33033`).

Players add it in-game: **VERSUS → Online versus → Add server** (address, port, key).

## Option A — Docker (recommended)
```bash
mkdir e33versus && cd e33versus
curl -LO https://raw.githubusercontent.com/Sebastian0211-vs/ClairObscurExpedition33-VersusMod/main/server/docker-compose.yml
curl -L -o .env https://raw.githubusercontent.com/Sebastian0211-vs/ClairObscurExpedition33-VersusMod/main/server/.env.example
nano .env                 # E33_KEY = the secret players type once; E33_PUBLIC_PORT if 33033 is taken
docker compose up -d
docker compose logs -f    # hellos, rooms, disconnects
```
Update: `docker compose pull && docker compose up -d`. Stop: `docker compose down`.

The image is `ghcr.io/sebastian0211-vs/e33versus-relay` (`latest` or a release tag such as `v0.1.0`, amd64 + arm64).
To build it yourself from this folder instead: `docker compose up -d --build`.

Settings (environment): `E33_KEY` (empty = no key), `E33_PORT` (port inside the container, default 33033),
`E33_MOTD` (welcome text).

## Option B — systemd (no Docker)
```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin e33relay
sudo mkdir -p /opt/e33relay && sudo cp e33relay.py /opt/e33relay/
sudo cp e33relay.service /etc/systemd/system/
sudo nano /etc/systemd/system/e33relay.service     # replace CHANGE_ME with your key
sudo systemctl daemon-reload && sudo systemctl enable --now e33relay
journalctl -u e33relay -f
```

## Option C — just run it
```bash
python3 e33relay.py --port 33033 --key my-secret
```

## Firewall
Open TCP `33033` (or your `E33_PUBLIC_PORT`): `sudo ufw allow 33033/tcp`, plus the provider's firewall if it has one
(Infomaniak: Manager → VPS → Firewall).
Check from a Windows PC: `Test-NetConnection <server-ip> -Port 33033` → `TcpTestSucceeded : True`.

## Test
`python3 test_relay.py <host> <port> <key>` connects two fake players, opens a room and relays a message
(prints `PASS`). CI runs it against the Docker image on every push.
