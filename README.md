# E33 Versus — 1v1 battles for Clair Obscur: Expedition 33

Build a team from **any** character of the game — Expeditioners, enemies, bosses — and fight a friend, on the same
PC or online.

- **VERSUS** button on the title screen, Sparking Zero–style character select: 334 units, teams of up to 3 under a
  15-point cap, costs and stats balanced around a common level.
- **The game's own battle wheel for every unit.** Monsters and bosses get *Skills*, *Items* and *Attack* exactly like
  the Expeditioners: real targeting cursor, tooltips, AP gauge and costs. Units with more than 6 moves get a
  **6-move loadout** you choose on the select screen.
- **Items** per team and per match (3 Healing, 2 Energy, 1 Revive Tint).
- **Boss phases** as a hard-to-trigger super move (*Phase Up*), not a second life.
- **Arenas:** fight where your save stands, or travel to one of 64 locations.
- **Online 1v1** through a tiny relay server you can host yourself (one Docker command).
- **Custom characters:** turn any 3D model (`.glb`, `.fbx`, `.obj`, `.vrm`...) into a fighter with **CharForge**: it plays
  with the moves and animations of the unit you pick as its base (see [CharForge](tools/charforge/README.md)).

> Status: early test build (0.x). Expect rough edges — please report them in Issues.

## Requirements
- *Clair Obscur: Expedition 33* (Steam, PC).
- **UE4SS dev build `716c1e4`** (Dec 2025, reports itself as "v3.0.1 Beta #0 - Git SHA #716c1e4" in `UE4SS.log`).
  This is the build the mod is tested on. Do **not** use the official `v3.0.1` release (Feb 2024): it is much older.
  Download `UE4SS_716c1e4_for_E33Versus.zip` from the [v0.1.0 release](../../releases/tag/v0.1.0) and extract it into
  the game folder (UE4SS is MIT-licensed; the zip holds only UE4SS and its standard mods). Already have UE4SS from the
  Archipelago randomizer? That is the same build.
- A save that has at least one Expeditioner. The fight takes place in the world of the save you pick; autosave is
  turned off during versus so your save is not touched.
- Online: Windows firewall may ask once about `e33net.exe` (the mod's network helper) — allow it.

## Install
1. Download `E33Versus-<version>.zip` from [Releases](../../releases).
2. Extract it into the game folder (`...\steamapps\common\Expedition 33\`) so that
   `Sandfall\Binaries\Win64\ue4ss\Mods\E33Versus\` exists.
3. The mod enables itself (`enabled.txt`). If it does not load, add the line `E33Versus : 1` to
   `Sandfall\Binaries\Win64\ue4ss\Mods\mods.txt`.
4. Start the game: a **VERSUS** button appears on the title screen.

Uninstall: delete `ue4ss\Mods\E33Versus`. Logs: `ue4ss\Mods\E33Versus\data\versus.log` and `ue4ss\UE4SS.log`.

## Controls
| | Keyboard | Gamepad |
|---|---|---|
| Move | Arrows | D-pad / left stick |
| Pick / confirm | Enter | A |
| Remove / back | Backspace | B |
| Unit categories | Q / E | LB / RB |
| Switch team (local) | Tab | Y |
| Edit a unit's 6 moves | R | R3 |
| Arena / level | F7 / F8 | LT / RT |
| Start (local) / Ready (online) | Space | X |
| Open versus in a loaded world | F6 | L3 + R3 |

In battle everything uses the game's normal battle controls.

## Custom characters
1. Install [Blender](https://www.blender.org/download/) 4.2+.
2. Play one versus match with the unit you want as a base (a hero, Chroma Maelle, a Chalier...): its skeleton is saved.
3. Drag your model onto `ue4ss\Mods\E33Versus\CharForge\CharForge.exe`, pick the base, a name and a cost.
4. VERSUS -> **Custom** tab. Details, supported models and limits: [tools/charforge/README.md](tools/charforge/README.md).

## Play online
1. One of you hosts a relay server (below) — or use a server a friend runs.
2. Title screen → **VERSUS** → **Online versus** → **Add server**: a name, the address, port (default `33033`) and the
   server key.
3. One player **creates a room**, the other joins it (open rooms are listed, or type the 4-letter code).
4. Pick teams, both press **Ready** → the host's settings (arena, level) are used, each player picks the save to fight in,
   and the match starts once both games are loaded.

The defending player's game is the authority for each attack (it ran the parry/dodge), so both screens stay in sync.

## Host a server
Everything is in [`server/`](server/). With Docker, on any Linux box/VPS:
```bash
mkdir e33versus && cd e33versus
curl -LO https://raw.githubusercontent.com/Sebastian0211-vs/ClairObscurExpedition33-VersusMod/main/server/docker-compose.yml
curl -L -o .env https://raw.githubusercontent.com/Sebastian0211-vs/ClairObscurExpedition33-VersusMod/main/server/.env.example
nano .env            # set E33_KEY
docker compose up -d
```
Open TCP port `33033` in your firewall/provider panel. Without Docker: `python3 e33relay.py --key <secret>` (Python 3.8+,
no packages) or the systemd unit — see [`server/README.md`](server/README.md).

## Build / develop
- `mod/E33Versus/` is the mod as it installs. A junction from `ue4ss\Mods\E33Versus` to this folder runs the repo
  directly; an optional, git-ignored `Scripts/dev.lua` sets developer paths (see `Scripts/main.lua`).
- `sidecar/e33net.py`: the network helper (Lua has no sockets); releases ship it built as `e33net.exe` (PyInstaller).
- `server/`: relay server, Dockerfile, compose file, `test_relay.py`.
- `tools/fakepeer.py`: a scripted online opponent for solo testing.
- `tools/charforge/`: custom characters (CLI + Blender converter); in game `Scripts/lib/custom.lua` rebuilds them.
- CI checks every push; pushing a tag `vX.Y.Z` builds the release zips and the relay image
  (`ghcr.io/sebastian0211-vs/e33versus-relay`).

## Credits
- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) — the Lua modding runtime this mod runs on.
- Research tools used to understand the game (not shipped): retoc, kismet-analyzer, CUE4Parse, FModel.
- The Archipelago randomizer for Expedition 33 (COE33AP), whose VERSUS-button approach and API usage were a reference.
- **AI disclosure:** this mod was designed by Sebastian0211-vs and programmed, reverse-engineered and tested
  with Claude Code (Anthropic, model Claude Opus 5.5). No AI-generated art or audio — every visual and sound is the
  game's own.

Clair Obscur: Expedition 33 © Sandfall Interactive / Kepler Interactive. This is an unofficial fan project; no game
files are included. Code under the [MIT License](LICENSE).
