-- E33 Versus custom characters: any model (converted by tools/charforge) worn by a base unit of the game.
-- The base unit (hero or DT_jRPG_Enemies row) keeps everything that makes it play: moves, animations, AI, HUD.
-- Its own meshes are hidden (the body keeps animating) and the custom model is rebuilt at runtime as one
-- ProceduralMeshComponent per (bone, material) section, snapped to that bone: the game's animations move it.
--
-- Custom/<id>/character.lua  definition: { name, base = { kind = "hero"|"enemy", id|row }, cost, portrait, ... }
-- Custom/<id>/mesh.lua       sections in bone space (written by tools/charforge)
-- Custom/<id>/*.png          textures (loaded with ImportFileAsTexture2D, applied on a lit game material)
CUSTOM = CUSTOM or {}
CUSTOM.DIR = (E33V_MOD or "") .. "Custom/"
CUSTOM.PMC = "/Script/ProceduralMeshComponent.ProceduralMeshComponent"
-- A lit opaque master material with plain texture samplers. The characters' M_Characters samples VIRTUAL textures
-- only (a runtime-imported Texture2D renders black there), so a prop master material of the game is used instead.
CUSTOM.MATERIAL = "/Game/FX/Packs/Particles_Wind_Control_System/Materials/Master/M_Master_Material"
CUSTOM.TEX_PARAM = "1. Base Map"
CUSTOM.FALLBACK = "/Engine/BasicShapes/BasicShapeMaterial"   -- "Color" vector parameter
CUSTOM.meshCache = CUSTOM.meshCache or {}
CUSTOM.texCache = CUSTOM.texCache or {}
local function log(s) if V and V.log then V.log("CUSTOM " .. s) end end

-- ---------- definitions ----------
local function listDirs(path)
  local out = {}
  local p = io.popen('dir /b /ad "' .. path:gsub("/", "\\") .. '" 2>nul')
  if p then for l in p:lines() do if not l:match("^[_.]") then out[#out + 1] = l end end; p:close() end
  return out
end
-- (Re)read every Custom/<id>/character.lua. Bad files are skipped and logged.
function CUSTOM.scan()
  local defs = {}
  CUSTOM.hashCache = {}
  for _, id in ipairs(listDirs(CUSTOM.DIR)) do
    local f = CUSTOM.DIR .. id .. "/character.lua"
    local h = io.open(f, "r")
    if h then
      h:close()
      local ok, d = pcall(dofile, f)
      if ok and type(d) == "table" and d.base then
        d.id = id; d.name = d.name or id; d.cost = math.max(1, math.min(10, tonumber(d.cost) or 5))
        defs[id] = d
      else log("skipped " .. id .. ": " .. tostring(d)) end
    end
  end
  CUSTOM.defs = defs
  return defs
end
function CUSTOM.def(id) if not CUSTOM.defs then CUSTOM.scan() end; return CUSTOM.defs[id] end
-- A select-screen unit for a custom character: the base unit's fields + custom = id (all versus code keeps working
-- on kind/id/row; only the name, cost, portrait and the look change).
function CUSTOM.unit(id)
  local d = CUSTOM.def(id); if not d then return nil end
  local u = { custom = id, name = d.name, label = d.name }
  if d.base.kind == "hero" then u.kind, u.id = "hero", d.base.id else u.kind, u.row = "enemy", d.base.row end
  return u
end
function CUSTOM.list()
  local out = {}
  for id in pairs(CUSTOM.scan()) do local u = CUSTOM.unit(id); if u then out[#out + 1] = u end end
  table.sort(out, function(a, b) return a.name < b.name end)
  for _, u in ipairs(out) do u.label = ("[%d] %s"):format(CUSTOM.def(u.custom).cost, u.name) end
  return out
end

-- Display name of the unit a custom character plays as.
function CUSTOM.baseName(id)
  local d = CUSTOM.def(id); if not d then return "?" end
  if d.base.kind == "hero" then
    for _, h in ipairs(V and V.HEROES or {}) do if h.id == d.base.id then return h.label end end
    return d.base.id
  end
  return (ROSTER and ROSTER[d.base.row] or {}).name or d.base.row
end
-- A hero exists once in the save's party: a custom character on a hero base and that hero (or another custom
-- character on the same hero) cannot be in the match together. Returns a message, or nil when u can be picked.
function CUSTOM.heroClash(u)
  if not (u and u.kind == "hero") then return nil end
  for _, side in ipairs({ "A", "B" }) do
    for i = 1, 3 do
      local o = V.cfg[side][i]
      if o and o.kind == "hero" and o.id == u.id and (o.custom or u.custom) then
        return ("%s already uses %s's body (one per match)"):format(o.name or o.id, CUSTOM.baseNameOfHero(u.id))
      end
    end
  end
end
function CUSTOM.baseNameOfHero(id) for _, h in ipairs(V and V.HEROES or {}) do if h.id == id then return h.label end end; return id end

-- Version stamp of a character's look (first line of mesh.lua, written by CharForge): online, both PCs compare it.
function CUSTOM.hash(id)
  CUSTOM.hashCache = CUSTOM.hashCache or {}
  if CUSTOM.hashCache[id] ~= nil then return CUSTOM.hashCache[id] or nil end
  local h, f = nil, io.open(CUSTOM.DIR .. id .. "/mesh.lua", "r")
  if f then h = (f:read("l") or ""):match("charforge%-hash: (%x+)"); f:close() end
  CUSTOM.hashCache[id] = h or false
  return h
end

-- ---------- assets ----------
function CUSTOM.mesh(id)
  local m = CUSTOM.meshCache[id]
  if m then return m end
  local ok, data = pcall(dofile, CUSTOM.DIR .. id .. "/mesh.lua")
  assert(ok and type(data) == "table", "mesh.lua of " .. id .. ": " .. tostring(data))
  -- Lua tables in the shape the UFunction wants, built once per character (spawns reuse them)
  for _, s in ipairs(data.sections) do
    local v, n, uv, t = {}, {}, {}, {}
    for i = 1, #s.v, 3 do v[#v + 1] = { X = s.v[i], Y = s.v[i + 1], Z = s.v[i + 2] }; n[#n + 1] = { X = s.n[i], Y = s.n[i + 1], Z = s.n[i + 2] } end
    for i = 1, #s.uv, 2 do uv[#uv + 1] = { X = s.uv[i], Y = s.uv[i + 1] } end
    for i = 1, #s.t do t[i] = s.t[i] end
    s.V, s.N, s.UV, s.T = v, n, uv, t
    s.v, s.n, s.uv, s.t = nil, nil, nil, nil
  end
  CUSTOM.meshCache[id] = data
  return data
end
local function loadObj(path)
  local name = path:match("([^/]+)$")
  local o = StaticFindObject(path .. "." .. name)
  if not (o and o:IsValid()) then pcall(LoadAsset, path); o = StaticFindObject(path .. "." .. name) end
  return (o and o:IsValid()) and o or nil
end
function CUSTOM.texture(id, file)
  local key = id .. "/" .. file
  local t = CUSTOM.texCache[key]
  if t and t:IsValid() then return t end
  local krl = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
  local path = (CUSTOM.DIR .. key):gsub("/", "\\")
  t = krl:ImportFileAsTexture2D(FindFirstOf("PlayerController"), path)
  if t and t:IsValid() then CUSTOM.texCache[key] = t; return t end
  log("texture not loaded: " .. path)
end
-- Portrait for the select screen and the HUD: Custom/<id>/portrait.png (rendered by tools/charforge).
function CUSTOM.portrait(id)
  local h = io.open(CUSTOM.DIR .. id .. "/portrait.png", "rb")
  if not h then return nil end
  h:close()
  return CUSTOM.texture(id, "portrait.png")
end
-- Team-1 HUD portrait. Hero portraits are re-loaded from the character by the widget itself (SetPortraitImage /
-- LoadFromCharacter at turn changes), so the custom one is re-applied after those calls (hook below).
CUSTOM.hud = CUSTOM.hud or {}   -- widget address -> custom id
CUSTOM.PORTRAIT_W = "/Game/UI/Widgets/HUD_Battle/SubWidget/Characters/WBP_HUD_Battle_CharacterPortrait.WBP_HUD_Battle_CharacterPortrait_C"
local function paintPortrait(widget, t)
  for _, n in ipairs({ "Character_Portrait_Selected", "Character_Portrait_Damaged" }) do
    pcall(function() widget[n]:SetBrushFromTexture(t, false) end)
  end
end
function CUSTOM.setPortrait(widget, id)
  local t = CUSTOM.portrait(id)
  if not (t and widget and widget:IsValid()) then return end
  CUSTOM.hud[widget:GetAddress()] = id
  paintPortrait(widget, t)
  CUSTOM.hookPortraits()
end
function CUSTOM.onPortraitRefresh(ctx)
  local w = ctx:get()
  local id = w and CUSTOM.hud[w:GetAddress()]
  if not id then return end
  local t = CUSTOM.portrait(id)
  if t then paintPortrait(w, t) end
end
function CUSTOM.hookPortraits()
  if E33V_CUSTOM_PORTRAIT_HOOKS2 then return end
  local n = 0
  for _, fn in ipairs({ "SetPortraitImage", "SetPortrait", "LoadFromCharacter", "OnCharacterTurnStart", "OnHPChanged", "OnResurrect" }) do
    if pcall(RegisterHook, CUSTOM.PORTRAIT_W .. ":" .. fn, function(ctx) pcall(CUSTOM.onPortraitRefresh, ctx) end) then n = n + 1 end
  end
  -- turn order (top left): each portrait widget gets its character through SetCharacter
  if pcall(RegisterHook, CUSTOM.TURN_W .. ":SetCharacter", function(ctx, who) pcall(CUSTOM.onTurnOrderPortrait, ctx, who) end) then n = n + 1 end
  E33V_CUSTOM_PORTRAIT_HOOKS2 = n > 0
  log("portrait hooks: " .. n)
end
CUSTOM.TURN_W = "/Game/UI/Widgets/HUD_Battle/SubWidget/TurnOrder/WBP_HUD_TurnOrder_Portrait.WBP_HUD_TurnOrder_Portrait_C"
-- the custom id of a battle character, from the actor or one of its components (the stats component)
function CUSTOM.idOf(obj)
  if not (obj and obj.IsValid and obj:IsValid() and V and V.customOf) then return nil end
  local id = V.customOf[obj:GetAddress()]
  if id then return id end
  local ok, owner = pcall(function() return obj:GetOwner() end)
  if ok and owner and owner:IsValid() then return V.customOf[owner:GetAddress()] end
end
function CUSTOM.onTurnOrderPortrait(ctx, who)
  local w = ctx:get()
  local c = who and who:get()
  local id = CUSTOM.idOf(c)
  if not id then return end
  local t = CUSTOM.portrait(id)
  if not t then return end
  for _, n in ipairs({ "Portrait_Ally", "Portrait_enemy", "Portrait_EnemyAlly" }) do
    pcall(function() w[n]:SetBrushFromTexture(t, false) end)
  end
end
-- One dynamic instance of the game's character material per (custom character, material slot) and actor.
function CUSTOM.material(actor, id, m)
  local kml = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
  local parent = loadObj(CUSTOM.MATERIAL)
  local t = m.tex and CUSTOM.texture(id, m.tex)
  if parent and t then
    local mid = kml:CreateDynamicMaterialInstance(actor, parent, FName("E33V_" .. id), 0)
    mid:SetTextureParameterValue(FName(CUSTOM.TEX_PARAM), t)
    return mid
  end
  local fb = loadObj(CUSTOM.FALLBACK)
  if not fb then return nil end
  local mid = kml:CreateDynamicMaterialInstance(actor, fb, FName("E33V_" .. id), 0)
  local c = m.color or { 1, 1, 1, 1 }
  mid:SetVectorParameterValue(FName("Color"), { R = c[1], G = c[2], B = c[3], A = c[4] or 1 })
  return mid
end

-- ---------- wearing a model ----------
CUSTOM.HIDE = { SkeletalMeshComponent = true, StaticMeshComponent = true, GroomComponent = true, PoseableMeshComponent = true,
  InstancedStaticMeshComponent = true }
local function comps(actor, cls)
  local out = {}
  local r = actor:K2_GetComponentsByClass(StaticFindObject(cls))
  for _, c in pairs(r or {}) do c = c.get and c:get() or c; if c and c:IsValid() then out[#out + 1] = c end end
  return out
end
-- The skeletal mesh that carries the base's animation: the Character mesh, else the component with most bones.
function CUSTOM.body(actor, bone)
  local ok, m = pcall(function() return actor.Mesh end)
  if ok and m and m:IsValid() and (not bone or m:GetBoneIndex(FName(bone)) >= 0) then return m end
  local best, bn = nil, -1
  for _, c in ipairs(comps(actor, "/Script/Engine.SkeletalMeshComponent")) do
    local n = c:GetNumBones()
    if (not bone or c:GetBoneIndex(FName(bone)) >= 0) and n > bn then best, bn = c, n end
  end
  return best
end
-- Hide the base's look but keep its skeleton animating (hidden skinned meshes otherwise skip their pose update).
function CUSTOM.hideBase(actor, body, keep)
  local n = 0
  for _, c in ipairs(comps(actor, "/Script/Engine.PrimitiveComponent")) do
    local cls = c:GetClass():GetFName():ToString()
    local name = c:GetFName():ToString()
    local kept = keep and keep(name, cls)
    if CUSTOM.HIDE[cls] and not kept and not name:find("^E33V_CUSTOM") then
      pcall(function() c:SetHiddenInGame(true, false) end); n = n + 1
    end
  end
  pcall(function() body.VisibilityBasedAnimTickOption = 0 end)   -- AlwaysTickPoseAndRefreshBones
  return n
end
CUSTOM.SEQ = CUSTOM.SEQ or 0
-- Build the custom model on actor. Returns the number of sections built.
function CUSTOM.apply(actor, id)
  local d = CUSTOM.def(id); assert(d, "no custom character " .. tostring(id))
  local t0 = os.clock()
  local data = CUSTOM.mesh(id)
  local body = CUSTOM.body(actor, data.sections[1] and data.sections[1].bone)
  assert(body, "no skeletal mesh on " .. actor:GetFName():ToString())
  local keepWeapons = d.keepWeapons ~= false
  local hidden = CUSTOM.hideBase(actor, body, function(name, cls)
    return keepWeapons and (name:lower():find("weapon") ~= nil)
  end)
  local cls = StaticFindObject(CUSTOM.PMC)
  local mats = {}
  local built, missing = 0, 0
  local identity = { Translation = { X = 0, Y = 0, Z = 0 }, Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
  CUSTOM.parts = CUSTOM.parts or {}
  local parts = {}
  for _, s in ipairs(data.sections) do
    if body:GetBoneIndex(FName(s.bone)) < 0 then missing = missing + 1
    else
      local c = actor:AddComponentByClass(cls, true, identity, false)
      c:K2_AttachToComponent(body, FName(s.bone), 2, 2, 2, false)   -- SnapToTarget: the section's space IS the bone's
      c:CreateMeshSection_LinearColor(0, s.V, s.T, s.N, s.UV, {}, {}, {}, {}, {}, false, false)
      c:SetCollisionEnabled(0)
      if not mats[s.mat] then mats[s.mat] = CUSTOM.material(actor, id, data.materials[s.mat] or {}) or false end
      if mats[s.mat] then c:SetMaterial(0, mats[s.mat]) end
      parts[#parts + 1] = c; built = built + 1
    end
  end
  CUSTOM.parts[actor:GetAddress()] = parts
  pcall(CUSTOM.hookPortraits)
  -- Battle texts ("<name> attacks") and the turn-order icon. The name goes through the engine's own
  -- SetTextPropertyByName: assigning the FText property from Lua (UE4SS 3.0.1) corrupted memory and crashed the game
  -- a few frames later in memcpy (11:20 and 11:29 tests).
  pcall(function()
    local st = actor.AC_jRPG_CharacterStats
    StaticFindObject("/Script/Engine.Default__KismetSystemLibrary"):SetTextPropertyByName(st, FName("CharacterDisplayName"), FText(d.name))
    local icon = CUSTOM.portrait(id)
    if icon then st.CharacterBattleIcon = icon end
  end)
  log(("%s on %s: %d sections (%d bones missing), %d base meshes hidden, %.2f s"):format(id, actor:GetFName():ToString(), built, missing, hidden, os.clock() - t0))
  return built
end
-- Remove a custom look (debug / re-skin).
function CUSTOM.strip(actor)
  for _, c in ipairs((CUSTOM.parts or {})[actor:GetAddress()] or {}) do pcall(function() c:K2_DestroyComponent(actor) end) end
  CUSTOM.parts[actor:GetAddress()] = nil
  for _, c in ipairs(comps(actor, "/Script/Engine.PrimitiveComponent")) do
    if CUSTOM.HIDE[c:GetClass():GetFName():ToString()] then pcall(function() c:SetHiddenInGame(false, false) end) end
  end
end

-- ---------- skeleton dumps (input of tools/charforge) ----------
-- data/skeletons/<key>.tsv: index, bone, parent, reference-pose local transform (translation, quaternion, scale).
function CUSTOM.dumpSkeleton(actor, key)
  local mesh = CUSTOM.body(actor)
  if not mesh then return nil end
  local dir = (E33V_DATA or "") .. "skeletons/"
  os.execute('mkdir "' .. dir:gsub("/", "\\"):gsub("\\$", "") .. '" 2>nul')
  local path = dir .. key .. ".tsv"
  local lines = {}
  for i = 0, mesh:GetNumBones() - 1 do
    local name = mesh:GetBoneName(i):ToString()
    local t = mesh:GetRefPoseTransform(i)
    local p, q, s = t.Translation, t.Rotation, t.Scale3D
    lines[#lines + 1] = ("%d\t%s\t%s\t%.4f %.4f %.4f %.6f %.6f %.6f %.6f %.4f %.4f %.4f"):format(i, name, mesh:GetParentBone(FName(name)):ToString(),
      p.X, p.Y, p.Z, q.X, q.Y, q.Z, q.W, s.X, s.Y, s.Z)
  end
  local f = io.open(path, "w"); if not f then return nil end
  f:write(table.concat(lines, "\n")); f:close()
  return path
end
-- Every unit spawned in a versus gets its skeleton dumped once (so any unit can be used as a base later).
function CUSTOM.autoDump(actor, u)
  local key = u.kind == "hero" and ("hero_" .. u.id) or ("enemy_" .. tostring(u.row):gsub("#P%d+$", ""))
  local path = (E33V_DATA or "") .. "skeletons/" .. key .. ".tsv"
  local h = io.open(path, "r"); if h then h:close(); return end
  local ok, r = pcall(CUSTOM.dumpSkeleton, actor, key)
  log("skeleton " .. key .. ": " .. tostring(ok and r or ("FAILED " .. tostring(r))))
end
