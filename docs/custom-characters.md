# Custom characters: status and roadmap

Goal: put any 3D model in a versus team, with working animations and attacks.

Approach: the model *wears* a base unit of the game (hero or enemy). The base keeps moves, animations, AI, stats rules
and online sync; its meshes are hidden but keep animating. CharForge (`tools/charforge/`, Blender) cuts the model into
one rigid piece per bone of the base's skeleton; `Scripts/lib/custom.lua` rebuilds the pieces in game as
ProceduralMeshComponents snapped to those bones. No Unreal Editor needed.

## Done
| Area | What | Verified |
|---|---|---|
| Import | `.glb/.gltf/.fbx/.obj/.vrm/.dae/.blend/.usd/.stl/.ply` through Blender 4.2+ | Soldier, X Bot (Mixamo), Cesium Man (Khronos), Freddy (.blend), Fox (.obj) |
| Skeleton reading | Structural (hips, spine, neck/head, arms, legs), IK/helper bones ignored, facing from feet or L/R names | Mixamo, Khronos, Freddy rig, 7 game skeletons |
| Fingers | Matched by name (thumb/index/middle/ring/pinky) | Mixamo (10), Freddy (8) |
| Fit | Height, facing, per-bone rotation, limb pieces stretched to the base's bone lengths (`--stretch 0` to disable) | in game |
| No skeleton | Whole model rides the hips | Fox .obj on Sciel |
| Look | Base colour textures / colours on a lit game material (M_Characters only takes virtual textures) | in game |
| Textures moved away | Found by file name around the model | Freddy (source/ vs textures/) |
| Portrait | Rendered by Blender, shown in select screen, team HUD (hero bases too) and turn order | in game |
| Name | Custom name in battle texts via `SetTextPropertyByName` (a Lua FText write crashed) | in game, 8 reload cycles |
| Select screen | Custom tab, cost, "plays as", one-per-match check for hero bases | in game |
| Skeleton dumps | Every unit that fights is saved to `data/skeletons/` and becomes a usable base | 7+ bases |
| CharForge | CLI (`add/bases/list/remove`) and drag-and-drop `CharForge.exe` (release build) | exe tested on a mock install |
| Safety | `Custom/` files loaded as data only (word whitelist + empty environment) | hostile files refused in game |
| Stability | Handles dropped on map load / match start, assets preloaded before the battle trigger | 4+4 fight/reload cycles |
| Online | Custom id + version stamp sent; missing folder -> base unit; different version flagged | packing only (no 2-PC match yet) |
| Minimized window | Per-frame work runs from the world tick when the widget ticker is silent | in game (world and battle) |
| Dev | `V.cfg.aiBoth`: the AI plays both teams (automated tests) | used for all tests |

## To test
- [ ] A human playing a custom character on a hero base through the skill wheel (only AI basic attacks were tested).
- [ ] A two-PC online match with custom characters (both with the folder, one without, different versions).
- [ ] Fullscreen mode.
- [ ] A very dense model (100k+ triangles): build time at battle start.
- [ ] Non-humanoid model on a monster base (quadruped, flying...).

## Possible next steps
- [ ] **Smoother joints:** vertices weighted between two bones could be updated per frame (only the joint areas), or
      split into extra pieces; today joints bend like an action figure.
- [ ] **Extra bones:** jaw, tail, ears, hair and cloth follow their parent; map them when the base has matching bones.
- [ ] **Normal / roughness maps:** need a sampler that accepts a runtime texture as a normal map (sRGB off).
- [ ] **Victory screen:** still shows the base unit (name and art).
- [ ] **Bases without a fight:** a "scan" that spawns units once to save their skeletons, so any roster unit can be a
      base without playing it first.
- [ ] **Own moves:** a custom character could get its own move list / loadout preset instead of the base's.
- [ ] **Title screen minimized:** the mod pauses there (nothing ticks in Blueprint at the title); harmless today.
- [ ] **Sharing:** export/import a `Custom/<id>` folder as one zip from the game or CharForge.

## Known limits (by design)
- One hero per match: a custom on a hero base and that hero cannot both fight (the party has each hero once).
- Gameplay is the base's: stats rules, moves, AI and phases come from the base unit.
