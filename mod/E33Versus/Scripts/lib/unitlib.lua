-- E33 Versus unit helpers (prepend to bridge commands). UE4SS 3.0.1: only flat struct tables, no FString writes.
U = {}
-- Object searches (FindFirstOf / FindAllOf walk the engine's whole object list) crash inside UE4SS (+0x2f6cee) when they
-- run while the engine creates objects on its loading thread: after a level travel and while a battle spawns
-- (rematches 2026-10-08 10:37, 11:19, 11:28, 11:38). The objects the mod needs are reachable by reference instead:
-- game instance (persists across levels) -> player controller (GameplayStatics) -> its battle / characters managers,
-- action executor; game instance -> save manager, music system. FindFirstOf of those classes resolves by reference
-- first; a real search is the fallback (logged while a load or battle spawn is in progress).
-- The global wrappers only delegate to U.find1 / U.findAll, so a hot reload updates them.
function U.gi()
  local g = E33V_GI
  if g and g:IsValid() then return g end
  g = E33V_FF and E33V_FF("BP_jRPG_GI_Custom_C") or FindFirstOf("BP_jRPG_GI_Custom_C")
  E33V_GI = (g and g:IsValid()) and g or nil
  return E33V_GI
end
local GS
function U.pc()
  local gi = U.gi(); if not gi then return nil end
  if not (GS and GS:IsValid()) then GS = StaticFindObject("/Script/Engine.Default__GameplayStatics") end
  local ok, pc = pcall(function() return GS:GetPlayerController(gi, 0) end)
  if ok and pc and pc:IsValid() then return pc end
end
local function prop(o, name)
  if not o then return nil end
  local ok, v = pcall(function() local x = o[name]; return (x and x.IsValid and x:IsValid()) and x or nil end)
  if ok then return v end
end
-- The exploration controller (BP_jRPG_Controller_World_C): the one that owns a battle manager (the title's does not).
function U.worldPC()
  local pc = U.pc()
  if pc and prop(pc, "AC_jRPG_BattleManager") then return pc end
end
U.BYREF = {
  PlayerController = function() return U.pc() end,
  BP_jRPG_Controller_World_C = function() return U.worldPC() end,
  AC_jRPG_BattleManager_C = function() return prop(U.worldPC(), "AC_jRPG_BattleManager") end,
  AC_jRPG_CharactersManager_C = function() return prop(U.worldPC(), "AC_jRPG_CharactersManager") end,
  BP_GameActionExecutorComponent_C = function() return prop(U.worldPC(), "BP_GameActionExecutorComponent") end,
  BP_jRPG_GI_Custom_C = function() return U.gi() end,
  GameInstance = function() return U.gi() end,
  BP_SaveManager_C = function() return prop(U.gi(), "SaveManager") end,
}
local function watching() return V and V.log and (V.spawnPending or V.loading or os.clock() < (V.searchWatchUntil or 0)) end
local function trace() return (debug.traceback("", 3):gsub("\n%s*", " | "):sub(1, 300)) end
function U.find1(c)
  local r = U.BYREF[c]
  if r then local ok, o = pcall(r); if ok and o and o:IsValid() then return o end end
  if watching() then V.log("SEARCH FindFirstOf " .. tostring(c) .. " " .. trace()) end
  return E33V_FF(c)
end
function U.findAll(c)
  if watching() then V.log("SEARCH FindAllOf " .. tostring(c) .. " " .. trace()) end
  return E33V_FA(c)
end
if not E33V_FIND_WRAPPED then
  E33V_FIND_WRAPPED = true
  E33V_FF, E33V_FA = FindFirstOf, FindAllOf
  FindFirstOf = function(c) return U.find1(c) end
  FindAllOf = function(c) return U.findAll(c) end
end
function U.bm()
  if U._bm and U._bm:IsValid() then return U._bm end
  if V and V.loading then return nil end
  U._bm = U.findBM()
  return U._bm
end
-- A later battle in the same world can run on a NEW battle manager instance while the old one stays valid
-- (11:46 rematch: cached P=0 E=0, live one P=1 E=1). Prefer the instance that has units; drop the cache with U.bmReset().
-- The world controller's own battle manager: a property read, no object search (FindAllOf while a battle's assets
-- stream in crashed inside UE4SS, 2026-10-08 rematch).
function U.bmFromPC() return prop(U.worldPC(), "AC_jRPG_BattleManager") end
function U.findBM(search)
  local own = U.bmFromPC()
  if not search then return own end
  local withUnits, any
  for _, b in ipairs(FindAllOf("AC_jRPG_BattleManager_C") or {}) do
    if b:IsValid() then
      local n = #b.PlayerCharacters + #b.Enemies
      if n > 0 and b.BattleEndState == 0 then return b end   -- a running battle
      if n > 0 then withUnits = withUnits or b end
      any = any or b
    end
  end
  return withUnits or any
end
function U.bmReset() U._bm = nil end
-- Rebuild a TArray without `obj` (3.0.1 has no Remove): copy, Empty, re-append.
function U.arrayRemove(arr, obj)
  local keep = {}
  for i = 1, #arr do local x = arr[i]; if x:GetAddress() ~= obj:GetAddress() then keep[#keep + 1] = x end end
  arr:Empty()
  for i = 1, #keep do arr[i] = keep[i] end
  return #keep
end
function U.arrayHas(arr, obj) for i = 1, #arr do if arr[i]:GetAddress() == obj:GetAddress() then return true end end return false end
-- World transform of a battle spot. playerSide=true -> hero spots.
function U.spotTransform(playerSide, spot)
  local o1, o2 = {}, {}
  U.bm():GetProperBattleSpawnPointTransform(not playerSide, spot, 0, o1, o2)
  return o1  -- struct out params are written INTO the table (object outs are keyed by name)
end
local function quatYaw(q) return math.deg(math.atan(2 * (q.W * q.Z + q.X * q.Y), 1 - 2 * (q.Y * q.Y + q.Z * q.Z))) end
-- Enemy-side spots are unreliable (spots 0/1 often overlap), so enemy slots mirror the hero-side spacing
-- around enemy spot 0: slot 0 = centre, 1 and 2 = left/right by half the hero spot 1..2 distance.
function U.slotTransform(playerSide, spot)
  local t = U.spotTransform(playerSide, playerSide and spot or 0)
  if playerSide or spot == 0 then return t end
  local h1, h2 = U.spotTransform(true, 1).Translation, U.spotTransform(true, 2).Translation
  local lx, ly = (h2.X - h1.X) / 2, (h2.Y - h1.Y) / 2
  local sgn = (spot == 1) and -1 or 1
  local p = t.Translation
  return { Translation = { X = p.X + sgn * lx, Y = p.Y + sgn * ly, Z = p.Z }, Rotation = t.Rotation }
end
function U.placeAt(u, playerSide, spot)
  local t = U.slotTransform(playerSide, spot)
  local p, q = t.Translation, t.Rotation
  u:K2_SetActorLocation({ X = p.X, Y = p.Y, Z = p.Z }, false, {}, true)
  u:K2_SetActorRotation({ Pitch = 0.0, Yaw = quatYaw(q), Roll = 0.0 }, true)
  u.BattleSpotIndex = spot
  -- Home position used when dashing back after an action (leaf writes only).
  local ol, orr = u.OriginalLocation, u.OriginalRotation
  ol.X, ol.Y, ol.Z = p.X, p.Y, p.Z
  orr.Pitch, orr.Yaw, orr.Roll = 0.0, quatYaw(q), 0.0
  pcall(function() local wr = u.OriginalActorWorldRotation; wr.Pitch, wr.Yaw, wr.Roll = 0.0, quatYaw(q), 0.0 end)
  -- The real dash-back target: CombatMovement.InitialLocation, refreshed from the current transform.
  u.AC_jRPG_CombatMovement:UpdateInitialTransform()
  return string.format("%.0f,%.0f,%.0f yaw %.0f", p.X, p.Y, p.Z, quatYaw(q))
end
-- Put unit u on a side: flags + manager lists + position.
function U.setSide(u, playerSide, spot)
  local bm = U.bm()
  u["Enemy?"] = not playerSide
  if playerSide then
    if U.arrayHas(bm.Enemies, u) then U.arrayRemove(bm.Enemies, u) end
    pcall(function() bm.EnemiesBySpotIndex:Remove(u.BattleSpotIndex) end)
    if not U.arrayHas(bm.PlayerCharacters, u) then bm.PlayerCharacters[#bm.PlayerCharacters + 1] = u end
  else
    if U.arrayHas(bm.PlayerCharacters, u) then U.arrayRemove(bm.PlayerCharacters, u) end
    if not U.arrayHas(bm.Enemies, u) then bm.Enemies[#bm.Enemies + 1] = u end
  end
  local where = U.placeAt(u, playerSide, spot)
  local t = {}; bm:IsPlayerTeamCharacterBase(u, t)
  return u:GetFName():ToString() .. " playerTeam=" .. tostring(t.IsPlayerTeam) .. " at " .. where
end
-- Spawn any DT_jRPG_Enemies row, then move it to the requested side/spot.
-- Spawn on a spare internal spot index (kicked units never free their EnemiesBySpotIndex entry), then place.
E33V_SPAWN_SEQ = E33V_SPAWN_SEQ or 20
function U.spawn(row, playerSide, spot)
  local o1, o2 = {}, {}
  E33V_SPAWN_SEQ = E33V_SPAWN_SEQ + 1
  U.bm():SpawnEnemyOnSpot(E33V_SPAWN_SEQ, FName(row), true, o1, o2)
  local u = o1.SpawnedEnemy
  assert(u and u:IsValid(), "spawn failed: " .. row)
  return u, U.setSide(u, playerSide, spot)
end
-- Swap PlayerCharacters <-> Enemies contents (so enemy-AI "hero" targeting hits a switched unit's real opponents).
function U.swapLists()
  local bm = U.bm(); local p, e = {}, {}
  for i = 1, #bm.PlayerCharacters do p[#p + 1] = bm.PlayerCharacters[i] end
  for i = 1, #bm.Enemies do e[#e + 1] = bm.Enemies[i] end
  bm.PlayerCharacters:Empty(); bm.Enemies:Empty()
  for i = 1, #e do bm.PlayerCharacters[i] = e[i] end
  for i = 1, #p do bm.Enemies[i] = p[i] end
  E33V_SWAPPED = not E33V_SWAPPED
end

-- Hero from the save's character collection (heroes count toward the 3-per-side cap while on the player list).
function U.spawnHero(id, playerSide, spot)
  local gi = FindFirstOf("BP_jRPG_GI_Custom_C")
  local cm = FindFirstOf("AC_jRPG_CharactersManager_C")
  local o = {}; cm:GetCharacterData(FName(id), o)
  local data = o.CharacterData
  assert(data and data:IsValid(), "no character data for " .. id .. " in this save")
  local out = {}
  U.bm()["Spawn Player Character"](U.bm(), data, spot, 0, out)
  local u = out.SpawnedCharacter
  assert(u and u:IsValid(), "hero spawn failed: " .. id)
  return u, U.setSide(u, playerSide, spot)
end
function U.kick(u) local o = {}; U.bm():KickCharacterFromBattle_Internal(u, o) end
