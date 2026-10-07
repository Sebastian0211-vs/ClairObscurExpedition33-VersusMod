-- E33 Versus move picker for non-hero units (requires unitlib + uilib loaded).
P = P or {}
E33V_CONTROLLED = E33V_CONTROLLED or {}
local LOGF = (E33V_DATA or "") .. (E33V_LOGNAME or "versus.log")
local function log(s) local f = io.open(LOGF, "a"); if f then f:write(os.date("%H:%M:%S") .. " PICK " .. s .. "\n"); f:close() end end
local function dname(c) local ok, n = pcall(function() return c.AC_jRPG_CharacterStats.CharacterDisplayName:ToString() end); return (ok and n ~= "") and n or c:GetFName():ToString() end
-- Move handles of a unit: every FRoutedEventHandle property on its own BP classes (names vary:
-- "Skill Handle_X", "SkillHandle_X", "Skill Hande_X"), except the base class's DEBUG_OverrideSkillRouting.
P.dname = dname
function P.moves(u)
  local out, cls = {}, u:GetClass()
  while cls and cls:IsValid() do
    local cname = cls:GetFName():ToString()
    if cname == "BP_jRPG_Character_Battle_Base_C" or not cname:find("^BP_") then break end
    cls:ForEachProperty(function(p)
      local ok, st = pcall(function() return p:GetStruct():GetFName():ToString() end)
      if ok and st and st:find("RoutedEventHandle") then
        local n = p:GetFName():ToString()
        out[#out + 1] = { prop = n, label = (n:gsub("^Skill ?Hand?l?e_", ""):gsub("_", " ")) }
      end
    end)
    local ok, sup = pcall(function() return cls:GetSuperStruct() end); cls = ok and sup or nil
  end
  -- Bosses with phases: only offer the current phase's moves (others silently fall back to a phase-1 move).
  local okp, phase = pcall(function() return u.CurrentPhase end)
  if okp and type(phase) == "number" then
    local filtered = {}
    for _, m in ipairs(out) do
      local ph = tonumber(m.prop:match("Phase(%d+)"))
      if not ph or ph == phase then filtered[#filtered + 1] = m end
    end
    if #filtered > 0 then out = filtered end
  end
  table.sort(out, function(x, y) return x.label < y.label end)
  return out
end
-- Alive units on the other side from u.
function P.opponents(u)
  local bm = U.bm(); local mine = u["Enemy?"]; local out, seen = {}, {}
  for _, arr in ipairs({ bm.PlayerCharacters, bm.Enemies }) do
    for i = 1, #arr do local c = arr[i]
      if c:IsValid() and not seen[c:GetAddress()] and c["Enemy?"] ~= mine and c.AC_jRPG_CharacterStats.CurrentHP > 0 then
        seen[c:GetAddress()] = true; out[#out + 1] = c end end
  end
  return out
end
-- Only hero classes have a counter attack; enemy classes inherit BP_jRPG_Enemy_Battle_Base_C.
function P.isEnemyClass(c)
  local cls = c:GetClass()
  while cls and cls:IsValid() do
    if cls:GetFName():ToString() == "BP_jRPG_Enemy_Battle_Base_C" then return true end
    local ok, sup = pcall(function() return cls:GetSuperStruct() end); cls = ok and sup or nil
  end
  return false
end
function P.execute(u, move, target)
  -- A full parry by a non-hero would start a counter it can't perform and stall the battle.
  u.CanBeCountered = not P.isEnemyClass(target)
  local sg, dg = u[move.prop].GUID_2_DFA374874639D7D56F0B8E8613D03461, u.DEBUG_OverrideSkillRouting.GUID_2_DFA374874639D7D56F0B8E8613D03461
  dg.A, dg.B, dg.C, dg.D = sg.A, sg.B, sg.C, sg.D
  U.bm().DEBUG_RandomHeroAcquireOverride = target
  E33V_TARGET_FOR[u:GetAddress()] = target
  u["ControlledByBattleAI?"] = true
  pcall(function() U.bm().LGUI_Actor_BattleWheels:SetActorHiddenInGame(false) end)
  -- Same HUD signals a hero turn sends once an action is picked (clears the "choosing" overlay).
  pcall(function() local w = U.bm().BattleScreenWidget; w:OnPlayerChoseAction(); w:OnPlayerTurnEnd() end)
  log(dname(u) .. " uses " .. move.label .. " on " .. dname(target))
  u:PerformActionByAI_Internal()
end
function P.wait(u)
  UI.close(); UI.onPick, UI.onBack = nil, nil
  pcall(function() U.bm().LGUI_Actor_BattleWheels:SetActorHiddenInGame(false) end)
  pcall(function() local w = U.bm().BattleScreenWidget; w:OnPlayerChoseAction(); w:OnPlayerTurnEnd() end)
  E.ap[u:GetAddress()] = math.min(E.AP_MAX, (E.ap[u:GetAddress()] or 0) + 1)
  log(dname(u) .. " waits (+1 AP)")
  -- Same path the game uses for a skipped (stunned) turn: End Character Turn + On Action Finished.
  u["ControlledByBattleAI?"] = true
  local bm = U.bm()
  bm["End Character Turn"](bm, 1000.0)
  u["On Action Finished"](u, {})
end
function P.open(u)
  local moves = P.moves(u)
  local ap = E.ap[u:GetAddress()] or 0
  local labels = {}
  for i, m in ipairs(moves) do
    local c = E.moveCost(u, m); m.cost = c
    labels[i] = ("%s[%d AP] %s"):format(c > ap and "x " or "", c, m.label)
  end
  labels[#labels + 1] = "Wait (+1 AP)"
  local phaseIdx
  if PH and PH.hasNext(u) then
    labels[#labels + 1] = ("%s[%d AP] PHASE UP  (needs HP <= %d%%)"):format(PH.canPhaseUp(u) and "" or "x ", PH.UP_COST, PH.UP_MAX_HP * 100)
    phaseIdx = #labels
  end
  UI.close()
  -- The hero-turn flow attached the game's action wheel to this unit; hide it while our picker is open.
  pcall(function() U.bm().LGUI_Actor_BattleWheels:SetActorHiddenInGame(true) end)
  UI.make(("%s - choose a move   (AP %d/%d)"):format(dname(u), ap, E.AP_MAX), labels)
  UI.onPick = function(i)
    if phaseIdx and i == phaseIdx then
      if not PH.canPhaseUp(u) then UI.title:SetText(FText(("Phase up needs %d AP and HP <= %d%%"):format(PH.UP_COST, PH.UP_MAX_HP * 100))); return end
      PH.phaseUp(u); P.wait(u); return
    end
    if i > #moves then P.wait(u); return end
    local move = moves[i]
    if move.cost > ap then UI.title:SetText(FText(("Not enough AP: %s costs %d, you have %d"):format(move.label, move.cost, ap))); return end
    local opp = P.opponents(u)
    if #opp == 0 then UI.title:SetText(FText("No target available")); return end
    local tl = {}; for j, c in ipairs(opp) do tl[j] = dname(c) .. "  (" .. math.floor(c.AC_jRPG_CharacterStats.CurrentHP) .. " HP)" end
    UI.close()
    UI.make(dname(u) .. " - " .. move.label .. " -> target", tl)
    UI.onBack = function() P.open(u) end
    UI.onPick = function(j)
      UI.close(); UI.onPick, UI.onBack = nil, nil
      E.ap[u:GetAddress()] = ap - move.cost
      E.snapshot(u, move, opp[j])
      P.execute(u, move, opp[j])
    end
  end
  UI.onBack = nil
end
