-- E33 Versus "Versus AI": team 2 is played by the computer (local versus only; V.cfg.ai = true).
-- Monsters / bosses use the same move path as a player's wheel (loadout, AP costs, P.execute with our targets).
-- Heroes have no AI in the game: they use the game's forced auto-attack path (stats.TargetedCharacters +
-- SelectedActionType = 1 + ExecuteAttackAction), with a random number of successful combo presses.
-- (requires versus.lua, picker.lua, economy.lua, wheel.lua, phases.lua, sync.lua for SYNC.after)
AI = AI or {}
AI.SIDE = "B"
AI.THINK = 1.1            -- seconds before the AI acts (the turn stays readable)
local function alog(s) V.log("AI " .. s) end

function AI.active() return V.cfg.ai == true and not V.online end
-- V.cfg.aiBoth (developer test, set from the dev bridge): the computer plays both teams.
function AI.controls(c)
  local side = V.sideOf and V.sideOf[c:GetAddress()]
  return AI.active() and side ~= nil and (side == AI.SIDE or V.cfg.aiBoth == true)
end

-- Target: usually the weakest opponent (lowest HP share), sometimes a random one.
function AI.pickTarget(u)
  local opp = P.opponents(u); if #opp == 0 then return nil end
  if math.random() < 0.35 then return opp[math.random(#opp)] end
  local best, bestF
  for _, t in ipairs(opp) do
    local f = 1; pcall(function() f = t.AC_jRPG_CharacterStats.CurrentHP / math.max(1, V.maxHP(t)) end)
    if not bestF or f < bestF then best, bestF = t, f end
  end
  return best
end

-- Monster move: the strongest affordable attack most of the time, a random affordable one otherwise; with too little
-- AP, the free basic attack (+1 AP) like a player pressing Attack.
function AI.pickMove(u)
  local list = WH.wheelMoves(u)
  local ap = E.ap[u:GetAddress()] or 0
  local basic = WH.basicMove(u, list)
  local ok = {}
  for _, m in ipairs(list) do
    local c = E.moveCost(u, m)
    if c <= ap and m ~= basic and not WH.isSupport(m.prop) then ok[#ok + 1] = { m = m, cost = c } end
  end
  if #ok == 0 or math.random() < 0.25 then return basic, 0, true end
  table.sort(ok, function(a, b) return a.cost > b.cost end)
  local pick = (math.random() < 0.6) and ok[1] or ok[math.random(#ok)]
  return pick.m, pick.cost, false
end

function AI.monsterTurn(u)
  if not (u and u:IsValid()) or V.ended then return end
  local a = u:GetAddress()
  -- boss super move when allowed (low HP, enough AP): the game's own phase change
  if PH and PH.canPhaseUp(u) and math.random() < 0.6 then
    alog(P.dname(u) .. " phases up"); PH.phaseUp(u); P.wait(u); return
  end
  local move, cost, basic = AI.pickMove(u)
  local target = AI.pickTarget(u)
  if not (move and target) then alog(P.dname(u) .. " waits"); P.wait(u); return end
  E.ap[a] = basic and math.min(E.AP_MAX, (E.ap[a] or 0) + 1) or ((E.ap[a] or 0) - cost)
  WH.setAP(u, E.ap[a])
  alog(("%s: %s on %s (AP %d)"):format(P.dname(u), move.label or move.prop, P.dname(target), E.ap[a]))
  V.applyPerspective(u)
  E.snapshot(u, move, target)
  P.execute(u, move, target)
end

function AI.heroTurn(u)
  if not (u and u:IsValid()) or V.ended then return end
  local target = AI.pickTarget(u)
  if not target then alog(P.dname(u) .. ": no target"); return end
  local bm = U.bm()
  bm.DEBUG_ComboAutoSuccessCount = math.random(0, 3)   -- an imperfect player
  alog(("%s attacks %s"):format(P.dname(u), P.dname(target)))
  pcall(function() bm.LGUI_Actor_BattleWheels:SetActorHiddenInGame(true) end)
  pcall(function() local w = bm.BattleScreenWidget; w:OnPlayerChoseAction(); w:OnPlayerTurnEnd() end)
  local st = u.AC_jRPG_CharacterStats
  st.TargetedCharacters = { target }
  st.SelectedActionType = 1
  u:ExecuteAttackAction()
end

-- From V.onTurnStart (local versus). Returns true when the AI takes this turn.
function AI.onTurn(c)
  AI.unblock()
  if not AI.controls(c) then return false end
  local addr = c:GetAddress()
  if E33V_CONTROLLED[addr] then
    E.onTurn(c)
    c["ControlledByBattleAI?"] = false   -- the game waits (hero flow) until we act
    pcall(function() U.bm().LGUI_Actor_BattleWheels:SetActorHiddenInGame(true) end)
    alog("turn " .. P.dname(c))
    SYNC.after(AI.THINK, function() local ok, err = pcall(AI.monsterTurn, c); if not ok then alog("ERROR " .. tostring(err)); pcall(P.wait, c) end end)
  else
    -- a hero: the game opened its action wheel for the player; keep the player's hands off it
    AI.block()
    alog("turn " .. P.dname(c) .. " (hero)")
    SYNC.after(AI.THINK, function() local ok, err = pcall(AI.heroTurn, c); if not ok then alog("ERROR " .. tostring(err)) end end)
  end
  return true
end

function AI.block()
  local pc = TICK and TICK.pc
  if pc and pc:IsValid() and not AI.blocked then pc:DisableInput(pc); AI.blocked = true end
end
function AI.unblock()
  local pc = TICK and TICK.pc
  if AI.blocked and pc and pc:IsValid() then pc:EnableInput(pc) end
  AI.blocked = false
end

-- Select screen: an empty AI team is filled at random within the cost cap (monsters / bosses of the roster).
function AI.randomTeam()
  local pool = {}
  for _, u in ipairs(V.enemyRows()) do pool[#pool + 1] = u end
  local team, left = {}, V.CAP
  for _ = 1, 40 do
    if #team >= 3 or #pool == 0 then break end
    local u = pool[math.random(#pool)]
    local c = V.cost(u)
    if c <= left then
      local copy = {}; for k, v in pairs(u) do copy[k] = v end
      team[#team + 1] = copy; left = left - c
    end
  end
  return team
end
