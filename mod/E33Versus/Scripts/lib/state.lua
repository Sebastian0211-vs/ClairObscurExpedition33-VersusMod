-- E33 Versus online: the fight state of a unit, as data (requires versus.lua, economy.lua, wheel.lua).
-- ST.snap(u) captures everything that decides a fight for one unit; ST.serialize/ST.hash give a canonical,
-- rounded fingerprint (float noise never counts); ST.diff names the fields that differ; ST.apply writes a snapshot
-- back with the game's own setters (verified in game 2026-10-08):
--   shield  stats:SetCurrentShieldPoints(n, reason)        break  stats:SetCurrentBreakBarDamage(n, srcStats, reason)
--   turn order  stats.CurrentInitiative = x                stats  V.setMaxHP / V.setStat
--   buffs   add = StaticConstructObject(class, stats) + stats:ActivateBuff(inst, 4 (Forced), srcStats, out)
--           remove = buffComp:RemoveBuffInstance(inst); stacks = inst:ChangeStackCount(n); turns = inst.TurnDuration
-- Buff "aggregators" (type 3, permanent helpers the game creates with some buffs) are not part of the state.
ST = ST or {}
local REASON = "E33Versus sync"

local function num(v) return type(v) == "number" and v or nil end
local function r1(v) return v and math.floor(v * 10 + 0.5) / 10 end
local function q(f) local ok, v = pcall(f); if ok then return v end end

-- Active buffs of a unit: { {cls = full class path, name = short name, stacks, turns, perm, inst} } sorted by name.
function ST.buffs(u)
  local out = {}
  pcall(function()
    local arr = u.AC_jRPG_CharacterStats.BattleBuffComponent.ActiveBattleBuffs
    for i = 1, #arr do
      local inst = arr[i].BattleBuffInstance
      if inst and inst:IsValid() then
        local cls = inst:GetClass()
        local name = cls:GetFName():ToString()
        local typ = q(function() return inst.Type end)
        if typ ~= 3 and not name:find("Aggregator", 1, true) then
          local o = {}; pcall(function() inst:GetStackCount(o) end)
          out[#out + 1] = { cls = cls:GetFullName():match("^%S+%s+(.+)$") or cls:GetFullName(), name = name,
            stacks = o.StackCount or 1, turns = q(function() return inst.TurnDuration end) or 0,
            perm = q(function() return inst.IsPermanent end) == true, inst = inst }
        end
      end
    end
  end)
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

function ST.snap(u)
  local st = u.AC_jRPG_CharacterStats
  local s = { stats = {} }
  st.CharacterCurrentStats:ForEach(function(k, v) s.stats[tostring(k:get())] = v:get() end)
  s.hp = st.CurrentHP
  s.shield = q(function() return st.CurrentShieldPoints end) or 0
  s.ap = E.ap[u:GetAddress()] or 0
  s.init = q(function() return st.CurrentInitiative end) or 0
  s.brk = tonumber(q(function() return st.StunBreakBarCurrent end)) or 0
  s.stun = q(function() return st.IsStun end) == true
  s.dead = q(function() return u["Dead?"] end) == true
  s.phase = num(q(function() return u.CurrentPhase end))
  s.buffs = {}
  for _, b in ipairs(ST.buffs(u)) do s.buffs[#s.buffs + 1] = { cls = b.cls, name = b.name, stacks = b.stacks, turns = b.turns } end
  return s
end

-- Canonical text (rounded): equal text = equal state. Order of stat keys and buffs is fixed.
function ST.serialize(s)
  local keys = {}; for k in pairs(s.stats or {}) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
  local st = {}; for _, k in ipairs(keys) do st[#st + 1] = k .. ":" .. r1(s.stats[k]) end
  local bf = {}; for _, b in ipairs(s.buffs or {}) do bf[#bf + 1] = ("%s:%d:%d"):format(b.name, b.stacks or 1, b.turns or 0) end
  return ("hp=%s|sh=%d|ap=%d|in=%s|br=%d|st=%s|dd=%s|ph=%s|s=%s|b=%s"):format(r1(s.hp), s.shield or 0, s.ap or 0,
    r1(s.init), s.brk or 0, tostring(s.stun), tostring(s.dead), tostring(s.phase), table.concat(st, ","), table.concat(bf, ","))
end
-- 32-bit FNV-1a of the canonical text, as hex (byte XOR without operators, so any Lua version parses it).
local function xor8(a, b)
  local r, bit = 0, 1
  for _ = 1, 8 do
    if (a % 2) ~= (b % 2) then r = r + bit end
    a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
  end
  return r
end
function ST.hash(s)
  local text = type(s) == "string" and s or ST.serialize(s)
  local h = 2166136261
  for i = 1, #text do
    local low = h % 256
    h = h - low + xor8(low, text:byte(i))
    -- h * 16777619 mod 2^32 with 16777619 = 2^24 + 403, split so every product stays exact in a double
    h = ((h % 256) * 16777216 + h * 403) % 4294967296
  end
  return ("%08x"):format(h)
end

-- Field-level differences "field here->truth" (empty table = identical).
function ST.diff(here, truth)
  local d = {}
  local function cmp(name, a, b) if tostring(a) ~= tostring(b) then d[#d + 1] = ("%s %s->%s"):format(name, tostring(a), tostring(b)) end end
  cmp("hp", r1(here.hp), r1(truth.hp)); cmp("shield", here.shield, truth.shield); cmp("ap", here.ap, truth.ap)
  cmp("init", r1(here.init), r1(truth.init)); cmp("break", here.brk, truth.brk); cmp("stun", here.stun, truth.stun)
  cmp("dead", here.dead, truth.dead); cmp("phase", here.phase, truth.phase)
  for k, v in pairs(truth.stats or {}) do cmp("stat" .. k, r1((here.stats or {})[k]), r1(v)) end
  local hb, tb = {}, {}
  for _, b in ipairs(here.buffs or {}) do hb[#hb + 1] = ("%s x%d %dt"):format(b.name, b.stacks or 1, b.turns or 0) end
  for _, b in ipairs(truth.buffs or {}) do tb[#tb + 1] = ("%s x%d %dt"):format(b.name, b.stacks or 1, b.turns or 0) end
  cmp("buffs", "[" .. table.concat(hb, ",") .. "]", "[" .. table.concat(tb, ",") .. "]")
  return d
end

local function buffClass(path)
  local c = StaticFindObject(path)
  if not (c and c:IsValid()) then
    pcall(function() LoadAsset((path:gsub("%.[^.]+$", ""))) end)
    c = StaticFindObject(path)
  end
  return c and c:IsValid() and c or nil
end

-- Write a snapshot onto a unit. src = a unit to name as the source of break damage / buffs (any valid unit).
function ST.apply(u, s, src)
  local st = u.AC_jRPG_CharacterStats
  local srcStats = (src and src:IsValid() and src.AC_jRPG_CharacterStats) or st
  for k, v in pairs(s.stats or {}) do
    local key = tonumber(k)
    if key == 1 then V.setMaxHP(u, v) elseif key then V.setStat(u, key, v) end
  end
  if s.hp then st.CurrentHP = s.hp end
  pcall(function() if (st.CurrentShieldPoints or 0) ~= (s.shield or 0) then st:SetCurrentShieldPoints(s.shield or 0, REASON) end end)
  pcall(function() if tonumber(st.StunBreakBarCurrent) ~= (s.brk or 0) then st:SetCurrentBreakBarDamage(s.brk or 0, srcStats, REASON) end end)
  if s.init then pcall(function() st.CurrentInitiative = s.init end) end
  if s.ap then E.ap[u:GetAddress()] = s.ap; if WH and WH.setAP then pcall(WH.setAP, u, s.ap) end end
  if s.phase and num(q(function() return u.CurrentPhase end)) and u.CurrentPhase ~= s.phase then pcall(function() u.CurrentPhase = s.phase end) end
  -- buffs: remove the ones the truth does not have, add missing ones, align stacks / turns
  local here = ST.buffs(u)
  local want = {}; for _, b in ipairs(s.buffs or {}) do want[b.name] = b end
  for _, b in ipairs(here) do
    local w = want[b.name]
    if not w then
      pcall(function() st.BattleBuffComponent:RemoveBuffInstance(b.inst) end)
    else
      if (w.stacks or 1) ~= b.stacks then pcall(function() b.inst:ChangeStackCount(w.stacks or 1) end) end
      if (w.turns or 0) ~= b.turns then pcall(function() b.inst.TurnDuration = w.turns or 0 end) end
      want[b.name] = nil
    end
  end
  for _, w in pairs(want) do
    local cls = buffClass(w.cls)
    if cls then
      pcall(function()
        E33V_BUFF_SEQ = (E33V_BUFF_SEQ or 0) + 1
        local inst = StaticConstructObject(cls, st, FName("E33V_SyncBuff_" .. E33V_BUFF_SEQ))
        inst.TurnDuration = w.turns or 1
        local o = {}; st:ActivateBuff(inst, 4, srcStats, o)   -- 4 = EBuffApplicationProbability "Forced"
        inst.TurnDuration = w.turns or 1                       -- activation adds a turn: set it again after
        if (w.stacks or 1) > 1 then inst:ChangeStackCount(w.stacks) end
      end)
    end
  end
end
