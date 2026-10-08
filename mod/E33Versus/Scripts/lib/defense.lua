-- E33 Versus online: the opponent's parries / dodges / jumps seen live on both PCs (requires sync.lua, versus.lua).
-- Monster attacks: the DEFENDER's PC is the truth. After every hit on one of its units it sends the outcome
-- {k="hit", uid, n (that unit's hit number in this action), def = parry|gparry|dodge|jump|nil}.
-- The attacker's PC starts the same attack a little later (SYNC.delay) so the outcome of hit n arrives before its own
-- hit n; until that hit lands it holds the matching flag on the target (IsParrying...), which the game reads at
-- impact (verified: holding IsParrying parries every hit), and plays the guard animation once.
-- Hit capture: post-hook on the target's stats ReceiveDamage (runs after the hit is evaluated, before HP drops,
-- with the Is* flags still those used for the hit). Projectiles: ReceiveDamageFromObject (same handler, deduplicated).
-- Hero attacks go through neither: their results are streamed by a per-frame HP/shield watcher (DEF.watch*), with the
-- ATTACKER's PC as the truth (its combo presses are live).
DEF = DEF or {}
local function dlog(s) V.log("DEF " .. s) end
DEF.FLAG = { parry = "IsParrying", gparry = "IsGradientParrying", dodge = "IsDodging", jump = "IsJumping" }
DEF.ANIM = { parry = "TryStartParry", gparry = "TryStartGradientParry", dodge = "TryStartDodge", jump = "TryStartJump" }

-- One action at a time: who acts, hit counters per target uid, outcomes received per target uid.
function DEF.begin(u)
  DEF.act = { actor = SYNC.uid(u), mine = SYNC.mine(u), monster = P.isEnemyClass(u), n = {}, res = {}, anim = {}, hp = {}, at = {} }
end
function DEF.stop() DEF.act = nil; DEF.watch = nil end

-- What a hit left on a unit: HP, shield, break bar and statuses (sent ~0.1 s after the hit, once the game applied it).
function DEF.resultOf(t)
  local st = t.AC_jRPG_CharacterStats
  local r = { hp = st.CurrentHP, shield = st.CurrentShieldPoints }
  pcall(function() r.brk = tonumber(st.StunBreakBarCurrent) end)
  pcall(function() r.buffs = ST.buffList(t) end)
  return r
end
-- Write a received hit result (the truth's) onto a unit; returns a short text of what changed.
function DEF.writeResult(t, r)
  local st = t.AC_jRPG_CharacterStats
  local done = {}
  local before = st.CurrentHP
  if r.hp and math.abs((before or 0) - r.hp) >= 1 then st.CurrentHP = r.hp; done[#done + 1] = ("HP %.0f -> %.0f"):format(before or 0, r.hp) end
  if r.shield and (st.CurrentShieldPoints or 0) ~= r.shield then
    pcall(function() st:SetCurrentShieldPoints(r.shield, "E33Versus hit") end); done[#done + 1] = "shield " .. tostring(r.shield)
  end
  if r.brk and tonumber(st.StunBreakBarCurrent) ~= r.brk then
    pcall(function() st:SetCurrentBreakBarDamage(r.brk, st, "E33Versus hit") end); done[#done + 1] = "break " .. tostring(r.brk)
  end
  if r.buffs then
    local ok, n = pcall(ST.applyBuffs, t, r.buffs, st)
    if ok and n and n > 0 then done[#done + 1] = n .. " status change(s)" end
  end
  return table.concat(done, ", ")
end

-- Defender's PC: the opponent's attacking unit acquires its targets = the attack really started here.
function DEF.onAcquire(ctx)
  local a = DEF.act
  if not (a and not a.mine and not a.beganSent) then return end
  local u = ctx:get()
  if not (u and SYNC.uid(u) == a.actor) then return end
  a.beganSent = true
  NET.msg("began", { actor = a.actor })
end
-- Attacker's PC: the defender's attack started -> start ours a moment later.
function DEF.onBegan(m)
  local a = DEF.act
  if not (a and a.mine and a.start and m.actor == a.actor) then return end
  SYNC.after(SYNC.BEGAN_MARGIN, function() a.start("opponent began") end)
end

-- Which defense a unit is in right now (flags read at the hit).
function DEF.kindOf(t)
  if t.IsGradientParrying then return "gparry" end
  if t.IsParrying then return "parry" end
  if t.IsDodging then return "dodge" end
  if t.IsJumping then return "jump" end
  return nil
end

-- ---------- hit hook (named function: hook closures survive hot reloads unchanged) ----------
function DEF.cbHit(ctx, fromObj)
  local a = DEF.act; if not (a and a.monster and SYNC.active()) then return end
  local st = ctx:get(); local t = st and st:GetOwner()
  local uid = t and SYNC.uid(t); if not uid then return end
  if not fromObj and a.objAt and a.objAt[uid] and os.clock() - a.objAt[uid] < 0.05 then return end   -- counted by the projectile hook
  a.at[uid] = os.clock()
  local k = (a.n[uid] or 0) + 1; a.n[uid] = k
  if not a.mine and uid:sub(1, 1) == V.online.me then
    -- defender's PC: my unit was hit by the opponent's monster -> tell them how it went
    local def = DEF.kindOf(t)
    NET.msg("hit", { uid = uid, n = k, def = def, actor = a.actor })
    dlog(("-> hit %s #%d %s"):format(uid, k, tostring(def or "-")))
    -- the hit's result (crit, shield use, statuses all included): HP / shield once the game applied it
    SYNC.after(0.1, function()
      if not t:IsValid() then return end
      local m = DEF.resultOf(t); m.uid, m.n, m.actor = uid, k, a.actor
      NET.msg("hitres", m)
    end)
  elseif a.mine then
    -- attacker's PC: this hit is done; drop the flag we held for it
    local def = a.res[uid] and a.res[uid][k]
    if def and DEF.FLAG[def] then pcall(function() t[DEF.FLAG[def]] = false end) end
    SYNC.after(0.1, function() DEF.applyResult(uid, k) end)
    dlog(("hit %s #%d here: %s (%s)"):format(uid, k, tostring(def or "-"), a.res[uid] and a.res[uid][k] ~= nil and "known" or "no outcome yet"))
  end
end
-- Projectile hits. If ReceiveDamageFromObject runs ReceiveDamage inside, that inner (post) hook already counted this
-- hit a moment ago: skip it here.
function DEF.cbHitObj(ctx)
  if not SYNC.active() then return end
  local st = ctx:get(); local t = st and st:GetOwner()
  local uid = t and SYNC.uid(t); if not uid then return end
  local a = DEF.act
  -- research (R3): does a HERO attack land here? (hero hits never reach ReceiveDamage)
  if not (a and a.monster) then dlog(("damage from object on %s (hero action: %s)"):format(uid, tostring(DEF.watch and DEF.watch.actor))); return end
  -- one projectile hit fires BOTH hooks (this one first, seen 2026-10-08): count it once
  if a.at[uid] and os.clock() - a.at[uid] < 0.05 then return end
  a.objAt = a.objAt or {}; a.objAt[uid] = os.clock()
  dlog("projectile hit on " .. uid)
  return DEF.cbHit(ctx, true)
end
function DEF.install()
  local stats = "/Game/jRPGTemplate/Blueprints/Components/AC_jRPG_CharacterBattleStats.AC_jRPG_CharacterBattleStats_C:"
  if not E33V_DEF_HOOK then
    E33V_DEF_HOOK = pcall(RegisterHook, stats .. "ReceiveDamage", function(ctx) return DEF.cbHit(ctx) end)
    dlog("hit hook: " .. tostring(E33V_DEF_HOOK))
  end
  if not E33V_DEF_OBJHOOK then
    E33V_DEF_OBJHOOK = pcall(RegisterHook, stats .. "ReceiveDamageFromObject", function(ctx) return DEF.cbHitObj(ctx) end)
    dlog("projectile hit hook: " .. tostring(E33V_DEF_OBJHOOK))
  end
end

-- ---------- outcomes from the defender ----------
function DEF.onHit(m)
  local a = DEF.act; if not (a and a.mine and m.uid and m.n) then return end
  if m.actor and m.actor ~= a.actor then return end
  a.res[m.uid] = a.res[m.uid] or {}
  a.res[m.uid][m.n] = m.def or false
  local done = a.n[m.uid] or 0
  if m.n <= done then dlog(("<- hit %s #%d %s arrived after that hit (state fixes HP)"):format(m.uid, m.n, tostring(m.def))) end
end

-- ---------- hit results from the defender (attacker's PC) ----------
-- Applied once our own hit #n landed (whichever comes last): both screens show the same HP / shield hit by hit, so
-- random rolls (crits, procs) made here never stick.
function DEF.onHitRes(m)
  if m.hero then
    local w = DEF.watch
    if not (w and not w.mine and m.uid and m.n and (not m.actor or m.actor == w.actor)) then return end
    w.got[m.uid] = w.got[m.uid] or {}; w.got[m.uid][m.n] = m
    if (w.n[m.uid] or 0) >= m.n then DEF.watchApply(m.uid, m.n) end
    return
  end
  local a = DEF.act; if not (a and a.mine and m.uid and m.n) then return end
  if m.actor and m.actor ~= a.actor then return end
  a.hp[m.uid] = a.hp[m.uid] or {}
  a.hp[m.uid][m.n] = m
  if (a.n[m.uid] or 0) >= m.n then DEF.applyResult(m.uid, m.n) end
end
function DEF.applyResult(uid, k)
  local a = DEF.act; if not (a and a.mine) then return end
  local r = a.hp[uid] and a.hp[uid][k]
  if not r or r.applied then return end
  -- a later result for this unit already applied: an older one must not overwrite it
  if (a.lastApplied and a.lastApplied[uid] or 0) > k then return end
  local t = SYNC.unit(uid); if not t then return end
  r.applied = true
  a.lastApplied = a.lastApplied or {}; a.lastApplied[uid] = k
  local what = DEF.writeResult(t, r)
  if what ~= "" then dlog(("hit %s #%d result: %s (defender's)"):format(uid, k, what)) end
end

-- ---------- hero attacks: per-frame watcher ----------
-- Started when a hero action is confirmed (owner's PC: SYNC.cbRequest) or replayed (other PC: SYNC.replayHero).
-- Owner's PC: every HP / shield change of any unit during the action = one result, sent ~0.1 s later (statuses
-- settled). Other PC: its own k-th change of a unit takes the owner's k-th result (whichever arrives last), so both
-- screens show the same numbers hit by hit; the next turn's snapshot fixes anything left.
function DEF.watchStart(u, mine)
  local w = { actor = SYNC.uid(u), mine = mine, last = {}, n = {}, got = {}, applied = {} }
  for _, x in ipairs(V.units or {}) do
    local id = SYNC.uid(x)
    if id and x:IsValid() then local st = x.AC_jRPG_CharacterStats; w.last[id] = { st.CurrentHP, st.CurrentShieldPoints } end
  end
  DEF.watch = w
  dlog(("hero watch %s (%s)"):format(tostring(w.actor), mine and "owner" or "replay"))
end
function DEF.watchFrame()
  local w = DEF.watch; if not w then return end
  for _, x in ipairs(V.units or {}) do
    local id = SYNC.uid(x)
    if id and x:IsValid() then
      local st = x.AC_jRPG_CharacterStats
      local hp, sh = st.CurrentHP, st.CurrentShieldPoints
      local l = w.last[id]
      if l and (math.abs((l[1] or 0) - (hp or 0)) >= 1 or l[2] ~= sh) then
        w.last[id] = { hp, sh }
        local k = (w.n[id] or 0) + 1; w.n[id] = k
        if w.mine then
          SYNC.after(0.1, function()
            if not x:IsValid() then return end
            local m = DEF.resultOf(x); m.uid, m.n, m.actor, m.hero = id, k, w.actor, true
            NET.msg("hitres", m)
          end)
        else
          DEF.watchApply(id, k)
        end
      end
    end
  end
end
function DEF.watchApply(id, k)
  local w = DEF.watch; if not w then return end
  local r = w.got[id] and w.got[id][k]
  if not r or r.applied or (w.applied[id] or 0) > k then return end
  local t = SYNC.unit(id); if not t then return end
  r.applied = true; w.applied[id] = k
  local what = DEF.writeResult(t, r)
  local st = t.AC_jRPG_CharacterStats
  w.last[id] = { st.CurrentHP, st.CurrentShieldPoints }   -- our own write is not a new hit
  if what ~= "" then dlog(("hero hit %s #%d result: %s (attacker's)"):format(id, k, what)) end
end

-- ---------- per frame on the attacker's PC: hold the flag for the next hit of each target ----------
function DEF.frame()
  if DEF.watch then DEF.watchFrame() end
  local a = DEF.act; if not (a and a.mine and a.monster) then return end
  for uid, list in pairs(a.res) do
    local k = (a.n[uid] or 0) + 1
    local def = list[k]
    if def and DEF.FLAG[def] then
      local t = SYNC.unit(uid)
      if t then
        local key = uid .. "#" .. k
        if not a.anim[key] then
          a.anim[key] = true    -- guard animation once per hit (may be refused by a lock: the held flag still counts)
          pcall(function() local o = {}; t[DEF.ANIM[def]](t, o) end)
        end
        pcall(function() t[DEF.FLAG[def]] = true end)
      end
    end
  end
end
