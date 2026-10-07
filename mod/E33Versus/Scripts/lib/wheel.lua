-- E33 Versus: the game's own battle wheel for non-hero units (requires unitlib, picker, versus, economy, phases).
-- How it works (all verified in game 2026-10-07):
--  * Skills page: the wheel lists skill-data assets (BP_DataAsset_Skill). We build one per monster move (copied from a
--    hero skill template, then renamed / re-costed) and load the unit's 6-move loadout into the wheel.
--  * The game's targeting needs the acting unit's side labelled "heroes" (applyPerspective(c, mySide)) while choosing.
--  * Confirming a target calls BM:RequestActionExecution -> CurrentCharacter:ExecuteAction(BM.SelectedAction, name).
--    ExecuteAction ignores action types outside 1..5, so after the wheel picks one of OUR skills we set
--    BM.SelectedAction = 0 and run the monster move ourselves (P.execute) from a hook on RequestActionExecution.
--  * Items run natively (item scripts work on monsters). Each team has its own stock: BM.BattleItemsCount is swapped
--    to the acting team's counts at every turn start.
--  * The wheel actor normally follows a bone of the acting unit at hero scale; for monsters we pin it in front of our own
--    over-the-shoulder camera (SetLocationAsStatic), the camera distance scaled to the unit's size.
WH = WH or {}
local function log(s) V.log("WHEEL " .. s) end
WH.MAX_SKILLS = 6
WH.ITEM_STOCK = { Health = 3, Energy = 2, Revive = 1 }   -- per team, per match
WH.SKILL_TEMPLATE = "DA_Skill_Gustave_Combo1"
WH.BM = "/Game/jRPGTemplate/Blueprints/Components/AC_jRPG_BattleManager.AC_jRPG_BattleManager_C:"
WH.assets = WH.assets or {}      -- "<class>::<prop>" -> skill asset (kept alive: GameInstance outer + keep flags)
WH.byName = WH.byName or {}      -- NameID string -> { key, prop }
WH.seq = WH.seq or 0

-- ---------- move names ----------
-- "Skill Handle_Sirene Skill DeathStare" -> "Death Stare"; "SkillHandle_5_HammerCombo6hits" -> "Hammer Combo 6 Hits"
function WH.pretty(prop)
  local s = prop:gsub("^Skill ?Hand?l?e_", ""):gsub("_", " ")
  s = s:gsub("^%d+%s*", "")
  s = s:gsub("^[%a]+ Skill ", ""):gsub("^Skill ", "")                -- "<Unit> Skill X" -> "X"
  s = s:gsub("[Pp]hase ?%d+", ""):gsub("^ +", "")
  s = s:gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2")         -- CamelCase -> words (keeps "AOE")
  s = s:gsub("(%a)(%d)", "%1 %2"):gsub("(%d)(%a)", "%1 %2")
  s = s:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end)
  s = s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  return s ~= "" and s or prop
end
function WH.targeting(prop)
  local l = prop:lower()
  if WH.isSupport(prop) then return 0 end
  if l:find("aoe") or l:find("all") or l:find("wave") or l:find("storm") or l:find("rain") or l:find("explosion") then return 3 end
  return 1
end
function WH.tier(cost)
  if cost <= 1 then return "Quick technique" elseif cost <= 3 then return "Strong technique" elseif cost <= 5 then return "Heavy technique" end
  return "Devastating technique"
end

-- ---------- texts ----------
-- NEVER assign an FText made in Lua to an object property (obj.Name = FText("x")): UE4SS copies it without a reference,
-- the text data is freed later and the game crashes the next time it copies that text (9 dumps: FText copy loop with a
-- garbage pointer; no crash with the same objects and no text assignment).
-- Fix: the engine copies the text into the property itself (SetTextPropertyByName = proper ref count). The Lua FText
-- passed as the argument is still kept alive, in case UE4SS releases the parameter copy.
WH._texts = WH._texts or {}
function WH.setText(obj, prop, str)
  local K = WH._ksl; if not (K and K:IsValid()) then K = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary"); WH._ksl = K end
  local t = FText(str); WH._texts[#WH._texts + 1] = t
  K:SetTextPropertyByName(obj, FName(prop), t)
end

-- ---------- skill assets ----------
function WH.template()
  if WH._tpl and WH._tpl:IsValid() then return WH._tpl end
  for _, a in ipairs(FindAllOf("BP_DataAsset_Skill_C") or {}) do
    if a:GetFName():ToString() == WH.SKILL_TEMPLATE then WH._tpl = a; return a end
  end
  pcall(LoadAsset, "/Game/Gameplay/SkillTree/Content/Gustave/DA_Skill_Gustave_Combo1.DA_Skill_Gustave_Combo1")
  for _, a in ipairs(FindAllOf("BP_DataAsset_Skill_C") or {}) do
    if a:GetFName():ToString() == WH.SKILL_TEMPLATE then WH._tpl = a; return a end
  end
end
function WH.asset(u, move, cost, label, desc, tgt)
  -- fresh objects every turn (never reuse a handle across turns: a collected object would crash the wheel)
  local key = u:GetClass():GetFName():ToString() .. "::" .. move.prop
  local a
  do
    local tpl = WH.template(); if not tpl then return nil end
    WH.seq = WH.seq + 1
    a = StaticConstructObject(tpl:GetClass(), FindFirstOf("GameInstance"), FName("E33V_Skill_" .. WH.seq .. "_" .. os.time()), 0, 0x0E000000, false, false, tpl, nil, nil)
    if not (a and a:IsValid()) then return nil end
    a.NameID = FName("E33V_" .. WH.seq)
    WH.assets[key] = a
    WH.byName["E33V_" .. WH.seq] = { key = key, prop = move.prop }
  end
  WH.setText(a, "Name", label or WH.pretty(move.prop))
  WH.setText(a, "ShortDescription", desc or WH.tier(cost))
  WH.setText(a, "Description", desc or WH.tier(cost))
  a.APCost = cost
  a.TargetingType = tgt or WH.targeting(move.prop)
  return a
end

-- ---------- loadout ----------
-- V.cfg[side][slot].loadout = { prop, ... } (chosen on the select screen); default = 6 moves spread over the cost range.
function WH.defaultLoadout(moves, costOf)
  if #moves <= WH.MAX_SKILLS then local t = {}; for i, m in ipairs(moves) do t[i] = m.prop end; return t end
  local s = {}; for i, m in ipairs(moves) do s[i] = m end
  table.sort(s, function(x, y) local cx, cy = costOf(x), costOf(y); if cx ~= cy then return cx < cy end; return x.prop < y.prop end)
  local t = {}
  for i = 1, WH.MAX_SKILLS do t[i] = s[math.floor((i - 1) * (#s - 1) / (WH.MAX_SKILLS - 1) + 0.5) + 1].prop end
  return t
end
-- Select screen: every move of a roster row (all phases), priced by class name. Phase-tagged moves only show up in the
-- wheel while the boss is in that phase.
function WH.rowMoves(row)
  local d = MOVES and MOVES[(row or ""):gsub("#P%d+$", "")]
  if not d then return nil end
  local out = {}
  for _, p in ipairs(d.props) do
    local ph = tonumber(p:match("Phase(%d+)"))
    out[#out + 1] = { prop = p, label = WH.pretty(p), cost = E.costFor(d.cls, p), phase = ph }
  end
  return out
end
function WH.defaultLoadoutFor(row)
  local list = WH.rowMoves(row); if not list then return nil end
  return WH.defaultLoadout(list, function(m) return m.cost end)
end
function WH.unitCfg(u)
  local uid = V.uidOf and V.uidOf[u:GetAddress()]
  if not uid then return nil end
  return V.cfg[uid:sub(1, 1)] and V.cfg[uid:sub(1, 1)][tonumber(uid:sub(2))]
end
-- Current-phase moves in loadout order, topped up from the remaining moves (a phase change swaps the move set).
function WH.wheelMoves(u)
  local moves = P.moves(u); local byProp = {}
  for _, m in ipairs(moves) do byProp[m.prop] = m end
  local cfg = WH.unitCfg(u)
  local lo = (cfg and cfg.loadout) or WH.defaultLoadout(moves, function(m) return E.moveCost(u, m) end)
  local out, used = {}, {}
  for _, p in ipairs(lo) do if byProp[p] and not used[p] and #out < WH.MAX_SKILLS then out[#out + 1] = byProp[p]; used[p] = true end end
  for _, m in ipairs(moves) do if not used[m.prop] and #out < WH.MAX_SKILLS then out[#out + 1] = m; used[m.prop] = true end end
  return out, moves
end
-- "Attack" on the action wheel = the unit's cheapest real ATTACK, free, +1 AP (like a hero's basic attack).
-- Support moves never qualify (the Mime's cheapest move gave it a shield instead of hitting - user report).
WH.SUPPORT = { "shield", "heal", "buff", "boost", "protect", "summon", "silence", "craft", "reality", "regen", "cleanse", "taunt", "guard", "defen" }
WH.ATTACKY = { "attack", "hit", "punch", "combo", "slash", "strike", "kick", "smash", "stab", "bite", "claw", "shot", "shoot", "slam", "swing", "fall", "jump", "estoc", "spear", "hammer", "blade", "thunder", "fire", "stare" }
function WH.isSupport(prop) local l = prop:lower(); for _, w in ipairs(WH.SUPPORT) do if l:find(w, 1, true) then return true end end; return false end
function WH.isAttacky(prop) local l = prop:lower(); for _, w in ipairs(WH.ATTACKY) do if l:find(w, 1, true) then return true end end; return false end
function WH.basicMove(u, moves)
  local best, bestScore
  for _, m in ipairs(moves) do
    if not WH.isSupport(m.prop) then
      local score = E.moveCost(u, m) * 10 + (WH.isAttacky(m.prop) and 0 or 5)
      if not bestScore or score < bestScore or (score == bestScore and m.prop < best.prop) then best, bestScore = m, score end
    end
  end
  return best or moves[1]
end
-- ---------- AP (our economy, mirrored into the game's AP so the native gauge and wheel costs show it) ----------
-- Monsters have max AP (stat 2) = 0, so SetAP clamps to 0: raise it to our cap first. SetAP (reason must be non-zero)
-- fires the game's AP-change event, which refreshes the native AP gauge.
function WH.setAP(u, n)
  local st = u.AC_jRPG_CharacterStats
  if (V.getStat(u, 2) or 0) < E.AP_MAX then pcall(V.setStat, u, 2, E.AP_MAX) end
  if not pcall(function() st:SetAP(n, 1) end) then st.CurrentAP = n end
  if math.abs((st.CurrentAP or 0) - n) > 0.01 then st.CurrentAP = n end
  WH.apWritten = WH.apWritten or {}; WH.apWritten[u:GetAddress()] = true
end
-- AP the game changed since we last wrote it (Energy Tint, drains) becomes our value.
function WH.readAP(u)
  local a = u:GetAddress()
  if WH.apWritten and WH.apWritten[a] then E.ap[a] = math.floor((u.AC_jRPG_CharacterStats.CurrentAP or 0) + 0.5) end
end

-- ---------- items (per-team stock) ----------
-- Monsters: the game's item scripts only finish on humanoid skeletons (Chroma Lune healed fine, the Mime froze in
-- "executing"), so a monster's item is applied here and its turn ended the game's way. Heroes use the native flow.
WH.ITEM_EFFECT = { Health = 0.30, Energy = 3, Revive = 0.30 }
function WH.applyItem(user, item, target)
  local kind = WH.itemKind(item); local bm = U.bm()
  target = (target and target:IsValid()) and target or user
  local st = target.AC_jRPG_CharacterStats
  local max = V.maxHP(target)
  if kind == "Health" then
    st.CurrentHP = math.min(max, st.CurrentHP + max * WH.ITEM_EFFECT.Health)
  elseif kind == "Energy" then
    local a = target:GetAddress()
    if E.ap[a] ~= nil then E.ap[a] = math.min(E.AP_MAX, E.ap[a] + WH.ITEM_EFFECT.Energy); WH.setAP(target, E.ap[a])
    else pcall(function() st:SetAP(math.floor((st.CurrentAP or 0) + WH.ITEM_EFFECT.Energy), 1) end) end
  elseif kind == "Revive" then   -- best effort (UNTESTED): the game's own resurrect queue
    local dead = false; pcall(function() dead = target["Dead?"] == true end)
    if dead or st.CurrentHP <= 0 then pcall(function() bm:RegisterPendingResurrect(st) end) end
  end
  pcall(function() bm:ConsumeBattleItem(FName(item), 1) end)
  log(("item %s on %s -> HP %.0f, AP %.0f"):format(tostring(kind), P.dname(target), st.CurrentHP, st.CurrentAP or 0))
end
function WH.itemKind(name) for k in pairs(WH.ITEM_STOCK) do if name:find(k) then return k end end end
function WH.resetItems() WH.items = { A = {}, B = {} }; WH.itemSide = nil
  for k, n in pairs(WH.ITEM_STOCK) do WH.items.A[k] = n; WH.items.B[k] = n end end
function WH.swapItems(side)
  local bm = U.bm(); if not (bm and WH.items and side) then return end
  local m = bm.BattleItemsCount
  if WH.itemSide then   -- store what the previous team has left
    pcall(function() m:ForEach(function(k, v) local kind = WH.itemKind(k:get():ToString()); if kind then WH.items[WH.itemSide][kind] = v:get() end end) end)
  end
  pcall(function() m:ForEach(function(k, v) local kind = WH.itemKind(k:get():ToString()); if kind then v:set(WH.items[side][kind] or 0) end end) end)
  WH.itemSide = side
end

-- ---------- camera + wheel placement ----------
-- Height = head bone above the feet (+15%); capsules are human-sized even on huge bosses, full bounds include FX.
-- Radius from the collision bounds (wide dresses / bodies) pushes the camera out further.
function WH.size(u)
  local cap = 180; pcall(function() cap = u.CapsuleComponent:GetScaledCapsuleHalfHeight() * 2 end)
  local p = u:K2_GetActorLocation(); local feet = p.Z - cap / 2
  local H = cap
  pcall(function() local h = u.Mesh:GetSocketLocation(FName("head")); if h.Z - feet > 50 then H = math.max(cap, (h.Z - feet) * 1.15) end end)
  local o, e = {}, {}; local R = 60
  pcall(function() u:GetActorBounds(true, o, e, false); R = math.max(e.X or 60, e.Y or 60) end)
  return H, math.min(R, 600), feet
end
function WH.placeCamera(u)
  local KM = StaticFindObject("/Script/Engine.Default__KismetMathLibrary")
  local me = V.sideOf[u:GetAddress()]; local cx, cy, n = 0, 0, 0
  for _, x in ipairs(V.units or {}) do
    if x:IsValid() and V.sideOf[x:GetAddress()] ~= me and x.AC_jRPG_CharacterStats.CurrentHP > 0 then
      local l = x:K2_GetActorLocation(); cx, cy, n = cx + l.X, cy + l.Y, n + 1 end
  end
  local p = u:K2_GetActorLocation()
  if n == 0 then cx, cy, n = p.X + 500, p.Y, 1 end
  cx, cy = cx / n, cy / n
  local dx, dy = cx - p.X, cy - p.Y; local len = math.max(1, math.sqrt(dx * dx + dy * dy)); dx, dy = dx / len, dy / len
  local rx, ry = -dy, dx
  local H, R, feet = WH.size(u)
  local D = math.max(280, 1.35 * H) + R
  local cam = { X = p.X - dx * D + rx * D * 0.62, Y = p.Y - dy * D + ry * D * 0.62, Z = feet + H * 0.8 + 40 }
  local look = { X = p.X + dx * len * 0.6, Y = p.Y + dy * len * 0.6, Z = feet + H * 0.4 }
  local rot = KM:FindLookAtRotation(cam, look)
  WH.camPos, WH.camRot = cam, rot
  WH.applyCam(u)
  FindFirstOf("PlayerController"):SetViewTargetWithBlend(u, 0.35, 0, 0, false)
  -- wheel: in front of the camera, left of the unit, facing the camera
  local f = KM:GetForwardVector(rot); local r = KM:GetRightVector(rot)
  WH.wheelPos = { X = cam.X + f.X * 210 + r.X * 18, Y = cam.Y + f.Y * 210 + r.Y * 18, Z = cam.Z + f.Z * 210 - 12 }
  WH.wheelFwd = { X = f.X, Y = f.Y, Z = 0 }
  WH.pinWheel()
end
-- The game's turn flow switches the unit to its shoulder camera: keep OUR camera component active and in place.
function WH.applyCam(u)
  if not WH.camPos then return end
  if u.Camera_Shoulder:IsActive() or not u.Camera:IsActive() then pcall(function() u:OverrideWithShoulderCamera(false) end); u.Camera:SetActive(true, false) end
  u.Camera:K2_SetWorldLocationAndRotation(WH.camPos, WH.camRot, false, {}, true)
end
function WH.pinWheel()
  local w = U.bm().LGUI_Actor_BattleWheels
  -- location only: the wheel turns toward the active camera by itself. (Overwriting its DesiredForwardVector stuck
  -- into the next HERO turn: oversized, skewed wheel.)
  w:SetLocationAsStatic(WH.wheelPos)
end
-- Per frame while a monster chooses: the game re-pins the wheel to the unit when a page opens -> pin it back.
function WH.frame()
  local c = WH.cur; if not (c and c.choosing) then return end
  c.frames = (c.frames or 0) + 1
  local okS, ts = pcall(function() return c.u:GetCurrentBattleTurnState() end)
  if okS then
    if ts ~= c.turnState then log(("turn state %s -> %s (frame %d)"):format(tostring(c.turnState), tostring(ts), c.frames)) end
    if ts == 2 and c.turnState ~= 2 then c.loadAt = c.frames + 2 end
    c.turnState = ts
  end
  if c.loadAt and c.frames >= c.loadAt then
    c.loadAt = nil
    local ok, err = pcall(WH.loadSkillPage); if not ok then log("skill page: " .. tostring(err)) end
  end
  -- targeting: the acting side must be "heroes" for the cursor to land on the right units
  local tm = WH._tm; if not (tm and tm:IsValid()) then tm = WH.targetingManager(); WH._tm = tm end
  if tm and tm:IsValid() then
    local on = tm["TargetingEnabled?"] == true
    if on and not c.flipped then
      c.flipped = true
      V.applyPerspective(c.u, V.sideOf[c.u:GetAddress()])
      pcall(function() tm:EnableTargeting(tm.SelectedTargetingType) end)
    elseif not on and c.flipped then
      c.flipped = false
      V.applyPerspective(c.u)
    end
  end
  if not WH.wheelPos then return end
  pcall(WH.applyCam, c.u)
  local w = U.bm().LGUI_Actor_BattleWheels
  local l = w:K2_GetActorLocation()
  if math.abs(l.X - WH.wheelPos.X) + math.abs(l.Y - WH.wheelPos.Y) + math.abs(l.Z - WH.wheelPos.Z) > 5 then pcall(WH.pinWheel) end
  local pc = TICK and TICK.pc   -- cached: a per-frame FindFirstOf walks every object while the page spawns/destroys FX
  if not (pc and pc:IsValid()) then return end           -- (crashed inside UE4SS, 2 dumps)
  local vt = pc:GetViewTarget()
  if vt and vt:IsValid() and vt:GetAddress() ~= c.u:GetAddress() then pc:SetViewTargetWithBlend(c.u, 0.25, 0, 0, false) end
end

-- ---------- turn ----------
-- Called at a controlled (non-hero) unit's turn start instead of the old list picker.
function WH.beginTurn(u)
  local a = u:GetAddress(); local bm = U.bm()
  local list, moves = WH.wheelMoves(u)
  local st = u.AC_jRPG_CharacterStats
  local skills = {}
  WH.cur = { u = u, moves = moves, basic = WH.basicMove(u, moves), choosing = true, byNameMove = {} }
  for _, m in ipairs(list) do
    local cost = E.moveCost(u, m)
    local asset = WH.asset(u, m, cost)
    if asset then skills[#skills + 1] = asset; WH.cur.byNameMove[asset.NameID:ToString()] = { move = m, cost = cost } end
  end
  -- the super move: only offered once it is allowed
  if PH and PH.hasNext(u) and PH.canPhaseUp(u) then
    local pm = { prop = "E33V_PhaseUp" }
    local asset = WH.asset(u, pm, PH.UP_COST, "Phase Up", "Unleash the next phase.", 0)
    if asset then skills[#skills + 1] = asset; WH.cur.byNameMove[asset.NameID:ToString()] = { phaseUp = true, cost = PH.UP_COST } end
  end
  -- No SkillStates for these (InitSkillStates made the wheel crash): buttons fall back to the asset's APCost.
  pcall(function() st:ClearSkillStates() end)
  st.Skills:Empty()
  for i, s in ipairs(skills) do st.Skills[i] = s end
  WH.cur.skills = skills
  -- the game's hero-turn flow adds +1 AP right after this (like for heroes): write one less so the gauge = our value
  WH.setAP(u, math.max(0, (E.ap[a] or 0) - 1))
  -- Labels stay as the enemy AI expects while browsing (opening Skills as a "player-team" monster crashed the game in
  -- OnStartChoosingSkill); WH.frame flips them only while the target cursor is up.
  WH.cur.flipped = false
  u["ControlledByBattleAI?"] = false
  pcall(function() bm.LGUI_Actor_BattleWheels:SetActorHiddenInGame(false) end)
  pcall(WH.placeCamera, u)
  log(("%s: %d skills, AP %d, basic %s"):format(P.dname(u), #skills, E.ap[a] or 0, WH.cur.basic and WH.cur.basic.prop or "-"))
end
-- The skills page is only (re)loaded by the game for each equipped save skill: a monster has none, so the list we load
-- at turn start stays. (UpdateCharacterSkillWheels is a local BP call: a UE4SS hook on it never fires.)
-- The targeting manager that belongs to the running battle (a component next to the battle manager).
function WH.targetingManager()
  local bm = U.bm()
  local ok, tm = pcall(function() return bm:GetOwner():GetComponentByClass(StaticFindObject("/Game/jRPGTemplate/Blueprints/Components/AC_jRPG_TargetingManager.AC_jRPG_TargetingManager_C")) end)
  if ok and tm and tm:IsValid() then return tm end
  return FindFirstOf("AC_jRPG_TargetingManager_C")
end
function WH.container()
  local c = WH._wc
  if c and c:IsValid() then return c end
  -- the container of THIS battle's wheel actor (a rematch can leave the old battle's widgets around)
  pcall(function() local o = {}; U.bm().LGUI_Actor_BattleWheels:GetWheelsContainerWidget(o); for _, v in pairs(o) do if type(v) == "userdata" and v.IsValid and v:IsValid() then c = v end end end)
  if not (c and c:IsValid()) then
    for _, x in ipairs(FindAllOf("WBP_HUD_WheelsContainer_C") or {}) do if x:GetFullName():find("Transient", 1, true) then c = x end end
  end
  WH._wc = c; return c
end
function WH.loadSkillPage()
  local c = WH.cur; local w = WH.container(); if not (c and c.skills and w) then return end
  local o = {}; w:GetSkillWheel(o)
  local sw = o.SkillWheel
  -- loading the list for a unit labelled player-team crashed the game (it reads that character's save data, which a
  -- monster does not have): label it enemy for the call only.
  log("skill page load: wheel widget " .. tostring(sw and sw:IsValid()))
  if sw and sw:IsValid() then
    local was = c.u["Enemy?"]; c.u["Enemy?"] = true
    -- The Skills parameter is by-ref: UE4SS 3.0.1 rewrites the handles in the Lua table we pass into references to the
    -- call's temporary memory. Handles we keep elsewhere must never go in (that crashed the game ~1 s later, 6 dumps):
    -- pass a throwaway table of FRESH handles read from stats.Skills, and never touch it again.
    local st = c.u.AC_jRPG_CharacterStats
    local fresh = {}; for i = 1, #st.Skills do fresh[i] = st.Skills[i] end
    local ok, err = pcall(function() sw:LoadSkillListData(st, fresh) end)
    c.u["Enemy?"] = was
    if not ok then error(err) end
  end
end
-- WHEN: from the per-frame ticker, a couple of frames after the unit's turn state becomes 2 (choosing a skill).
-- Not from a hook callback: calling a function with an out-parameter inside a hook crashed UE4SS itself.
function WH.cbSelectAction(ctx, t)
  local c = WH.cur; if not (c and c.choosing) then return end
  local ok, v = pcall(function() return t:get() end)
  log(("SelectAction %s %s"):format(tostring(ok), tostring(v)))
  if ok and v == 1 then   -- Attack -> basic move
    c.pending = { move = c.basic, cost = 0, basic = true }
    U.bm().SelectedAction = 0
  end
end
function WH.cbSelectSecondary(ctx, n)
  local c = WH.cur; if not (c and c.choosing) then return end
  local ok, v = pcall(function() return n:get():ToString() end)
  log(("SelectSecondary %s %s"):format(tostring(ok), tostring(v)))
  if not ok then return end
  local bm = U.bm()
  local entry = c.byNameMove[v]
  if entry then c.pending = entry; bm.SelectedAction = 0
  elseif bm.SelectedAction == 3 then c.pending = { item = v }; bm.SelectedAction = 0 end   -- monster items: see WH.applyItem
end
function WH.cbRequest(ctx, targets)
  local c = WH.cur; if not (c and c.choosing) then return end
  if not c.pending then
    -- Gamepad Attack: the controller path never calls SelectAction (verified 2026-10-07: request arrives with
    -- SelectedAction 1 or 0 and no SelectAction call). Left alone, the game runs its hero attack on the monster: it
    -- walks up to the target and stands there (no hero animation). Treat it as Attack = the basic move.
    local sa; pcall(function() sa = U.bm().SelectedAction end)
    log(("request with no choice (SelectedAction %s) -> basic move"):format(tostring(sa)))
    if not c.basic then return end
    c.pending = { move = c.basic, cost = 0, basic = true }
    pcall(function() U.bm().SelectedAction = 0 end)
  end
  local u = c.u
  local st = u.AC_jRPG_CharacterStats
  local tgts = {}
  pcall(function() for i = 1, #st.TargetedCharacters do tgts[#tgts + 1] = st.TargetedCharacters[i] end end)
  local p = c.pending; c.pending = nil; c.choosing = false
  local a = u:GetAddress()
  E.ap[a] = math.floor((st.CurrentAP or 0) + 0.5)   -- the game's AP is the truth while choosing
  if p.item then
    log(P.dname(u) .. " uses item " .. p.item)
    if SYNC and SYNC.active() and SYNC.mine(u) then
      local ids = {}; for _, t in ipairs(tgts) do ids[#ids + 1] = SYNC.uid(t) end
      SYNC.sendAct(u, "item", { item = p.item, targets = ids })
    end
    WH.cur = nil
    V.applyPerspective(u)
    WH.applyItem(u, p.item, tgts[1])
    SYNC.endTurn(u)
    return
  end
  if p.phaseUp then
    E.ap[a] = (E.ap[a] or 0) - p.cost; WH.setAP(u, E.ap[a])
    WH.cur = nil
    PH.phaseUp(u); P.wait(u)
    return
  end
  local target = tgts[1]
  if not (target and target:IsValid()) or (V.sideOf[target:GetAddress()] == V.sideOf[a]) then
    target = P.opponents(u)[1]    -- buffs / self-targeted moves: the AI picks its own targets anyway
  end
  if p.basic then E.ap[a] = math.min(E.AP_MAX, (E.ap[a] or 0) + 1) else E.ap[a] = (E.ap[a] or 0) - (p.cost or 0) end
  WH.setAP(u, E.ap[a])
  WH.cur = nil
  V.applyPerspective(u)                         -- back to the labels the enemy AI expects
  E.snapshot(u, p.move, target)
  P.execute(u, p.move, target)
end
function WH.install()
  if E33V_WHEEL_HOOKS then return end
  local ok1 = true
  local ok2 = pcall(RegisterHook, WH.BM .. "SelectAction", function(ctx, t) return WH.cbSelectAction(ctx, t) end)
  local ok3 = pcall(RegisterHook, WH.BM .. "SelectSecondaryAction", function(ctx, n) return WH.cbSelectSecondary(ctx, n) end)
  local ok4 = pcall(RegisterHook, WH.BM .. "RequestActionExecution", function(ctx, t) return WH.cbRequest(ctx, t) end)
  E33V_WHEEL_HOOKS = ok1 and ok2 and ok3 and ok4
  log(("hooks: %s %s %s %s"):format(tostring(ok1), tostring(ok2), tostring(ok3), tostring(ok4)))
end
-- Turn start for EVERY unit (heroes too): end any unfinished monster choice, swap item stock to the acting team.
function WH.onAnyTurn(c)
  WH.cur = nil
  -- a new battle can use new manager/targeting/wheel objects (same-world rematch): never keep the old ones
  local bm = U.bm(); local a = bm and bm:IsValid() and bm:GetAddress()
  if a ~= WH._bmAddr then WH._bmAddr = a; WH._tm, WH._wc = nil, nil end
  -- The battle wheel widget is created once and keeps the battle manager of the FIRST battle: in a same-world rematch
  -- that one is destroyed and every wheel action (heroes too) went nowhere. Point it at the running battle.
  pcall(function()
    local w = WH.container()
    if w and bm and (not w.BattleManagerReference:IsValid() or w.BattleManagerReference:GetAddress() ~= a) then
      w.BattleManagerReference = bm; V.log("WHEEL container re-linked to the running battle")
    end
  end)
  pcall(WH.install)
  local side = V.sideOf and V.sideOf[c:GetAddress()]
  if side then pcall(WH.swapItems, side) end
end

-- ---------- menu sounds (the game's own UI sound events) ----------
WH.SND = { move = "UI_GameMenu_Team_NavigationMove", ok = "UI_GameMenu_Global_Navigate_Click_Valid", back = "UI_GameMenu_NavigateBack",
  tab = "UI_GameMenu_Global_SwitchTop", deny = "UI_RestMenu_Skill_CantLearn", add = "UI_GameMenu_Character_AddToParty",
  remove = "UI_GameMenu_Character_RemoveFromParty", open = "UI_GameMenu_Global_Open", close = "UI_GameMenu_Global_Close",
  start = "UI_MainMenu_Continue" }
function WH.sfx(name)
  local row = WH.SND[name] or name
  pcall(function()
    local dt = WH._sdt; if not (dt and dt:IsValid()) then dt = StaticFindObject("/Game/Gameplay/Audio/DT_SoundEvent_UI.DT_SoundEvent_UI"); WH._sdt = dt end
    local fl = WH._sfl; if not (fl and fl:IsValid()) then fl = StaticFindObject("/Game/jRPGTemplate/Blueprints/Basics/FL_jRPG_CustomFunctionLibrary.Default__FL_jRPG_CustomFunctionLibrary_C"); WH._sfl = fl end
    if dt and dt:IsValid() and fl and fl:IsValid() then fl:PlaySoundEventRow_UI({ DataTable = dt, RowName = FName(row) }, (TICK and TICK.pc and TICK.pc:IsValid()) and TICK.pc or FindFirstOf("PlayerController")) end
  end)
end
