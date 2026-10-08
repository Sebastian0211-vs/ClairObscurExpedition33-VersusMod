# CharForge: custom characters for E33 Versus

Put any 3D model in a versus team. The model *wears* a unit of the game (the **base**): it plays with that unit's
moves, animations, AI and rules, and looks like your model.

## Make a character
Requirements: [Blender](https://www.blender.org/download/) 4.2 or newer (found automatically), and one versus match
already played with the base unit in a team (the mod saves each unit's skeleton to `data/skeletons/` the first time it
fights).

- **Drag and drop:** drag the model file onto `CharForge.exe` (in `ue4ss\Mods\E33Versus\CharForge\`). It lists the
  bases you can use, then asks for a name and a cost.
- **Command line** (from the repo, Python 3.8+):
  ```
  python tools/charforge/charforge.py bases
  python tools/charforge/charforge.py add MyModel.glb --base hero:Maelle --name "My hero" --cost 5
  python tools/charforge/charforge.py add Robot.fbx --base enemy:CZ_ChromaVerso --name "Robot"
  python tools/charforge/charforge.py list
  python tools/charforge/charforge.py remove Robot
  ```
  Options: `--scale 1.2` (size relative to the base), `--maxtex 2048` (texture size), `--hide-weapons` (hide the
  base's weapon meshes), `--stretch 0` (keep the model's own limb lengths instead of fitting them to the base's bones),
  `--bonemap map.json` (fix the bone matching, see below), `--force` (rebuild), `--mod <dir>` (the `E33Versus` folder
  when it is not found automatically).

Then in game: **VERSUS** -> character select -> **Custom** tab (Q/E). The result is `Custom/<id>/`; edit
`character.lua` to rename it, change its cost or its base (re-run CharForge after changing the base).

## Models that work
Anything Blender imports: `.glb/.gltf`, `.fbx`, `.obj`, `.vrm`, `.dae`, `.blend`, `.usd`, `.stl`, `.ply`.

- **Rigged humanoids** (Mixamo, VRM, Unreal/Unity humanoids, Rigify, most game rips) get their arms, legs, spine,
  head and fingers (when both skeletons name them: thumb/index/middle/ring/pinky) moved by the base's animations. Each
  limb piece is stretched to the base's bone length so the joints meet. The skeleton is read by its shape, not by bone names: hips = common parent of
  the feet, legs/arms/spine/head = the chains to the lowest, outermost and highest bones, facing from the feet.
- **Models without a skeleton** are carried whole by the base's hips (they follow every dash, jump and hit, without
  bending).
- Base colour textures and material colours are kept (normal, roughness and emissive maps are not used). Textures
  that are not where the model file expects them are found by name in the folders around it. Very dense models (100k+ triangles) take a few seconds to
  build when the fight starts.
- Pick a base shaped like the model: a humanoid on a hero or a humanoid enemy (Chroma heroes, Chalier, Dualliste...).

How it renders: the model is cut into one rigid piece per bone and the mod rebuilds the pieces at runtime
(ProceduralMeshComponent) on the base's skeleton, whose own meshes are hidden but keep animating. Joints therefore
bend as rigid parts (like an action figure), not as a smooth skin.

In battle the character shows its own name in the battle texts, and its portrait in the team HUD and the turn order.

## Fixing the bone matching
`Custom/<id>/forge_report.json` lists the matches (`model bone -> game bone`). To change some, write a JSON file
`{"mixamorig:LeftForeArm": "lowerarm_l", ...}` (game bone names are in `data/skeletons/<base>.tsv`) and pass it with
`--bonemap`.

## Online
Gameplay only depends on the base unit, so both players stay in sync. To see the custom look, the opponent needs the
same `Custom/<id>` folder (send it to them); without it they see the base unit. Each character carries a version stamp
(first line of `mesh.lua`): when both players have the folder but different versions, the select screen says
"Other version on your PC" and each PC shows its own.

## Limits
- Joints are rigid pieces: no smooth skin (that needs a real skeletal mesh, made in Unreal Editor).
- Bones other than hips/spine/neck/head/arms/legs/fingers (jaw, tail, ears, hair, cloth) follow their parent.
- One hero per match: a custom character on a hero base and that hero cannot be in the same match (the party has each
  hero once).
- A unit can be a base once it has fought in a versus match (its skeleton is saved then).
- The victory screen still shows the base unit.

## Licences
You choose the models. Models you did not make keep their own licence: check it before sharing a `Custom/` folder.
Nothing in `Custom/` is part of this repository.
