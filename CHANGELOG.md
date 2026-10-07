# Changelog

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
