-- E33 Versus online battle sync (requires versus.lua, picker.lua, economy.lua, net.lua, online.lua).
-- Units are named the same on both PCs: side .. slot ("A1".."B3"). Each unit is owned by the PC of its side.
-- Owner's turn: play normally, then send the action. Opponent's turn: wait (banner), replay the received action.
-- After each action the DEFENDER's PC (it ran the parry/dodge QTE) sends the true HP/AP of every unit.
SYNC = SYNC or {}
local function argGet(a) local ok, v = pcall(function() return a:get() end); if ok then return v end; return a end
local function slog(s) V.log("SYNC " .. s) end

function SYNC.active() return V.online and V.online.inMatch end
function SYNC.uid(c) return c and V.uidOf and V.uidOf[c:GetAddress()] end
function SYNC.unit(uid)
  for _, u in ipairs(V.units or {}) do if u:IsValid() and SYNC.uid(u) == uid then return u end end
end
function SYNC.mine(c) local id = SYNC.uid(c); return id ~= nil and id:sub(1, 1) == V.online.me end

-- ---------- turn start (called from V.onTurnStart before the picker) ----------
-- Returns true when the turn belongs to the opponent (the caller must not open a local picker).
-- End a unit's turn without acting (the game's own skipped-turn path, as P.wait without the AP gain).
function SYNC.endTurn(u)
  pcall(function() local w = U.bm().BattleScreenWidget; w:OnPlayerChoseAction(); w:OnPlayerTurnEnd() end)
  u["ControlledByBattleAI?"] = true
  local bm = U.bm()
  bm["End Character Turn"](bm, 1000.0)
  u["On Action Finished"](u, {})
end
function SYNC.hideTip() if SYNC.tipShown then SYNC.tipShown = false; pcall(function() U.bm():HideBattleMenuTooltip() end) end end
function SYNC.onTurn(c)
  SYNC.hideTip()
  SYNC.unblockInput()
  pcall(function() U.bm().DEBUG_ComboAutoSuccessCount = 0 end)
  -- a hero's turn can "restart" (free aim, then an action); only flush when another unit's turn begins
  local same = SYNC.lastUnit and SYNC.lastUnit:IsValid() and SYNC.lastUnit:GetAddress() == c:GetAddress()
  if not same then
    pcall(SYNC.flushMyHero, SYNC.lastUnit)
    SYNC.turnSnap = (SYNC.mine(c) and not P.isEnemyClass(c)) and SYNC.hpSnap() or nil
  end
  SYNC.lastUnit = c
  SYNC.hookActionStart(); SYNC.hookHero(); DEF.install()   -- battle classes are loaded by now (no-ops once installed)
  if not same then DEF.stop() end
  slog("turn start " .. tostring(SYNC.uid(c)) .. (SYNC.mine(c) and " (mine)" or " (opponent)"))
  local uid = SYNC.uid(c); if not uid then return false end
  V.online.turnN = (V.online.turnN or 0) + 1
  -- I defended the last action (it was the opponent's unit): my HP values are the truth.
  if V.online.lastActor and V.online.lastActor:sub(1, 1) ~= V.online.me then SYNC.sendState() end
  V.online.lastActor = uid
  local info = { n = V.online.turnN, uid = uid }
  local tg = {}; for _, o in ipairs(P.opponents(c)) do tg[#tg + 1] = SYNC.uid(o) end
  info.targets = tg
  if P.isEnemyClass(c) then
    local mv = {}; for _, m in ipairs(P.moves(c)) do mv[#mv + 1] = m.prop end
    info.moves = mv
  else info.hero = true end
  NET.msg("turn", info)
  if SYNC.mine(c) then return false end
  -- opponent's unit: block local control and wait for their action
  SYNC.waiting = { uid = uid, unit = c }
  c["ControlledByBattleAI?"] = false
  pcall(function() U.bm().LGUI_Actor_BattleWheels:SetActorHiddenInGame(true) end)
  UI.close(); UI.onPick, UI.onBack = nil, nil
  -- the game's own battle tooltip box instead of our list menu (FText as a call argument is safe; only property
  -- assignment of a Lua FText is not)
  pcall(function() U.bm():ShowBattleMenuTooltip(FText((NET.status.peer or "Opponent") .. "'s turn"), FText(P.dname(c) .. " is choosing...")) end)
  SYNC.tipShown = true
  if not P.isEnemyClass(c) then SYNC.blockInput() end   -- the opponent drives this hero: no local menu input
  SYNC.tryApply()
  return true
end

-- ---------- outgoing actions (wrapped picker functions) ----------
function SYNC.sendAct(u, kind, fields)
  if not (SYNC.active() and SYNC.mine(u)) then return end
  local m = fields or {}; m.uid = SYNC.uid(u); m.kind = kind; m.ap = E.ap[u:GetAddress()]
  NET.msg("act", m)
  slog(("-> act %s %s %s%s"):format(m.uid, kind, tostring(m.move or m.secondary or m.atype or ""), m.combo and (" combo " .. m.combo .. "/" .. tostring(m.comboTotal)) or ""))
end
-- (Re)wrap whenever picker.lua / phases.lua (re)defined the functions, so hot reloads keep sync working.
function SYNC.wrap()
  if P.execute ~= SYNC.execW then
    local exec = P.execute
    SYNC.execW = function(u, move, target)
      if SYNC.active() and SYNC.mine(u) and not SYNC.applying then
        -- my monster attacks: send now, play it a little later so the defender's hit outcomes (parry, dodge...) reach
        -- this PC before the same hits land here (defense.lua)
        SYNC.sendAct(u, "move", { move = move.prop, target = SYNC.uid(target) })
        DEF.begin(u)
        local d = SYNC.delay()
        slog(("my move starts in %.2f s"):format(d))
        SYNC.after(d, function() exec(u, move, target) end)
        return
      end
      return exec(u, move, target)
    end
    P.execute = SYNC.execW
  end
  if P.wait ~= SYNC.waitW then
    local wait = P.wait
    SYNC.waitW = function(u)
      if not SYNC.applying and not SYNC.afterPhaseUp then SYNC.sendAct(u, "wait") end
      SYNC.afterPhaseUp = false
      return wait(u)
    end
    P.wait = SYNC.waitW
  end
  -- the picker follows a phase-up with P.wait: that wait is part of the same action, do not send it again
  if PH and PH.phaseUp and PH.phaseUp ~= SYNC.phaseW then
    local phaseUp = PH.phaseUp
    SYNC.phaseW = function(u) if not SYNC.applying then SYNC.sendAct(u, "phaseup"); SYNC.afterPhaseUp = true end; return phaseUp(u) end
    PH.phaseUp = SYNC.phaseW
  end
end
SYNC.wrap()

-- ---------- incoming ----------
SYNC.queue = SYNC.queue or {}
function SYNC.onAct(m) SYNC.queue[#SYNC.queue + 1] = m; SYNC.tryApply() end
function SYNC.tryApply()
  local w = SYNC.waiting; if not w then return end
  for i, m in ipairs(SYNC.queue) do
    if m.uid == w.uid then
      table.remove(SYNC.queue, i)
      SYNC.waiting = nil
      SYNC.hideTip(); UI.close(); UI.onPick, UI.onBack = nil, nil
      local u = w.unit
      if m.ap then E.ap[u:GetAddress()] = m.ap end
      SYNC.applying = true
      local ok, err = pcall(function()
        if m.kind == "move" then
          local move; for _, mv in ipairs(P.moves(u)) do if mv.prop == m.move then move = mv end end
          local target = SYNC.unit(m.target)
          if not (move and target) then error("unknown move/target " .. tostring(m.move) .. " " .. tostring(m.target)) end
          E.snapshot(u, move, target)
          DEF.begin(u)
          P.execute(u, move, target)
        elseif m.kind == "phaseup" then PH.phaseUp(u); P.wait(u)
        elseif m.kind == "hero" then SYNC.applyShots(m.shots); SYNC.replayHero(u, m)
        elseif m.kind == "item" then
          if P.isEnemyClass(u) then   -- monsters: applied by the mod on both PCs (WH.applyItem)
            local t = m.targets and m.targets[1] and SYNC.unit(m.targets[1])
            WH.applyItem(u, m.item, t); SYNC.endTurn(u)
          else SYNC.replayHero(u, { atype = 3, secondary = m.item, targets = m.targets }) end
        elseif m.kind == "freeaim" then SYNC.applyShots(m.shots); SYNC.endTurn(u)
        else P.wait(u) end
      end)
      SYNC.applying = false
      slog(("<- act %s %s %s %s"):format(m.uid, m.kind, tostring(m.move or ""), ok and "applied" or ("FAILED " .. tostring(err))))
      if not ok then pcall(P.wait, u) end   -- never leave the battle stuck
      return
    end
  end
end

-- ---------- authoritative state ----------
function SYNC.sendState()
  local units = {}
  for _, u in ipairs(V.units or {}) do
    local id = SYNC.uid(u)
    if id and u:IsValid() then
      units[id] = { hp = math.floor(u.AC_jRPG_CharacterStats.CurrentHP * 10 + 0.5) / 10, ap = E.ap[u:GetAddress()] }
    end
  end
  NET.msg("state", { n = V.online.turnN, units = units })
end
function SYNC.onState(m)
  local fixed = {}
  for id, s in pairs(m.units or {}) do
    local u = SYNC.unit(id)
    if u then
      local st = u.AC_jRPG_CharacterStats
      if s.hp and math.abs(st.CurrentHP - s.hp) >= 1 then
        fixed[#fixed + 1] = ("%s %.0f->%.0f"):format(id, st.CurrentHP, s.hp)
        st.CurrentHP = s.hp
      end
      if s.ap then E.ap[u:GetAddress()] = s.ap end
    end
  end
  if #fixed > 0 then slog("state correction: " .. table.concat(fixed, ", ")) end
end
function SYNC.onTurnMsg(m)
  if V.online and m.n and V.online.turnN and m.n == V.online.turnN and m.uid ~= V.online.lastActor then
    slog(("DESYNC turn %d: here %s, opponent %s"):format(m.n, tostring(V.online.lastActor), tostring(m.uid)))
    if not V.online.desyncSent then V.online.desyncSent = true; pcall(ONLINE.uploadLog, "desync") end
  end
end
function SYNC.install()
  SYNC.hookActionStart()
  SYNC.hookHero()
  NET.on("msg:act", SYNC.onAct)
  NET.on("msg:state", SYNC.onState)
  NET.on("msg:turn", SYNC.onTurnMsg)
  NET.on("msg:hit", DEF.onHit)
end

-- ---------- timing ----------
-- Head start the defender's PC gets on my monster attacks: the outcome of each hit must travel back before the same
-- hit lands here. Round trip (sidecar ping) + the run-to-run variation of attack timing (~0.35 s measured).
function SYNC.delay()
  local rtt = (tonumber(NET.status.ping_ms) or 100) / 1000
  return math.min(1.2, 0.45 + 1.5 * rtt)
end
SYNC.later = SYNC.later or {}
function SYNC.after(sec, fn) SYNC.later[#SYNC.later + 1] = { at = os.clock() + sec, fn = fn } end
-- per frame (ticker.lua)
function SYNC.tick()
  if #SYNC.later > 0 then
    local now, keep = os.clock(), {}
    for _, j in ipairs(SYNC.later) do
      if now >= j.at then local ok, err = pcall(j.fn); if not ok then slog("scheduled call failed: " .. tostring(err)) end
      else keep[#keep + 1] = j end
    end
    SYNC.later = keep
  end
  if DEF and DEF.frame then DEF.frame() end
end

-- ---------- defender-only QTE ----------
-- When MY unit attacks, the defender sits at the other PC: block the game's player input here (parry/dodge) until the
-- next turn starts. The other PC runs the defender's QTE and its state message corrects our HP numbers.
function SYNC.blockInput()
  local pc = TICK and TICK.pc
  if pc and pc:IsValid() and not SYNC.inputBlocked then pc:DisableInput(pc); SYNC.inputBlocked = true; slog("input blocked (opponent defends)") end
end
function SYNC.unblockInput()
  local pc = TICK and TICK.pc
  if SYNC.inputBlocked and pc and pc:IsValid() then pc:EnableInput(pc) end
  SYNC.inputBlocked = false
end
-- Hook callbacks only delegate to these named functions: a registered closure keeps the code it was created with,
-- so inline logic would survive hot reloads unchanged.
function SYNC.cbAcquire(ctx) if SYNC.active() and SYNC.mine(ctx:get()) then SYNC.blockInput() end end
function SYNC.hookActionStart()
  if E33V_SYNC_ACTHOOK then return end
  local base = "/Game/jRPGTemplate/Blueprints/Basics/BP_jRPG_Character_Battle_Base.BP_jRPG_Character_Battle_Base_C:"
  E33V_SYNC_ACTHOOK = pcall(RegisterHook, base .. "Acquire Targets", function(ctx) return SYNC.cbAcquire(ctx) end)
end

-- ---------- hero actions ----------
-- The battle wheel drives the battle manager: SelectAction(type) [+ SelectSecondaryAction(skill)] then, once the target is
-- confirmed, RequestActionExecution(targets). The owner's PC records these; the other PC replays the same three calls.
local function curChar() local bm = U.bm(); return bm and bm.CurrentCharacter end
function SYNC.cbSelectAction(ctx, t)
  if not (SYNC.active() and not SYNC.applying and SYNC.mine(curChar())) then return end
  SYNC.hero = { atype = argGet(t) }
end
function SYNC.cbSelectSecondary(ctx, n)
  if not (SYNC.active() and not SYNC.applying and SYNC.mine(curChar())) then return end
  SYNC.hero = SYNC.hero or {}
  local v = argGet(n); SYNC.hero.secondary = (type(v) == "userdata" and v.ToString) and v:ToString() or tostring(v)
end
function SYNC.cbRequest(ctx, targets)
  local u = curChar()
  if not (SYNC.active() and not SYNC.applying and SYNC.mine(u)) then return end
  local arr = argGet(targets); local ids = {}
  pcall(function() for i = 1, #arr do local t = argGet(arr[i]); ids[#ids + 1] = SYNC.uid(t) or "?" end end)
  local h = SYNC.hero or {}
  h.atype = h.atype or U.bm().SelectedAction   -- items never call SelectAction
  -- Sent when this action has FINISHED (next turn start / match end), so the skill-combo result can go with it.
  SYNC.pendingHero = { unit = u, atype = h.atype, secondary = h.secondary, targets = ids, shots = SYNC.shotsSince(SYNC.turnSnap) }
  SYNC.hero = nil
  slog(("hero action recorded: atype %s %s -> %s"):format(tostring(h.atype), tostring(h.secondary), table.concat(ids, ",")))
end
function SYNC.hookHero()
  if E33V_SYNC_HEROHOOK then return end
  local BM = "/Game/jRPGTemplate/Blueprints/Components/AC_jRPG_BattleManager.AC_jRPG_BattleManager_C:"
  local function cur() local bm = U.bm(); return bm and bm.CurrentCharacter end
  local ok1 = pcall(RegisterHook, BM .. "SelectAction", function(ctx, t) return SYNC.cbSelectAction(ctx, t) end)
  local ok2 = pcall(RegisterHook, BM .. "SelectSecondaryAction", function(ctx, n) return SYNC.cbSelectSecondary(ctx, n) end)
  local ok3 = pcall(RegisterHook, BM .. "RequestActionExecution", function(ctx, t) return SYNC.cbRequest(ctx, t) end)
  E33V_SYNC_HEROHOOK = ok1 and ok2 and ok3
  slog(("hero hooks: %s %s %s"):format(tostring(ok1), tostring(ok2), tostring(ok3)))
end
-- Called at the next turn start after one of MY heroes acted: send the action with its combo result, or, if no action
-- was confirmed (free aim "Viser" shots go through raycasts, not RequestActionExecution), report free aim + true HP.
function SYNC.flushMyHero(prev)
  local snap = SYNC.turnSnap; SYNC.turnSnap = nil
  if not (prev and prev:IsValid() and SYNC.mine(prev) and not P.isEnemyClass(prev)) then SYNC.pendingHero = nil; return end
  local ph = SYNC.pendingHero; SYNC.pendingHero = nil
  if ph and ph.unit:IsValid() and ph.unit:GetAddress() == prev:GetAddress() then
    local hits, total = 0, 0
    pcall(function()
      local hist = prev.ComboSuccessHistory
      for i = 1, #hist do total = total + 1; if argGet(hist[i]) == true then hits = hits + 1 end end
    end)
    SYNC.sendAct(prev, "hero", { atype = ph.atype, secondary = ph.secondary, targets = ph.targets, combo = hits, comboTotal = total, shots = ph.shots })
  else
    SYNC.sendAct(prev, "freeaim", { shots = SYNC.shotsSince(snap) })
  end
end
-- Free-aim shots: HP lost by the opponents between MY hero's turn start and the moment it confirms an action (or ends
-- its turn) = damage from shots. (A damage-event hook crashed the game on the first hit, so we diff HP snapshots.)
function SYNC.hpSnap()
  local t = {}
  for _, u in ipairs(V.units or {}) do local id = SYNC.uid(u); if id and u:IsValid() then t[id] = u.AC_jRPG_CharacterStats.CurrentHP end end
  return t
end
function SYNC.shotsSince(snap)
  if not snap then return nil end
  local now, out = SYNC.hpSnap(), {}
  for id, hp in pairs(snap) do
    local d = hp - (now[id] or hp)
    if d >= 1 and id:sub(1, 1) ~= V.online.me then out[#out + 1] = { target = id, dmg = d } end
  end
  return #out > 0 and out or nil
end
function SYNC.applyShots(list)
  for _, sh in ipairs(list or {}) do
    local t = SYNC.unit(sh.target)
    if t then local st = t.AC_jRPG_CharacterStats; st.CurrentHP = math.max(0, st.CurrentHP - (sh.dmg or 0)) end
  end
end
function SYNC.replayHero(u, m)
  local bm = U.bm()
  bm.DEBUG_ComboAutoSuccessCount = m.combo or 0   -- the owner's combo hits succeed automatically here
  local targets = {}
  for _, id in ipairs(m.targets or {}) do local t = SYNC.unit(id); if t then targets[#targets + 1] = t end end
  if m.atype == 3 then bm.SelectedAction = 3   -- items: the wheel sets the action type directly
  elseif m.atype then bm:SelectAction(m.atype) end
  if m.secondary and m.secondary ~= "" and m.secondary ~= "None" then bm:SelectSecondaryAction(FName(m.secondary)) end
  bm:RequestActionExecution(targets)
end

-- ---------- research: which functions a hero action goes through (for remote hero replay) ----------
function SYNC.hookHeroResearch()
  if E33V_HERO_RESEARCH then return end
  E33V_HERO_RESEARCH = true
  local base = "/Game/jRPGTemplate/Blueprints/Basics/BP_jRPG_Character_Battle_Base.BP_jRPG_Character_Battle_Base_C:"
  for _, fn in ipairs({ "ExecuteSkillScriptFromState", "ExecuteSkillScript", "ExecuteSkillAction", "OnStartChoosingSkill", "Acquire Targets", "ResetCurrentSkill" }) do
    pcall(RegisterHook, base .. fn, function(ctx, a)
      local c = ctx:get()
      local extra = ""
      pcall(function() local v = a:get(); extra = v.GetFullName and v:GetFullName() or tostring(v) end)
      V.log(("HERO-RESEARCH %s %s %s"):format(fn, P.dname(c), extra))
    end)
  end
end
