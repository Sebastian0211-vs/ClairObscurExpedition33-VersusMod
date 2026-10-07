-- E33 Versus online: the opponent's parries / dodges / jumps seen live on both PCs (requires sync.lua, versus.lua).
-- Monster attacks: the DEFENDER's PC is the truth. After every hit on one of its units it sends the outcome
-- {k="hit", uid, n (that unit's hit number in this action), def = parry|gparry|dodge|jump|nil}.
-- The attacker's PC starts the same attack a little later (SYNC.delay) so the outcome of hit n arrives before its own
-- hit n; until that hit lands it holds the matching flag on the target (IsParrying...), which the game reads at
-- impact (verified: holding IsParrying parries every hit), and plays the guard animation once.
-- Hit capture: post-hook on the target's stats ReceiveDamage (runs after the hit is evaluated, before HP drops,
-- with the Is* flags still those used for the hit). Hero hits do not go through it (hero attacks: phase B).
DEF = DEF or {}
local function dlog(s) V.log("DEF " .. s) end
DEF.FLAG = { parry = "IsParrying", gparry = "IsGradientParrying", dodge = "IsDodging", jump = "IsJumping" }
DEF.ANIM = { parry = "TryStartParry", gparry = "TryStartGradientParry", dodge = "TryStartDodge", jump = "TryStartJump" }

-- One action at a time: who acts, hit counters per target uid, outcomes received per target uid.
function DEF.begin(u)
  DEF.act = { actor = SYNC.uid(u), mine = SYNC.mine(u), monster = P.isEnemyClass(u), n = {}, res = {}, anim = {} }
end
function DEF.stop() DEF.act = nil end

-- Which defense a unit is in right now (flags read at the hit).
function DEF.kindOf(t)
  if t.IsGradientParrying then return "gparry" end
  if t.IsParrying then return "parry" end
  if t.IsDodging then return "dodge" end
  if t.IsJumping then return "jump" end
  return nil
end

-- ---------- hit hook (named function: hook closures survive hot reloads unchanged) ----------
function DEF.cbHit(ctx)
  local a = DEF.act; if not (a and a.monster and SYNC.active()) then return end
  local st = ctx:get(); local t = st and st:GetOwner()
  local uid = t and SYNC.uid(t); if not uid then return end
  local k = (a.n[uid] or 0) + 1; a.n[uid] = k
  if not a.mine and uid:sub(1, 1) == V.online.me then
    -- defender's PC: my unit was hit by the opponent's monster -> tell them how it went
    local def = DEF.kindOf(t)
    NET.msg("hit", { uid = uid, n = k, def = def, actor = a.actor })
    dlog(("-> hit %s #%d %s"):format(uid, k, tostring(def or "-")))
  elseif a.mine then
    -- attacker's PC: this hit is done; drop the flag we held for it
    local def = a.res[uid] and a.res[uid][k]
    if def and DEF.FLAG[def] then pcall(function() t[DEF.FLAG[def]] = false end) end
    dlog(("hit %s #%d here: %s (%s)"):format(uid, k, tostring(def or "-"), a.res[uid] and a.res[uid][k] ~= nil and "known" or "no outcome yet"))
  end
end
function DEF.install()
  if E33V_DEF_HOOK then return end
  local stats = "/Game/jRPGTemplate/Blueprints/Components/AC_jRPG_CharacterBattleStats.AC_jRPG_CharacterBattleStats_C:"
  E33V_DEF_HOOK = pcall(RegisterHook, stats .. "ReceiveDamage", function(ctx) return DEF.cbHit(ctx) end)
  dlog("hit hook: " .. tostring(E33V_DEF_HOOK))
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

-- ---------- per frame on the attacker's PC: hold the flag for the next hit of each target ----------
function DEF.frame()
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
