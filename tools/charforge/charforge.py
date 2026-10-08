#!/usr/bin/env python3
"""E33 Versus character forge: turn any 3D model into a custom versus character.

    python charforge.py add <model> --base hero:Maelle [--name "Name"] [--cost 5] [--id my_char]
    python charforge.py bases          # bases you can use (skeletons the mod has seen)
    python charforge.py list           # custom characters already installed
    python charforge.py remove <id>
    CharForge.exe <model>              # drag a model onto CharForge.exe: asks for name, base and cost

The model can be anything Blender imports: .glb/.gltf, .fbx, .obj, .vrm, .dae, .blend, .usd, .stl, .ply.
A rigged humanoid (Mixamo, VRM, Unreal/Unity humanoid, Rigify...) gets its limbs moved by the base's animations;
a model without a skeleton is carried whole by the base's hips.

The base is the game unit the character plays as (moves, animations, AI, stats rules): hero:<Frey|Maelle|Lune|Sciel|
Verso|Monoco> or enemy:<DT_jRPG_Enemies row>, e.g. enemy:CZ_ChromaVerso. Its skeleton is needed: the mod writes it to
data/skeletons/ the first time that unit fights in a versus match.

Requires Blender 4.2+ (found automatically, or --blender / BLENDER env var).
"""
import argparse, glob, json, os, re, shutil, subprocess, sys

FROZEN = getattr(sys, "frozen", False)   # CharForge.exe (PyInstaller) shipped in Mods/E33Versus/CharForge/
HERE = os.path.dirname(os.path.abspath(sys.executable if FROZEN else __file__))
REPO_MOD = os.path.normpath(os.path.join(HERE, "..", "..", "mod", "E33Versus"))
SHIPPED_MOD = os.path.normpath(os.path.join(HERE, ".."))
HEROES = {"Frey": "Gustave", "Maelle": "Maelle", "Lune": "Lune", "Sciel": "Sciel", "Verso": "Verso", "Monoco": "Monoco"}


def find_mod(arg):
    """The installed mod folder (ue4ss/Mods/E33Versus) or this repo's mod/E33Versus."""
    cands = [arg] if arg else []
    cands += [os.environ.get("E33VERSUS_MOD", ""), SHIPPED_MOD, REPO_MOD]
    for steam in [r"C:\Program Files (x86)\Steam\steamapps\common", r"D:\SteamLibrary\steamapps\common", r"E:\SteamLibrary\steamapps\common"]:
        cands.append(os.path.join(steam, "Expedition 33", "Sandfall", "Binaries", "Win64", "ue4ss", "Mods", "E33Versus"))
    for c in cands:
        if c and os.path.isdir(os.path.join(c, "Scripts")):
            return os.path.normpath(c)
    sys.exit("E33Versus mod folder not found: pass --mod <...\\ue4ss\\Mods\\E33Versus>")


def find_blender(arg):
    cands = [arg, os.environ.get("BLENDER", ""), shutil.which("blender") or ""]
    cands += sorted(glob.glob(r"C:\Program Files\Blender Foundation\Blender *\blender.exe"), reverse=True)
    cands += sorted(glob.glob(os.path.expanduser(r"~\AppData\Roaming\Blender Foundation\Blender*\blender.exe")), reverse=True)
    cands += ["/usr/bin/blender", "/Applications/Blender.app/Contents/MacOS/Blender"]
    for c in cands:
        if c and os.path.isfile(c):
            return c
    sys.exit("Blender not found: install Blender 4.2+ (blender.org) or pass --blender <path to blender.exe>")


def skeleton_key(base):
    kind, _, name = base.partition(":")
    if kind not in ("hero", "enemy") or not name:
        sys.exit("--base must be hero:<id> or enemy:<row>, e.g. hero:Maelle or enemy:CZ_ChromaVerso")
    if kind == "hero" and name not in HEROES:
        sys.exit("hero ids: " + ", ".join(HEROES))
    return kind, name, ("hero_" if kind == "hero" else "enemy_") + name


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def cmd_add(a):
    mod = find_mod(a.mod)
    model = os.path.abspath(a.model)
    if not os.path.isfile(model):
        sys.exit("model not found: " + model)
    kind, name, key = skeleton_key(a.base)
    skel = os.path.join(mod, "data", "skeletons", key + ".tsv")
    if not os.path.isfile(skel):
        sys.exit("no skeleton for %s yet (%s).\nPlay one versus match with that unit in a team: the mod saves its "
                 "skeleton, then run this again. Available now: python charforge.py bases" % (a.base, skel))
    cid = a.id or re.sub(r"[^A-Za-z0-9_]+", "_", os.path.splitext(os.path.basename(model))[0]).strip("_") or "custom"
    out = os.path.join(mod, "Custom", cid)
    if os.path.isdir(out):
        if not a.force:
            sys.exit("Custom/%s already exists (use --force to rebuild it, or --id for another name)" % cid)
        shutil.rmtree(out)
    os.makedirs(out)
    blender = find_blender(a.blender)
    cmd = [blender, "-b", "--factory-startup", "--python", os.path.join(HERE, "blender_convert.py"), "--",
           "--model", model, "--skeleton", skel, "--out", out, "--id", cid, "--scale", str(a.scale), "--maxtex", str(a.maxtex)]
    if a.bonemap:
        cmd += ["--bonemap", os.path.abspath(a.bonemap)]
    print("converting with " + blender)
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    for line in (r.stdout + r.stderr).splitlines():
        if "[charforge]" in line or "Error" in line or "Traceback" in line or line.startswith("  File"):
            print("  " + line.replace("[charforge] ", ""))
    if r.returncode != 0 or not os.path.isfile(os.path.join(out, "mesh.lua")):
        shutil.rmtree(out, ignore_errors=True)
        sys.exit("conversion failed (Blender exit code %d)" % r.returncode)
    base = ('{ kind = "hero", id = %s }' % lua_str(name)) if kind == "hero" else ('{ kind = "enemy", row = %s }' % lua_str(name))
    with open(os.path.join(out, "character.lua"), "w", encoding="utf-8") as f:
        f.write("-- E33 Versus custom character (made by tools/charforge/charforge.py; edit freely)\n")
        f.write("return {\n")
        f.write("  name = %s,\n" % lua_str(a.name or cid))
        f.write("  base = %s,   -- the unit it plays as: moves, animations, AI\n" % base)
        f.write("  cost = %d,   -- team points (cap 15)\n" % max(1, min(10, a.cost)))
        f.write("  keepWeapons = %s,   -- keep the base unit's weapon meshes visible\n" % ("true" if a.keep_weapons else "false"))
        f.write("  source = %s,\n" % lua_str(os.path.basename(model)))
        f.write("}\n")
    rep = json.load(open(os.path.join(out, "forge_report.json"), encoding="utf-8"))
    print("added Custom/%s: %s, %d triangles, plays as %s, cost %d" % (cid, a.name or cid, rep.get("triangles", 0), a.base, a.cost))
    for w in rep.get("warnings", []):
        print("  warning: " + w)
    print("In game: VERSUS -> character select -> 'Custom' tab (Q/E).")


def cmd_bases(a):
    mod = find_mod(a.mod)
    d = os.path.join(mod, "data", "skeletons")
    files = sorted(glob.glob(os.path.join(d, "*.tsv")))
    if not files:
        print("No skeletons yet: play one versus match; every unit in it becomes usable as a base.")
    for f in files:
        k = os.path.splitext(os.path.basename(f))[0]
        kind, _, name = k.partition("_")
        n = sum(1 for _ in open(f, encoding="utf-8"))
        label = HEROES.get(name, name) if kind == "hero" else name
        print("  --base %-30s %-20s %d bones" % (kind + ":" + name, label, n))


def cmd_list(a):
    mod = find_mod(a.mod)
    for c in sorted(glob.glob(os.path.join(mod, "Custom", "*", "character.lua"))):
        txt = open(c, encoding="utf-8").read()
        nm = re.search(r'name\s*=\s*"([^"]*)"', txt); base = re.search(r"base\s*=\s*(\{[^}]*\})", txt)
        print("  %-20s %-24s %s" % (os.path.basename(os.path.dirname(c)), nm.group(1) if nm else "?", base.group(1) if base else "?"))


def cmd_remove(a):
    mod = find_mod(a.mod)
    p = os.path.join(mod, "Custom", a.id)
    if not os.path.isfile(os.path.join(p, "character.lua")):
        sys.exit("no custom character " + a.id)
    shutil.rmtree(p)
    print("removed Custom/" + a.id)


def interactive(model):
    """Drag-and-drop mode: CharForge.exe <model>."""
    class A: pass
    a = A()
    a.mod, a.model, a.blender, a.bonemap, a.force = None, model, None, None, False
    a.scale, a.maxtex, a.keep_weapons = 1.0, 1024, True
    mod = find_mod(None)
    print("E33 Versus CharForge - model: " + os.path.basename(model) + "\n")
    files = sorted(glob.glob(os.path.join(mod, "data", "skeletons", "*.tsv")))
    if not files:
        print("No base skeleton yet: play one versus match first (every unit in it becomes usable as a base).")
        return
    bases = []
    for f in files:
        k = os.path.splitext(os.path.basename(f))[0]; kind, _, name = k.partition("_")
        bases.append((kind + ":" + name, HEROES.get(name, name) if kind == "hero" else name))
    for i, (b, label) in enumerate(bases, 1):
        print("  %2d. %-28s %s" % (i, b, label))
    while True:
        pick = input("\nPlay as which unit (number): ").strip()
        if pick.isdigit() and 1 <= int(pick) <= len(bases): break
    a.base = bases[int(pick) - 1][0]
    default = os.path.splitext(os.path.basename(model))[0]
    a.name = input("Name [%s]: " % default).strip() or default
    c = input("Cost 1-10 [5]: ").strip()
    a.cost = int(c) if c.isdigit() else 5
    a.id = re.sub(r"[^A-Za-z0-9_]+", "_", a.name).strip("_") or "custom"
    if os.path.isdir(os.path.join(mod, "Custom", a.id)):
        a.force = input("Custom/%s exists, replace it? [y/N]: " % a.id).strip().lower() == "y"
        if not a.force: return
    cmd_add(a)


def main():
    if len(sys.argv) == 2 and os.path.isfile(sys.argv[1]):
        try:
            interactive(sys.argv[1])
        except SystemExit as e:
            if e.code not in (None, 0): print(e.code)
        input("\nPress Enter to close.")
        return
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--mod", help="E33Versus mod folder (default: installed game, then this repo)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("add", help="convert a model into a custom character")
    p.add_argument("model")
    p.add_argument("--base", required=True, help="hero:<id> or enemy:<row>")
    p.add_argument("--name")
    p.add_argument("--id")
    p.add_argument("--cost", type=int, default=5)
    p.add_argument("--scale", type=float, default=1.0, help="size multiplier (1 = the base unit's height)")
    p.add_argument("--maxtex", type=int, default=1024, help="largest texture side in pixels")
    p.add_argument("--bonemap", help="JSON {model bone: game bone} to fix or extend the automatic matching")
    p.add_argument("--keep-weapons", dest="keep_weapons", action="store_true", default=True)
    p.add_argument("--hide-weapons", dest="keep_weapons", action="store_false")
    p.add_argument("--blender")
    p.add_argument("--force", action="store_true", help="rebuild an existing character")
    p.set_defaults(fn=cmd_add)
    sub.add_parser("bases", help="list usable bases").set_defaults(fn=cmd_bases)
    sub.add_parser("list", help="list custom characters").set_defaults(fn=cmd_list)
    p = sub.add_parser("remove", help="delete a custom character"); p.add_argument("id"); p.set_defaults(fn=cmd_remove)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
