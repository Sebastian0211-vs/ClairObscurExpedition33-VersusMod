-- E33 Versus boss phases (requires versus.lua, picker.lua, economy.lua).
-- Rules (user design): phase-1 death is a real death; phasing up is a hard-to-trigger super move;
-- later phases can also be picked directly in the team builder at a higher cost.
PH = PH or {}
PH.UP_COST, PH.UP_MAX_HP = 7, 0.5
PH.armed = PH.armed or {}      -- addr -> hp fraction to restore after the game's transition
PH.dead = PH.dead or {}        -- addr -> true: a boss whose phase-1 "death" the game prevented (counts as dead)
function PH.phaseOf(u) local ok, v = pcall(function() return u.CurrentPhase end); return (ok and type(v) == "number") and v or nil end
function PH.hasNext(u)
  local p = PH.phaseOf(u); if not p then return false end
  local ok, v = pcall(function() return u["CanEnterPhase" .. (p + 1)] end)
  return ok and v ~= nil
end
function PH.hpFrac(u) local st = u.AC_jRPG_CharacterStats; return st.CurrentHP / math.max(1, V.maxHP(u)) end
-- The game "prevents" a phase-1 boss death: it arms the next phase and leaves the boss at ~1 HP. In versus that is a
-- real death. Only that combination counts (Goblu spawns with CanEnterPhase1 already true, at full HP).
function PH.isPhaseDeath(u)
  local addr = u:GetAddress(); local p = PH.phaseOf(u); if not p or PH.armed[addr] then return false end
  local ok, armedByGame = pcall(function() return u["CanEnterPhase" .. (p + 1)] end)
  return ok and armedByGame == true and PH.hpFrac(u) <= 0.02
end
-- Per frame (V.frameCheck): mark it the moment it happens, so a finishing blow ends the match at once.
function PH.watch(u)
  local addr = u:GetAddress()
  if PH.dead[addr] or not PH.isPhaseDeath(u) then return end
  PH.dead[addr] = true
  u["CanEnterPhase" .. (PH.phaseOf(u) + 1)] = false
  V.log(("%s phase death -> counts as dead"):format(u:GetFName():ToString()))
end
-- Turn start. Killing the unit whose turn it is crashes the game, so: its own turn is skipped (returns true), and it is
-- removed from the battle at the next turn start of ANOTHER unit.
function PH.onTurn(u)
  pcall(PH.watch, u)
  local cur = u:GetAddress()
  for _, x in ipairs(V.units or {}) do
    local a = x:IsValid() and x:GetAddress()
    if a and PH.dead[a] and a ~= cur and not PH.dead["kicked" .. a] then
      PH.dead["kicked" .. a] = true
      local ok, err = pcall(U.kick, x)
      V.log(("%s removed from the battle: %s"):format(x:GetFName():ToString(), ok and "ok" or tostring(err)))
    end
  end
  if PH.dead[cur] then pcall(SYNC.endTurn, u); return true end
  return false
end
-- After the boss's turn-start transition ran, restore the HP fraction the player had when phasing up.
function PH.afterTransition(u)
  local addr = u:GetAddress(); local frac = PH.armed[addr]; if not frac then return end
  local p = PH.phaseOf(u)
  if p and p ~= PH.armed["p" .. addr] then
    PH.armed[addr], PH.armed["p" .. addr] = nil, nil
    local hp = math.max(1, V.maxHP(u) * frac)
    u.AC_jRPG_CharacterStats.CurrentHP = hp
    V.log(("%s is now phase %d, HP kept at %.0f%%"):format(u:GetFName():ToString(), p, frac * 100))
  end
end
function PH.canPhaseUp(u)
  return PH.hasNext(u) and (E.ap[u:GetAddress()] or 0) >= PH.UP_COST and PH.hpFrac(u) <= PH.UP_MAX_HP
end
function PH.phaseUp(u)
  local addr = u:GetAddress(); local p = PH.phaseOf(u)
  E.ap[addr] = (E.ap[addr] or 0) - PH.UP_COST
  PH.armed[addr], PH.armed["p" .. addr] = PH.hpFrac(u), p
  u["CanEnterPhase" .. (p + 1)] = true
  V.log(("%s PHASE UP armed (%d -> %d)"):format(u:GetFName():ToString(), p, p + 1))
end
-- Start a unit directly in a later phase (roster entries "<row>#P2"): phase number + the BP's cosmetic transition.
function PH.startInPhase(u, phase)
  if not PH.phaseOf(u) then return end
  u.CurrentPhase = phase
  pcall(function() u["TransitionToPhase" .. phase .. "Real"](u) end)
  V.log(("%s starts in phase %d"):format(u:GetFName():ToString(), phase))
end
