# E33 Versus character forge - Blender side (runs headless: blender -b --python blender_convert.py -- <args>).
# Turns any model Blender can import into a "custom character" the mod builds at runtime: one rigid mesh section per
# (game bone, material), each expressed in that bone's local space, so the game's own animations move it.
#
# How a model is fitted onto a game skeleton (the base unit's skeleton, dumped in game to a .tsv):
#  1. both skeletons are read structurally: hips = common ancestor of the two feet, spine/neck/head = path from the
#     hips to the highest bone, arms = paths to the two outermost bones, legs = paths to the two lowest bones;
#  2. facing comes from the feet (ankle -> toe = forward), left = up x forward;
#  3. chains are matched slot by slot (arms from the hand back, legs from the thigh down, spine by height fraction);
#  4. every vertex goes to its strongest bone's mapped ancestor; each segment is rotated so its bone points the way
#     the game bone points in the game's reference pose, then moved onto the game bone.
# Models without an armature are attached whole to the hips bone.
import bpy, bmesh, sys, os, math, json, re
from mathutils import Vector, Quaternion, Matrix

def args():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = {}
    i = 0
    while i < len(a):
        k = a[i].lstrip("-"); v = a[i + 1] if i + 1 < len(a) else ""
        out[k] = v; i += 2
    return out

A = args()
MODEL, SKEL, OUTDIR = os.path.abspath(A["model"]), os.path.abspath(A["skeleton"]), os.path.abspath(A["out"])
CID = A.get("id") or re.sub(r"[^A-Za-z0-9_]", "_", os.path.splitext(os.path.basename(MODEL))[0])
NAME = A.get("name") or CID
MAXTEX = int(A.get("maxtex") or 1024)
SCALE_MUL = float(A.get("scale") or 1.0)
BONEMAP = json.loads(open(A["bonemap"], encoding="utf-8").read()) if A.get("bonemap") else {}
REPORT = {"model": os.path.basename(MODEL), "warnings": []}
def warn(s): print("[charforge] WARNING " + s); REPORT["warnings"].append(s)
def info(s): print("[charforge] " + s)

# ---------------------------------------------------------------- import
def import_model(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ext = os.path.splitext(path)[1].lower()
    if ext in (".glb", ".gltf"): bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".vrm":
        import shutil, tempfile
        tmp = os.path.join(tempfile.gettempdir(), "charforge_vrm.glb"); shutil.copyfile(path, tmp)
        bpy.ops.import_scene.gltf(filepath=tmp)
    elif ext == ".fbx": bpy.ops.import_scene.fbx(filepath=path, automatic_bone_orientation=True)
    elif ext == ".obj": bpy.ops.wm.obj_import(filepath=path)
    elif ext == ".stl": bpy.ops.wm.stl_import(filepath=path)
    elif ext == ".ply": bpy.ops.wm.ply_import(filepath=path)
    elif ext in (".usd", ".usda", ".usdc", ".usdz"): bpy.ops.wm.usd_import(filepath=path)
    elif ext == ".dae": bpy.ops.wm.collada_import(filepath=path)
    elif ext == ".blend":
        with bpy.data.libraries.load(path, link=False) as (src, dst): dst.objects = list(src.objects)
        for o in dst.objects:
            if o: bpy.context.scene.collection.objects.link(o)
    else: raise SystemExit("unsupported model format: " + ext)

import_model(MODEL)
bpy.context.view_layer.update()

def mesh_armature(o):
    for m in o.modifiers:
        if m.type == 'ARMATURE' and m.object: return m.object
    if o.parent and o.parent.type == 'ARMATURE' and o.parent_type in ('ARMATURE', 'OBJECT') and o.vertex_groups: return o.parent
    return None

meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH' and len(o.data.polygons) > 0 and not o.hide_get() and not o.hide_render]
arms = {}
for o in meshes:
    a = mesh_armature(o)
    if a: arms[a] = arms.get(a, 0) + len(o.data.polygons)
ARM = max(arms, key=arms.get) if arms else None
# meshes that belong to another armature or to none: keep them only when there is no armature at all (static props)
if ARM: meshes = [o for o in meshes if mesh_armature(o) == ARM or (o.parent and o.parent == ARM)]
if not meshes: raise SystemExit("no mesh found in " + MODEL)
info("armature: %s, meshes: %s" % (ARM.name if ARM else None, [o.name for o in meshes]))

# ---------------------------------------------------------------- skeletons as plain data: name -> {parent, head(Vector, RH, cm-or-m), children}
class Skel:
    def __init__(self): self.b = {}; self.order = []
    def add(self, name, parent, head, tail=None, rot=None):
        self.b[name] = {"parent": parent, "head": head, "tail": tail, "rot": rot, "children": []}; self.order.append(name)
    def link(self):
        for n, d in self.b.items():
            if d["parent"] in self.b: self.b[d["parent"]]["children"].append(n)
            else: d["parent"] = None
    def path(self, frm, to):           # bones from frm (excluded) down to `to` (included)
        p = []; n = to
        while n and n != frm: p.append(n); n = self.b[n]["parent"]
        return list(reversed(p)) if n == frm else None
    def ancestors(self, n):
        out = []
        while n: out.append(n); n = self.b[n]["parent"]
        return out
    def lca(self, a, b):
        sa = set(self.ancestors(a))
        for n in self.ancestors(b):
            if n in sa: return n
    def depth_desc(self, n):            # longest chain below n
        c = self.b[n]["children"]
        return 1 + (max(self.depth_desc(x) for x in c) if c else 0)

def qmul(a, b):  # (x,y,z,w)
    ax, ay, az, aw = a; bx, by, bz, bw = b
    return (aw*bx + ax*bw + ay*bz - az*by, aw*by - ax*bz + ay*bw + az*bx, aw*bz + ax*by - ay*bx + az*bw, aw*bw - ax*bx - ay*by - az*bz)
def qrot(q, v):
    x, y, z, w = q
    u = Vector((x, y, z)); vv = Vector(v)
    return 2.0 * u.dot(vv) * u + (w*w - u.dot(u)) * vv + 2.0 * w * u.cross(vv)

def read_game_skeleton(path):
    s = Skel(); world = {}
    rows = [l.rstrip("\n").split("\t") for l in open(path, encoding="utf-8") if l.strip()]
    for r in rows:
        name, parent = r[1], r[2]
        f = [float(x) for x in r[3].split()]
        lp, lq, ls = (f[0], f[1], f[2]), (f[3], f[4], f[5], f[6]), (f[7], f[8], f[9])
        if parent in world:
            pp, pq, ps = world[parent]
            p = Vector(pp) + qrot(pq, Vector((lp[0]*ps[0], lp[1]*ps[1], lp[2]*ps[2])))
            q = qmul(pq, lq); sc = (ps[0]*ls[0], ps[1]*ls[1], ps[2]*ls[2])
        else:
            p, q, sc = Vector(lp), lq, ls
        world[name] = (tuple(p), q, sc)
        # UE (left-handed, Y right) -> right-handed by mirroring Y
        head = Vector((p[0], -p[1], p[2]))
        rq = Quaternion((q[3], -q[0], q[1], -q[2]))   # mathutils order w,x,y,z
        s.add(name, parent if parent not in ("None", "") else None, head, None, rq)
    s.link()
    return s

def read_blender_skeleton(arm):
    s = Skel(); mw = arm.matrix_world
    for b in arm.data.bones:
        s.add(b.name, b.parent.name if b.parent else None, mw @ b.head_local, mw @ b.tail_local, None)
    s.link()
    return s

# ---------------------------------------------------------------- structural humanoid reading
HELPER = re.compile(r"(^|[^a-z])(ik|vb|ikfk|ctrl|ctl|ctr|helper|prop|weapon|camera|attach|socket|target|pole)([^a-z]|$)|^ik_|^vb ", re.I)
def read_body(s, label):
    # IK targets, virtual bones, weapon/prop/camera sockets and everything under them are not part of the body
    def helper(n):
        while n:
            if HELPER.search(n): return True
            n = s.b[n]["parent"]
        return False
    names = [n for n in s.order if not helper(n)]
    # Ignore helper bones far from the body cloud (IK targets, weapons, cameras...) by keeping bones with children or
    # with a parent; leaves are fine. Tips: lowest two (feet), highest (head), outermost two (hands).
    pts = {n: s.b[n]["head"] for n in names}
    def kids(n): return [c for c in s.b[n]["children"] if c in pts]
    zs = sorted(pts[n].z for n in names)
    zmin, zmax = zs[0], zs[-1]
    height = zmax - zmin
    if height <= 0: return None
    # feet: lowest bones; pick two with the largest lateral separation among the lowest 15%
    low = [n for n in names if pts[n].z <= zmin + 0.15 * height]
    if len(low) < 2: return None
    best = None
    for i in range(len(low)):
        for j in range(i + 1, len(low)):
            a, b = low[i], low[j]
            l = s.lca(a, b)
            if not l or l in (a, b): continue
            d = (pts[a] - pts[b]).xy.length
            if not best or d > best[0]: best = (d, a, b, l)
    if not best: return None
    _, fa, fb, hips = best
    def sub_depth(n):
        c = kids(n)
        return 1 + (max(sub_depth(x) for x in c) if c else 0)
    def main_chain(start):
        """follow the child with the deepest subtree (corrective / twist leaves are skipped)"""
        out = [start]; n = start
        while kids(n):
            n = max(kids(n), key=lambda x: (sub_depth(x), (pts[x] - pts[out[-1]]).length)); out.append(n)
        return out
    # head: a bone named head under the hips (not under a leg), else the highest one
    legA, legB = s.path(hips, fa)[0], s.path(hips, fb)[0]
    def under(n, root): return root in s.ancestors(n)
    torso = [n for n in names if under(n, hips) and n != hips and not under(n, legA) and not under(n, legB)]
    if not torso: return None
    named_head = [n for n in torso if re.search(r"(^|[^a-z])head$", n.lower())]
    head_tip = min(named_head, key=lambda n: len(s.ancestors(n))) if named_head else max(torso, key=lambda n: pts[n].z)
    spine_path = s.path(hips, head_tip)
    leg_chain = [main_chain(legA)[:4], main_chain(legB)[:4]]
    # facing from the feet: ankle -> toe, averaged
    def foot_fwd(ch):
        if len(ch) >= 4: v = pts[ch[3]] - pts[ch[2]]
        elif len(ch) >= 2: v = pts[ch[-1]] - pts[ch[-2]]
        else: return Vector((0, 0, 0))
        v = v.copy(); v.z = 0
        return v
    fwd = foot_fwd(leg_chain[0]) + foot_fwd(leg_chain[1])
    up = Vector((0, 0, 1))
    if fwd.length < 1e-6: fwd = Vector((0, -1, 0)); warn(label + ": no foot direction, assuming facing -Y")
    fwd.normalize()
    left = up.cross(fwd).normalized()
    # arms: outermost bones on each side among torso bones not on the spine path
    side_pts = [n for n in torso if n not in spine_path]
    hp = pts[hips]
    def lat(n): return (pts[n] - hp).dot(left)
    arms = {}
    if side_pts:
        L = max(side_pts, key=lat); R = min(side_pts, key=lat)
        for side, tip in (("l", L), ("r", R)):
            if (side == "l" and lat(tip) <= 0) or (side == "r" and lat(tip) >= 0): continue
            branch = s.lca(tip, head_tip)
            chain = s.path(branch, tip)
            # the outermost bone can be a finger tip or a corrective bone: re-follow the main chain from the branch,
            # then cut at the hand (named "hand", or the finger split: 3+ children with chains below them)
            chain = s.path(branch, tip)
            chain = main_chain(chain[0]) if chain else []
            named = [i for i, n in enumerate(chain) if i >= 1 and re.search(r"hand", n.lower())]
            hand_i = named[0] if named else len(chain) - 1
            if not named:
                for i, n in enumerate(chain):
                    if i >= 2 and sum(1 for c in kids(n) if sub_depth(c) >= 2) >= 3:
                        hand_i = i; break
            arms[side] = {"branch": branch, "chain": chain[:hand_i + 1]}
    legs = {}
    for ch in leg_chain:
        legs["l" if lat(ch[-1]) > 0 else "r"] = ch
    # spine = path hips -> arms branch (chest); neck/head = chest -> head tip
    chest = None
    for side in ("l", "r"):
        if side in arms and arms[side]["branch"] in spine_path:
            b = arms[side]["branch"]
            if chest is None or spine_path.index(b) > spine_path.index(chest): chest = b
    if chest is None: chest = spine_path[max(0, len(spine_path) // 2 - 1)]
    ci = spine_path.index(chest)
    body = {"hips": hips, "spine": spine_path[:ci + 1], "neck": spine_path[ci + 1:], "arm_l": arms.get("l", {}).get("chain", []),
            "arm_r": arms.get("r", {}).get("chain", []), "leg_l": legs.get("l", []), "leg_r": legs.get("r", []),
            "up": up, "fwd": fwd, "left": left, "height": height, "zmin": zmin}
    info("%s: hips=%s spine=%s neck=%s armL=%s armR=%s legL=%s legR=%s" % (label, hips, body["spine"], body["neck"], body["arm_l"], body["arm_r"], body["leg_l"], body["leg_r"]))
    return body

def map_chain(c, g, align):
    """custom chain -> game chain. align: 'start', 'end' or 'frac'."""
    m = {}
    if not c or not g: return m
    if align == "frac":
        for i, n in enumerate(c):
            t = i / max(1, len(c) - 1) if len(c) > 1 else 0
            m[n] = g[round(t * (len(g) - 1))]
    elif align == "end":
        for k in range(1, min(len(c), len(g)) + 1): m[c[-k]] = g[-k]
    else:
        for k in range(min(len(c), len(g))): m[c[k]] = g[k]
    return m

GAME = read_game_skeleton(SKEL)
gbody = read_body(GAME, "game")
if not gbody: raise SystemExit("could not read the game skeleton as a body: " + SKEL)
GH = GAME.b[gbody["hips"]]["head"]

# ---------------------------------------------------------------- global fit: rotate/scale/translate the model into the game frame
CUST = read_blender_skeleton(ARM) if ARM else None
cbody = read_body(CUST, "model") if CUST else None
def basis(b): return Matrix((b["fwd"], b["left"], b["up"])).transposed()   # columns fwd,left,up
mapping = {}
if cbody:
    R = basis(gbody) @ basis(cbody).transposed()
    k = gbody["height"] / cbody["height"] * SCALE_MUL
    CH = CUST.b[cbody["hips"]]["head"]
    # align feet level: model's lowest point on the game's lowest point, hips horizontally on hips
    def fit(v):
        w = R @ ((v - CH) * k)
        return Vector((w.x + GH.x, w.y + GH.y, w.z + (CH.z - cbody["zmin"]) * k + gbody["zmin"]))
    mapping[cbody["hips"]] = gbody["hips"]
    mapping.update(map_chain(cbody["spine"], gbody["spine"], "frac"))
    mapping.update(map_chain(cbody["neck"], gbody["neck"], "end" if len(gbody["neck"]) >= len(cbody["neck"]) else "frac"))
    for side in ("l", "r"):
        mapping.update(map_chain(cbody["arm_" + side], gbody["arm_" + side], "end"))
        mapping.update(map_chain(cbody["leg_" + side], gbody["leg_" + side], "start"))
    mapping.update({k2: v2 for k2, v2 in BONEMAP.items() if v2 in GAME.b})
    REPORT["bonemap"] = mapping
    info("bone map: %d model bones -> game bones" % len(mapping))
else:
    # static model: bounding box onto the game body, everything on the hips
    allv = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
    zmin = min(v.z for v in allv); zmax = max(v.z for v in allv)
    cx = sum(v.x for v in allv) / len(allv); cy = sum(v.y for v in allv) / len(allv)
    k = gbody["height"] / max(1e-6, zmax - zmin) * SCALE_MUL
    R = basis(gbody) @ Matrix(((0, -1, 0), (1, 0, 0), (0, 0, 1))).transposed().transposed()  # glTF/Blender front -Y
    R = basis(gbody) @ Matrix((Vector((0, -1, 0)), Vector((1, 0, 0)), Vector((0, 0, 1)))).transposed().transposed()
    def fit(v):
        w = R @ (Vector((v.x - cx, v.y - cy, v.z - zmin)) * k)
        return Vector((w.x + GH.x, w.y + GH.y, w.z + gbody["zmin"]))
    warn("model has no armature: attached whole to " + gbody["hips"] + " (it follows the body, limbs do not bend)")

# per mapped custom bone: segment transform = rotate the bone onto the game bone's direction, then move onto it
def chain_next(body, s, n):
    for key in ("spine", "neck", "arm_l", "arm_r", "leg_l", "leg_r"):
        ch = body[key]
        if n in ch:
            i = ch.index(n)
            if i + 1 < len(ch): return ch[i + 1]
            if key == "spine" and body["neck"]: return body["neck"][0]
    if n == body["hips"] and body["spine"]: return body["spine"][0]
    return None

seg_xf = {}   # custom bone -> (game bone, function world_model_vertex -> game-RH component vertex)
if cbody:
    for c, g in mapping.items():
        ch = fit(CUST.b[c]["head"])
        gh = GAME.b[g]["head"]
        rot = Quaternion()
        cn, gn = chain_next(cbody, CUST, c), chain_next(gbody, GAME, g)
        if cn and gn:
            dc = fit(CUST.b[cn]["head"]) - ch; dg = GAME.b[gn]["head"] - gh
            if dc.length > 1e-6 and dg.length > 1e-6: rot = dc.normalized().rotation_difference(dg.normalized())
        seg_xf[c] = (g, ch, gh, rot)
    # end bones (hands, head, feet ends) inherit their parent's rotation
    for c in list(seg_xf):
        g, ch, gh, rot = seg_xf[c]
        if chain_next(cbody, CUST, c) is None:
            p = CUST.b[c]["parent"]
            while p and p not in seg_xf: p = CUST.b[p]["parent"]
            if p: seg_xf[c] = (g, ch, gh, seg_xf[p][3])

def resolve(bone):
    """custom bone -> mapped custom bone (itself or nearest mapped ancestor)"""
    n = bone
    while n and n not in seg_xf: n = CUST.b[n]["parent"] if n in CUST.b else None
    return n or (cbody["hips"] if cbody else None)

# ---------------------------------------------------------------- materials / textures
os.makedirs(OUTDIR, exist_ok=True)
mat_index = {}; materials = []
def find_base_image(mat):
    if not mat or not mat.use_nodes: return None, (1, 1, 1, 1)
    col = (1, 1, 1, 1)
    for n in mat.node_tree.nodes:
        if n.type == 'BSDF_PRINCIPLED':
            inp = n.inputs.get("Base Color")
            if inp:
                col = tuple(inp.default_value)
                stack = [l.from_node for l in inp.links]
                seen = set()
                while stack:
                    x = stack.pop()
                    if x in seen: continue
                    seen.add(x)
                    if x.type == 'TEX_IMAGE' and x.image: return x.image, col
                    for i in x.inputs:
                        for l in i.links: stack.append(l.from_node)
    for n in mat.node_tree.nodes:
        if n.type == 'TEX_IMAGE' and n.image: return n.image, col
    return None, col

def material_slot(mat):
    key = mat.name if mat else "_none"
    if key in mat_index: return mat_index[key]
    img, col = find_base_image(mat)
    entry = {"color": [round(c, 4) for c in col[:4]]}
    if img and img.name in tex_files:
        entry["tex"] = tex_files[img.name]; entry["color"] = [1, 1, 1, 1]
    elif img:
        try:
            im = img.copy()
            w, h = im.size
            if max(w, h) > MAXTEX:
                f = MAXTEX / max(w, h); im.scale(max(1, int(w * f)), max(1, int(h * f)))
            fn = "tex_%d.png" % (len(tex_files) + 1)
            sc = bpy.context.scene
            # "Standard": the default AgX view transform would bake a tone curve into the saved colours
            sc.view_settings.view_transform = 'Standard'; sc.view_settings.look = 'None'
            sc.view_settings.exposure = 0.0; sc.view_settings.gamma = 1.0
            sc.render.image_settings.file_format = 'PNG'; sc.render.image_settings.color_mode = 'RGBA'
            im.save_render(os.path.join(OUTDIR, fn), scene=sc)
            tex_files[img.name] = fn
            entry["tex"] = fn; entry["color"] = [1, 1, 1, 1]
        except Exception as e:
            warn("texture of %s not exported: %s" % (key, e))
    if "tex" not in entry:
        # untextured material: a tiny texture of its colour (the game material takes colour from a texture)
        fn = "col_%d.png" % (len(materials) + 1)
        def srgb(c): return 255 * (12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055)
        write_png(os.path.join(OUTDIR, fn), 4, 4, [int(max(0, min(255, round(srgb(c))))) for c in entry["color"][:3]] + [255])
        entry["tex"] = fn
    mat_index[key] = len(materials) + 1; materials.append(entry)
    return mat_index[key]

tex_files = {}
def write_png(path, w, h, rgba):
    import zlib, struct
    raw = b"".join(b"\x00" + bytes(rgba) * w for _ in range(h))
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))

# ---------------------------------------------------------------- geometry
# sections[(game bone, mat)] = {"v": [], "n": [], "uv": [], "t": [], "index": {}}
sections = {}
def section(g, m):
    k = (g, m)
    if k not in sections: sections[k] = {"bone": g, "mat": m, "v": [], "n": [], "uv": [], "t": [], "index": {}}
    return sections[k]

MIR = lambda v: (v.x, -v.y, v.z)   # RH -> UE
deps = bpy.context.evaluated_depsgraph_get()
total_tris = 0
for o in meshes:
    # rest geometry: no armature deformation, other modifiers kept (mirror, subdivision levels as set)
    saved = []
    for m in o.modifiers:
        if m.type == 'ARMATURE': saved.append((m, m.show_viewport)); m.show_viewport = False
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    eo = o.evaluated_get(deps)
    me = eo.to_mesh()
    me.calc_loop_triangles()
    mw = o.matrix_world
    nmw = mw.to_3x3().inverted_safe().transposed()
    uvl = me.uv_layers.active.data if me.uv_layers.active else None
    # vertex -> strongest bone (indices survive when no topology modifier is active; fall back to the object's parent bone)
    groups = {g.index: g.name for g in o.vertex_groups}
    same_topo = len(me.vertices) == len(o.data.vertices)
    vbone = []
    if cbody and same_topo:
        for v in o.data.vertices:
            best, bw = None, 0.0
            for ge in v.groups:
                nm = groups.get(ge.group)
                if nm in CUST.b and ge.weight > bw: best, bw = nm, ge.weight
            vbone.append(resolve(best) if best else None)
    elif cbody:
        warn(o.name + ": modifiers change the topology, whole mesh on its parent bone")
    fallback = resolve(o.parent_bone) if (cbody and o.parent_bone) else (cbody["hips"] if cbody else None)
    split = [Vector(l.vector) for l in me.corner_normals] if hasattr(me, "corner_normals") else None
    for tri in me.loop_triangles:
        # triangle goes to the majority bone of its corners
        if cbody:
            bs = [vbone[me.loops[li].vertex_index] if vbone else None for li in tri.loops]
            bs = [b or fallback for b in bs]
            c = max(set(bs), key=bs.count)
            g, ch, gh, rot = seg_xf.get(c, (gbody["hips"], Vector(), GAME.b[gbody["hips"]]["head"], Quaternion()))
        else:
            g, ch, gh, rot = gbody["hips"], None, None, None
        mat = o.material_slots[tri.material_index].material if tri.material_index < len(o.material_slots) else None
        sec = section(g, material_slot(mat))
        gb = GAME.b[g]; ginv = gb["rot"].inverted()
        ids = []
        for li in tri.loops:
            vi = me.loops[li].vertex_index
            p = fit(mw @ me.vertices[vi].co)
            nrm = (nmw @ (split[li] if split else me.vertices[vi].normal))
            nrm = (R @ nrm)
            if rot is not None:
                p = gh + rot @ (p - ch); nrm = rot @ nrm
            lp = ginv @ (p - gb["head"]); ln = (ginv @ nrm).normalized()
            uv = (uvl[li].uv.x, 1.0 - uvl[li].uv.y) if uvl else (0.0, 0.0)
            key = (vi, round(uv[0], 4), round(uv[1], 4), round(ln.x, 2), round(ln.y, 2), round(ln.z, 2))
            idx = sec["index"].get(key)
            if idx is None:
                idx = len(sec["v"]) // 3; sec["index"][key] = idx
                sec["v"].extend(MIR(lp)); sec["n"].extend(MIR(ln)); sec["uv"].extend(uv)
            ids.append(idx)
        # kept as is: verified in game (reversed winding showed back faces, lit from inside)
        sec["t"].extend((ids[0], ids[1], ids[2]))
        total_tris += 1
    eo.to_mesh_clear()
    for m, sv in saved: m.show_viewport = sv

info("%d triangles in %d sections, %d materials" % (total_tris, len(sections), len(materials)))
if total_tris > 120000: warn("very dense model (%d triangles): loading in game will be slow" % total_tris)

# ---------------------------------------------------------------- write
def nums(xs, nd):
    fmt = "%." + str(nd) + "f"
    return ",".join((fmt % x).rstrip("0").rstrip(".") if isinstance(x, float) else str(x) for x in xs)

with open(os.path.join(OUTDIR, "mesh.lua"), "w", encoding="utf-8") as f:
    f.write("-- generated by tools/charforge from %s - mesh sections in game-bone space (cm)\n" % os.path.basename(MODEL))
    f.write("return {\n  materials = {\n")
    for m in materials:
        f.write("    { color = { %s }%s },\n" % (nums(m["color"], 4), (', tex = "%s"' % m["tex"]) if m.get("tex") else ""))
    f.write("  },\n  sections = {\n")
    for s in sections.values():
        f.write('    { bone = "%s", mat = %d,\n      v = { %s },\n      n = { %s },\n      uv = { %s },\n      t = { %s } },\n'
                % (s["bone"], s["mat"], nums(s["v"], 2), nums(s["n"], 3), nums(s["uv"], 4), nums(s["t"], 0)))
    f.write("  },\n}\n")
REPORT.update({"triangles": total_tris, "sections": len(sections), "materials": len(materials)})
with open(os.path.join(OUTDIR, "forge_report.json"), "w", encoding="utf-8") as f: json.dump(REPORT, f, indent=1)
info("wrote " + OUTDIR)

# ---------------------------------------------------------------- portrait (select screen + battle HUD)
def render_portrait(path):
    sc = bpy.context.scene
    # frame the head and shoulders, seen from the front (model space; meshes were not moved)
    if cbody:
        head = CUST.b[cbody["neck"][-1]]["head"] if cbody["neck"] else CUST.b[cbody["spine"][-1]]["head"]
        top = max((o.matrix_world @ v.co).z for o in meshes for v in o.data.vertices)
        fwd, up = cbody["fwd"], cbody["up"]
        size = max(0.25 * cbody["height"], (top - head.z) * 2.2)
        target = Vector((head.x, head.y, head.z + (top - head.z) * 0.35))
    else:
        allv = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
        lo = Vector((min(v.x for v in allv), min(v.y for v in allv), min(v.z for v in allv)))
        hi = Vector((max(v.x for v in allv), max(v.y for v in allv), max(v.z for v in allv)))
        target = (lo + hi) / 2; size = max(hi - lo) * 1.1; fwd = Vector((0, -1, 0)); up = Vector((0, 0, 1))
    cam_data = bpy.data.cameras.new("forge_cam"); cam_data.type = 'ORTHO'; cam_data.ortho_scale = size
    cam = bpy.data.objects.new("forge_cam", cam_data); sc.collection.objects.link(cam)
    cam.location = target + fwd * (size * 4 + 1.0)
    cam.rotation_euler = (-fwd).to_track_quat('-Z', 'Y').to_euler()
    cam_data.clip_end = size * 20 + 10
    sc.camera = cam
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'; sc.display.shading.color_type = 'TEXTURE'
    sc.display.shading.show_cavity = True
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = 256; sc.render.resolution_percentage = 100
    sc.view_settings.view_transform = 'Standard'
    sc.render.image_settings.file_format = 'PNG'; sc.render.image_settings.color_mode = 'RGBA'
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)

if A.get("portrait", "1") != "0":
    try:
        render_portrait(os.path.join(OUTDIR, "portrait.png")); info("portrait rendered")
    except Exception as e:
        warn("portrait not rendered: %s" % e)
