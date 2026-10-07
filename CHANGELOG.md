# Changelog

## Unreleased
- **Online: see the opponent's parries, dodges and jumps on monster attacks.** The defending player's PC reports the
  outcome of every hit; the attacker's PC plays its own attack a moment later (about half a second plus ping) and makes
  the same hits parried / dodged / jumped, so both screens show the same fight and the same HP.
- **Fix: F6 in an online room** (#3) no longer drops you into local versus. During a match it does nothing; after a
  match it opens the room's select screen on both PCs (new teams + both Ready = rematch).
- **Fix: arena travel rendering** (#4). Travel now uses the game's own map change, which applies each level's fog and
  audio settings (the raw console "open" skipped them).

## 0.1.2 - 2026-10-07
- **Fix: online fight started for one player only.** A PC sent "loaded" only while it was still waiting, so the PC that
  finished loading first waited forever. Now each PC always announces it is ready (verified against a test peer that
  loads first).
- **Fix: could not leave a server** (#1). Network status events re-opened the lobby over the server list after
  Disconnect / Backspace.
- **Fix: new room after a fight opened the move loadout** with no character (#2). The select screen now always opens
  on the team grid.

## 0.1.1 - 2026-10-07
- **Fix: monsters froze on a gamepad Attack** (walked up to the target and stood there). The controller's Attack skips
  the call the mod listened for; any unclassified action now plays the unit's basic move.
- **Fix: online match started on one PC only.** The network helper quit when the game had not checked in for 30 s,
  which a save pick + load can exceed; the late PC lost its connection after receiving the "loaded" message. The helper
  now stays while the game process runs.
- README: the required UE4SS is the dev build `716c1e4`, not the official v3.0.1 release.

## 0.1.0 - 2026-10-07
First public test build.

- **Versus mode** from the title screen (VERSUS button) or in a loaded world: character select inspired by Sparking Zero,
  teams of up to 3 units under a 15-point cap, any Expeditioner, enemy or boss (334 units).
- **Arenas**: fight where your save stands or travel to one of 64 locations.
- **The game's own battle wheel for every unit**: monsters and bosses get Skills (a 6-move loadout chosen on the select
  screen from their full move pool), Items and Attack, with the game's targeting, tooltips, AP gauge and costs.
- **Items**: each team has its own stock per match (3 Healing, 2 Energy, 1 Revive Tint).
- **Boss phases**: phase-up as a hard-to-trigger super move; a boss's phase-1 "death" is a real death.
- **Online 1v1** through a small relay server (Docker image or plain Python): server list, rooms, team select with ready
  checks, turn sync with the defending side as authority, items and loadouts synced.
- Game menu sounds in all versus menus; no fleeing in versus; unique names for unit variants.

Known limits: Revive Tint used by a monster is untested; hero skill-combo timing is replayed, not re-played; free aim
("Viser") damage is synced as a state correction.
