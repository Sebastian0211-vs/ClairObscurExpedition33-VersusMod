# E33 Versus relay server

Pairs two players in a room and forwards their messages. It never runs the game. It keeps logs so the server owner
can see what happened in a match (see [Logs](#logs)). Python 3 standard library only; one TCP port (default `33033`),
plus an optional log page port (default `33034`).

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
`E33_MOTD` (welcome text), `E33_ADMIN_KEY` (log page password; empty = page off), `E33_LOG_DAYS` (default 30),
`E33_LOG_DIR` / `E33_HTTP_PORT` (set by the image: `/data`, 33034).

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

## Logs
Written to the log folder (Docker: the `e33logs` volume at `/data`; otherwise `--log-dir`, default `./logs`):
- `rooms/<utc time>_<ROOM>.jsonl`: every event of a room (created, joined, left, closed) and every game message it
  relayed, one JSON object per line. This is the full record of an online match.
- `players/<utc time>_<ROOM>_<player>_<reason>.log`: a player's game log (`versus.log`, last 1 MB). The game sends it
  when an online match ends, when the opponent leaves mid-match, on a detected desync, and when a player picks
  **Send logs** in the online menu.
- `relay.log`: connections (with each player's mod version), rooms, uploads.

Files older than `E33_LOG_DAYS` (default 30) are deleted.

**Log page:** set `E33_ADMIN_KEY` in `.env` (and open `E33_LOG_PORT`, default 33034, in the firewall), then browse to
`http://<server-ip>:33034/`. Log in with any user name and the admin key as password. The page lists all files,
newest first; click one to read it. Plain HTTP: use a long random admin key, or skip the port and use an SSH tunnel
(`ssh -L 33034:localhost:33034 you@server`, then `http://localhost:33034/`). Without `E33_ADMIN_KEY` the page is off.

Without the page: `docker compose exec relay ls -R /data` and `docker compose cp relay:/data ./e33logs`.

## Firewall
Open TCP `33033` (or your `E33_PUBLIC_PORT`): `sudo ufw allow 33033/tcp`, plus the provider's firewall if it has one
(Infomaniak: Manager → VPS → Firewall).
Check from a Windows PC: `Test-NetConnection <server-ip> -Port 33033` → `TcpTestSucceeded : True`.

## Test
`python3 test_relay.py <host> <port> <key>` connects two fake players, opens a room and relays a message
(prints `PASS`). CI runs it against the Docker image on every push.
