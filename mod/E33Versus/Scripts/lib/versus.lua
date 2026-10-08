-- E33 Versus core: teams, match setup and battle flow (local and online).
-- Requires unitlib.lua, uilib.lua, picker.lua (functions only) loaded first.
-- F6 opens the versus menu. Teams of up to 3 units each, any hero in the save or any DT_jRPG_Enemies row.
V = V or {}
V.LOGF = (E33V_DATA or "") .. (E33V_LOGNAME or "versus.log")
V.PLACEHOLDER_ENC = "CZ_ChromaMaelle"
V.cfg = V.cfg or { A = {}, B = {}, arena = 1 }
local function log(s) local f = io.open(V.LOGF, "a"); if f then f:write(os.date("%H:%M:%S") .. " VS " .. s .. "\n"); f:close() end end
V.log = log

-- ---------- roster ----------
V.HEROES = { { id = "Frey", label = "Gustave", name = "Gustave" }, { id = "Maelle", label = "Maelle", name = "Maelle" }, { id = "Lune", label = "Lune" },
  { id = "Sciel", label = "Sciel" }, { id = "Verso", label = "Verso" }, { id = "Monoco", label = "Monoco" } }
function V.availableHeroes()
  local cm = FindFirstOf("AC_jRPG_CharactersManager_C"); local out = {}
  for _, h in ipairs(V.HEROES) do
    local o = {}; pcall(function() cm:GetCharacterData(FName(h.id), o) end)
    -- On the title no save is loaded yet: offer every hero (checked against the save once it is loaded).
    local titleMode = SEL and SEL.mode == "title"
    if titleMode or (o.CharacterData and o.CharacterData:IsValid()) then out[#out + 1] = { kind = "hero", id = h.id, name = h.label, label = h.label } end
  end
  return out
end
-- Several roster rows share a display name (variants with other moves/stats): make every name unique once at load.
-- Archetype first when it tells them apart ("Gestral Bully (Elite)"), else a letter in row order ("Goblu B").
function V.dedupeNames()
  if not ROSTER or V._rosterDeduped == ROSTER then return end
  local groups = {}
  for row, d in pairs(ROSTER) do if type(d) == "table" and d.name then
    groups[d.name] = groups[d.name] or {}; table.insert(groups[d.name], row) end end
  for name, rows in pairs(groups) do
    if #rows > 1 then
      table.sort(rows)
      local archCount = {}
      for _, r in ipairs(rows) do local a = ROSTER[r].arch or "?"; archCount[a] = (archCount[a] or 0) + 1 end
      local letter = {}
      for _, r in ipairs(rows) do
        local d = ROSTER[r]; local a = d.arch or "?"
        if archCount[a] == 1 then d.name = name .. " (" .. a .. ")"
        else letter[a] = (letter[a] or 0) + 1; d.name = name .. " " .. string.char(64 + letter[a]) .. ((archCount[a] < #rows) and (" (" .. a .. ")") or "") end
      end
    end
  end
  V._rosterDeduped = ROSTER
end
pcall(V.dedupeNames)
V.CAP = 15
V.HERO_COST = 5  -- placeholder until hero levels/builds are normalized
function V.cost(u)
  if not u then return 0 end
  if u.custom then local d = CUSTOM and CUSTOM.def(u.custom); return d and d.cost or 5 end   -- custom characters: own cost
  return u.kind == "hero" and V.HERO_COST or ((ROSTER[u.row] or {}).cost or 5)
end
function V.teamCost(side, exceptSlot) local t = 0; for i = 1, 3 do if i ~= exceptSlot then t = t + V.cost(V.cfg[side][i]) end end; return t end
-- Phase entries: a boss row can be picked directly in a later phase as "<row>#P<n>" (costs more).
-- Disabled: starting directly in phase 2 froze the game (phase-2 behaviour needs the real transition setup).
V.PHASE_ENTRIES = {}
function V.addPhaseEntries()
  for _, e in ipairs(V.PHASE_ENTRIES) do
    local base = ROSTER[e.row]
    if base and not ROSTER[e.row .. "#P" .. e.phase] then
      local c = {}; for k, v in pairs(base) do c[k] = v end
      c.name = base.name .. " (Phase " .. e.phase .. ")"; c.cost = math.min(10, base.cost + e.extra); c.phase = e.phase
      ROSTER[e.row .. "#P" .. e.phase] = c
    end
  end
end
-- Bosses built from several actors the encounter places (the spawn only creates the core): not fair/playable yet.
V.EXCLUDE = { MF_Axon_Visages = "masks are separate actors (attacks unreadable)" }
function V.enemyRows(filter)
  local out = {}
  for row, d in pairs(ROSTER) do
    if not d.dup and not V.EXCLUDE[row] and (not filter or filter(row, d)) then
      out[#out + 1] = { kind = "enemy", row = row, name = d.name, cost = d.cost, label = ("[%d] %s  (%s)"):format(d.cost, d.name, row) }
    end
  end
  table.sort(out, function(x, y) if x.cost ~= y.cost then return x.cost > y.cost end; return x.label < y.label end)
  return out
end
V.CATEGORIES = {
  { label = "Heroes", list = function() local h = V.availableHeroes(); for _, x in ipairs(h) do x.label = ("[%d] %s"):format(V.HERO_COST, x.label) end; return h end },
  { label = "Custom", list = function() return CUSTOM and CUSTOM.list() or {} end },   -- imported models (Custom/<id>/)
  { label = "Chroma heroes", list = function() return V.enemyRows(function(r) return r:find("^CZ_Chroma") end) end },
  { label = "Bosses", list = function() return V.enemyRows(function(r, d) return d.boss end) end },
  { label = "Elites & Alphas", list = function() return V.enemyRows(function(r, d) return d.arch == "Elite" or d.arch == "Alpha" end) end },
  { label = "All units (by cost)", list = function() return V.enemyRows() end },
}

-- ---------- menus ----------
local function unitLabel(u) if not u then return "(empty)" end; return ("[%d] %s"):format(V.cost(u), u.name or u.label) end
function V.menuMain()
  V.addPhaseEntries()
  local items, acts = {}, {}
  local function add(label, fn) items[#items + 1] = label; acts[#acts + 1] = fn end
  for _, side in ipairs({ "A", "B" }) do
    for i = 1, 3 do
      add(("Team %s - slot %d: %s"):format(side == "A" and "1" or "2", i, unitLabel(V.cfg[side][i])), function() V.menuCategory(side, i) end)
    end
  end
  add("Arena: #" .. V.cfg.arena, function() V.cfg.arena = V.cfg.arena % #FindAllOf("BP_BattleMap_C") + 1; V.menuMain() end)
  V.cfg.level = V.cfg.level or V.avgHeroLevel()
  add("Versus level: " .. V.cfg.level, function() V.cfg.level = V.cfg.level % 100 + 10; V.menuMain() end)
  add(">> START <<", function() UI.close(); V.start() end)
  add("Close", function() UI.close() end)
  UI.close(); UI.make(("E33 VERSUS - setup     Team 1: %d/%d pts     Team 2: %d/%d pts"):format(V.teamCost("A"), V.CAP, V.teamCost("B"), V.CAP), items)
  UI.onPick = function(i) acts[i]() end
  UI.onBack = function() UI.close() end
end
function V.menuCategory(side, slot)
  local labels = {}
  for i, c in ipairs(V.CATEGORIES) do labels[i] = c.label end
  labels[#labels + 1] = "(empty this slot)"
  UI.close(); UI.make(("Team %s slot %d - category"):format(side == "A" and "1" or "2", slot), labels)
  UI.onPick = function(i)
    if i > #V.CATEGORIES then V.cfg[side][slot] = nil; V.menuMain(); return end
    V.menuList(side, slot, V.CATEGORIES[i].list(), 1)
  end
  UI.onBack = V.menuMain
end
V.PAGE = 12
function V.menuList(side, slot, list, page)
  local pages = math.max(1, math.ceil(#list / V.PAGE))
  local first = (page - 1) * V.PAGE
  local labels, map = {}, {}
  for i = first + 1, math.min(first + V.PAGE, #list) do labels[#labels + 1] = list[i].label; map[#labels] = list[i] end
  if page < pages then labels[#labels + 1] = "-- next page --"; map[#labels] = "next" end
  if page > 1 then labels[#labels + 1] = "-- previous page --"; map[#labels] = "prev" end
  if #list == 0 then labels[1] = "(nothing available)"; map[1] = "none" end
  UI.close(); UI.make(("Pick unit (page %d/%d)  -  %d pts left"):format(page, pages, V.CAP - V.teamCost(side, slot)), labels)
  UI.onPick = function(i)
    local m = map[i]
    if m == "next" then V.menuList(side, slot, list, page + 1)
    elseif m == "prev" then V.menuList(side, slot, list, page - 1)
    elseif m == "none" then V.menuCategory(side, slot)
    elseif V.teamCost(side, slot) + V.cost(m) > V.CAP then
      V.log(("over cap: %s costs %d, team has %d/%d"):format(m.name or m.label, V.cost(m), V.teamCost(side, slot), V.CAP))
      UI.title:SetText(FText(("Too expensive: %d pts left for this slot"):format(V.CAP - V.teamCost(side, slot))))
    else V.cfg[side][slot] = m; V.menuMain() end
  end
  UI.onBack = function() V.menuCategory(side, slot) end
end

-- ---------- balance ----------
-- Enemy-class units get a hero-scale HP pool that grows with cost: refHP * (HP_BASE + HP_PER_COST * cost).
V.HP_BASE, V.HP_PER_COST = 0.6, 0.2
function V.maxHP(c) local o = {}; c.AC_jRPG_CharacterStats:GetMaxHP(o); return o.MaxHP or 0 end
-- Set max HP in place: HP is stat type 1 in CharacterBaseStats/CharacterCurrentStats (element :set, no map writes).
function V.setMaxHP(c, hp)
  local st = c.AC_jRPG_CharacterStats
  for _, m in ipairs({ st.CharacterBaseStats, st.CharacterCurrentStats }) do
    m:ForEach(function(k, v) if k:get() == 1 then v:set(hp) end end)
  end
  st.CurrentHP = hp
  return V.maxHP(c)
end
-- Versus level cap for heroes: scale the BATTLE copy of growth stats (value > 1) by cap/level.
-- (CharacterData:SetLevel would change saved data, attribute points, skill graph and notify the game instance.)
-- Stat keys (E_jRPG_StatType values, confirmed 21:44 against table values): 1 HP, 2 AP, 3 Attack, 8 Speed, 9 Crit.
V.STAT_ATK = 3
V.ATK_BASE, V.ATK_PER_COST = 0.8, 0.05
function V.getStat(c, key)
  local r; c.AC_jRPG_CharacterStats.CharacterCurrentStats:ForEach(function(k, v) if k:get() == key then r = v:get() end end); return r
end
function V.setStat(c, key, val)
  local st = c.AC_jRPG_CharacterStats
  for _, m in ipairs({ st.CharacterBaseStats, st.CharacterCurrentStats }) do
    m:ForEach(function(k, v) if k:get() == key then v:set(val) end end)
  end
end
function V.statMap(c)
  local t = {}
  c.AC_jRPG_CharacterStats.CharacterCurrentStats:ForEach(function(k, v) t[#t + 1] = k:get() .. "=" .. string.format("%.2f", v:get()) end)
  return table.concat(t, " ")
end
function V.capHero(actor, id)
  local cm = FindFirstOf("AC_jRPG_CharactersManager_C"); local o = {}
  cm:GetCharacterData(FName(id), o)
  local lvl = o.CharacterData and o.CharacterData.CurrentLevel or V.cfg.level
  log(("hero %s lv%d stats: %s"):format(id, lvl, V.statMap(actor)))
  if lvl <= V.cfg.level then return lvl end
  local k = V.cfg.level / lvl
  local st = actor.AC_jRPG_CharacterStats
  for _, m in ipairs({ st.CharacterBaseStats, st.CharacterCurrentStats }) do
    m:ForEach(function(key, v) local x = v:get(); if x > 1 then v:set(x * k) end end)
  end
  st.CurrentHP = V.maxHP(actor)
  log(("hero %s capped lv%d -> lv%d (x%.2f): HP %.0f"):format(id, lvl, V.cfg.level, k, st.CurrentHP))
  return lvl
end
function V.naturalHP(row, level)
  local d = ROSTER[row]; if not d or not ARCH_HP[d.arch] then return nil end
  return ARCH_HP[d.arch][math.max(1, math.min(100, level))] * (d.hpScale or 1)
end
function V.avgHeroLevel()
  local cm = FindFirstOf("AC_jRPG_CharactersManager_C"); local sum, n = 0, 0
  for _, h in ipairs(V.HEROES) do local o = {}; pcall(function() cm:GetCharacterData(FName(h.id), o) end)
    if o.CharacterData and o.CharacterData:IsValid() then sum = sum + o.CharacterData.CurrentLevel; n = n + 1 end end
  return n > 0 and math.floor(sum / n + 0.5) or 20
end

-- Enemy rows are not in DT_jRPG_CharacterDefinitions, so the HUD portrait falls back to a hero image.
-- Put the enemy's own turn-order portrait (DT_jRPG_Enemies PortraitData.TimelinePortrait) into the widget.
function V.setPortrait(widget, path)
  if not (widget and widget:IsValid() and path and path ~= "") then return end
  local name = path:match("([^/]+)$")
  local tex = StaticFindObject(path .. "." .. name)
  if not tex or not tex:IsValid() then LoadAsset(path); tex = StaticFindObject(path .. "." .. name) end
  if not tex or not tex:IsValid() then return end
  widget.Character_Portrait_Selected:SetBrushFromTexture(tex, false)
  widget.Character_Portrait_Damaged:SetBrushFromTexture(tex, false)
end

-- ---------- battle ----------
-- Destroy units this mod spawned in earlier versus battles that are no longer in the current battle.
-- (Only our own: the game keeps other battle actors around on purpose.)
V.spawned = V.spawned or {}
function V.cleanupStrays()
  local bm = U.bm(); local keep = {}
  for _, arr in ipairs({ bm.PlayerCharacters, bm.Enemies }) do for i = 1, #arr do keep[arr[i]:GetAddress()] = true end end
  local n, still = 0, {}
  for _, c in ipairs(V.spawned) do
    if c:IsValid() then
      -- Hidden and parked, never destroyed: K2_DestroyActor on the last match's units crashed every same-world
      -- rematch (11:19/11:27/11:30 tests; the game still references them after the end flow).
      if keep[c:GetAddress()] then still[#still + 1] = c
      else
        pcall(function() c:SetActorHiddenInGame(true); c:SetActorEnableCollision(false)
          c:K2_SetActorLocation({ X = 0, Y = 0, Z = -100000 }, false, {}, true) end)
        V.parked = V.parked or {}; V.parked[#V.parked + 1] = c; n = n + 1
      end
    end
  end
  V.spawned = still
  return n
end
function V.noAutoSave()
  local sm = FindFirstOf("BP_SaveManager_C")
  if sm and sm:IsValid() then sm.EnableAutoSave = false; return true end
  return false
end
function V.start()
  if not (V.cfg.A[1] or V.cfg.A[2] or V.cfg.A[3]) or not (V.cfg.B[1] or V.cfg.B[2] or V.cfg.B[3]) then
    log("need at least one unit per team"); V.menuMain(); return
  end
  log("autosave off: " .. tostring(V.noAutoSave()) .. ", strays removed: " .. V.cleanupStrays())
  E33V_ENC, E33V_MAP, E33V_LEVEL_OFFSET = V.PLACEHOLDER_ENC, V.cfg.arena, 0
  V.resetMatch()
  V.matchesHere = (V.matchesHere or 0) + 1
  -- Heroes kicked or killed in the previous match keep 0 HP in the party data: the next placeholder battle would
  -- start with a dead party -> "all heroes killed" -> crash during our setup (11:27 rematch test). Autosave is off.
  local cm = FindFirstOf("AC_jRPG_CharactersManager_C")
  V.spawnAt, V.spawnWarned = os.clock(), nil
  log("party healed: " .. tostring(cm and cm:IsValid() and pcall(function() cm:FullHealAllCharacters() end)))
  V.spawnPending = true
  -- custom characters: parse their meshes, load the material and import the textures NOW, before the battle starts
  -- streaming (setup then only builds components)
  if CUSTOM then pcall(CUSTOM.preload, V.cfg) end
  V.trigger()
end
-- Forget the previous match: a rematch in the same world otherwise ran the end check on the old (destroyed) units
-- at the placeholder battle's first turn -> forced CheckBattleEnd -> instant defeat -> crash (11:19 test).
function V.resetMatch()
  V.units, V.sideOf, V.uidOf, V.rowOf, V.customOf = {}, {}, {}, {}, {}
  if CUSTOM then CUSTOM.forgetMatch() end
  V.ended, V.turnSeen, V.lastSig, V.endWatch, V.heroSide, V.frameErr = nil, nil, nil, nil, nil, nil
  V.lastSnap, V.lastActor, V.lastSide, V.queuedDeathUnits = nil, nil, nil, nil
  V.counterUnits = {}
  if PH then PH.dead, PH.armed = {}, {} end
end
-- Setup order (never leave a side empty, or the game's CheckBattleEnd fires):
--  1. enemy-class units of both teams, each HP-normalized via probe spawn (placeholders still present);
--  2. enemy placeholders kicked (team 2 now has its enemy-class units, or keeps one placeholder until a hero arrives);
--  3. heroes swapped in one at a time: kick one placeholder hero, spawn one chosen hero (party cap is 3);
--  4. remaining placeholders kicked.
function V.heroId(c)
  local ok, v = pcall(function() return c.AC_jRPG_CharacterStats.CharacterHardcodedName:ToString() end)
  return ok and v or nil
end
-- Remove and return the first placeholder hero whose id passes test(id).
function V.takePlaceholder(list, test)
  for i, ph in ipairs(list) do
    if ph and ph:IsValid() and test(V.heroId(ph)) then return table.remove(list, i) end
  end
end
function V.setup()
  V.hookTurns()
  local bm = U.bm()
  V.noAutoSave()
  bm.FleeImpossible = true            -- no fleeing out of a versus match (the game greys out Flee)
  bm.HasSentReserveTeam = true
  bm.CurrentBattleEncounterLevel = V.cfg.level
  E33V_CONTROLLED, E33V_SWITCHED, E33V_TARGET_FOR = {}, {}, {}
  V.units, V.sideOf = {}, {}
  V.lastSnap, V.lastActor, V.ended, V.turnSeen, V.blockerRearms = nil, nil, nil, nil, 0
  E.reset()
  if WH then WH.resetItems() end
  local phHeroes, phEnemies = {}, {}
  for i = 1, #bm.PlayerCharacters do phHeroes[#phHeroes + 1] = bm.PlayerCharacters[i] end
  for i = 1, #bm.Enemies do phEnemies[#phEnemies + 1] = bm.Enemies[i] end
  -- End of match: a unit killed DURING a skill has its death queued until turn end (stats.bIsDeathQueuedForTurnEnd).
  -- V.frameCheck sees the wiped side in that window (from the ticker, which runs even during cinematic attacks),
  -- re-labels from our side and ends the battle before the game's queued death runs CheckBattleEnd.
  -- (Tried and dropped: a PendingResurrects blocker looped "revient a la vie"; a dead stand-in in both arrays froze turns.)
  local sum, n = 0, 0
  for _, h in ipairs(phHeroes) do local v = V.maxHP(h); if v > 0 then sum = sum + v; n = n + 1 end end
  V.refHP = (n > 0 and sum / n or 1000) * math.min(1, V.cfg.level / math.max(1, V.avgHeroLevel()))
  local asum, an = 0, 0
  for _, h in ipairs(phHeroes) do local a = V.getStat(h, V.STAT_ATK); if a and a > 0 then asum = asum + a; an = an + 1 end end
  V.refAtk = (an > 0 and asum / an or 1800) * math.min(1, V.cfg.level / math.max(1, V.avgHeroLevel()))
  log(("reference hero HP %.0f, attack %.0f (%d heroes), level %d"):format(V.refHP, V.refAtk, n, V.cfg.level))

  local function register(actor, side, u, msg)
    local addr = actor:GetAddress()
    V.sideOf[addr] = side
    V.rowOf = V.rowOf or {}; V.rowOf[addr] = u.row
    V.customOf = V.customOf or {}; V.customOf[addr] = u.custom
    -- same unit id on both PCs for online sync: side .. team slot
    V.uidOf = V.uidOf or {}
    for k = 1, 3 do if V.cfg[side][k] == u then V.uidOf[addr] = side .. k end end
    if u.kind == "enemy" then E33V_CONTROLLED[addr] = true end
    -- team-1 portraits are all (re)built by V.rebuildHUD at the end of setup
    if side == "B" and u.kind == "hero" then
      -- Spawned through the party path, so it was added to team 1's portrait row: move it to an overhead bar.
      local ok, err = pcall(function()
        local st = actor.AC_jRPG_CharacterStats
        local w = bm.BattleScreenWidget
        w.WBP_HUD_DisplayCharacterPortraits:RemoveCharacter(st)
        local o = {}; w:GetNextAvailableBossUI(st, o)
        local ui = o.BossUI
        if ui and ui:IsValid() then ui:SetCharacterBattleStats(st); ui:SetVisibility(4); pcall(function() ui:Appear() end); actor.BossUI = ui end
      end)
      if not ok then log("team 2 hero HUD: " .. tostring(err)) end
    end
    V.units[#V.units + 1] = actor; V.spawned[#V.spawned + 1] = actor
    log("spawned " .. msg)
    if CUSTOM then
      pcall(CUSTOM.autoDump, actor, u)   -- every unit's skeleton becomes usable as a base for tools/charforge
      if u.custom then
        local okC, errC = pcall(CUSTOM.apply, actor, u.custom)
        if not okC then log("custom look " .. tostring(u.custom) .. " FAILED: " .. tostring(errC)) end
      end
    end
  end
  local spotOf = { 0, 1, 2 }  -- slot -> visible spot

  -- 1. enemy-class units, HP-normalized
  for _, side in ipairs({ "B", "A" }) do
    for slot = 1, 3 do
      local u = V.cfg[side][slot]
      if u and u.kind == "enemy" then
        local ok, err = pcall(function()
          local target = V.refHP * (V.HP_BASE + V.HP_PER_COST * V.cost(u))
          local actor, msg = U.spawn(u.row:gsub("#P%d+$", ""), side == "A", spotOf[slot])
          pcall(V.fitSize, actor)
          local phase = tonumber(u.row:match("#P(%d+)$"))
          if phase then PH.startInPhase(actor, phase) end
          local natural = V.maxHP(actor)
          local final = V.setMaxHP(actor, target)
          log(("HP %s: natural %.0f -> target %.0f, now %.0f"):format(u.name or u.row, natural, target, final))
          local atk0 = V.getStat(actor, V.STAT_ATK) or 0
          local atk = V.refAtk * (V.ATK_BASE + V.ATK_PER_COST * V.cost(u))
          if atk0 > 0 then V.setStat(actor, V.STAT_ATK, atk) end
          log(("ATK %s: natural %.0f -> %.0f"):format(u.name or u.row, atk0, V.getStat(actor, V.STAT_ATK) or -1))
          local d = ROSTER[u.row:gsub("#P%d+$", "")] or {}
          log(("stats %s: %s | table@50 atk=%s spd=%s"):format(u.name or u.row, V.statMap(actor), tostring(d.atk), tostring(d.spd)))
          register(actor, side, u, msg)
        end)
        bm.Challenge_EnemyHealthMultiplier = 0
        if not ok then log("spawn failed " .. unitLabel(u) .. ": " .. tostring(err)) end
      end
    end
  end
  -- 2. enemy placeholders (keep one if team 2 has no enemy-class unit yet)
  local teamBHasUnit = false
  for addr, side in pairs(V.sideOf) do if side == "B" then teamBHasUnit = true end end
  for i, ph in ipairs(phEnemies) do if teamBHasUnit or i > 1 then pcall(U.kick, ph); phEnemies[i] = false end end
  -- 3. heroes, one swap at a time
  local chosen = {}
  for _, sd in ipairs({ "A", "B" }) do for k = 1, 3 do local c = V.cfg[sd][k]; if c and c.kind == "hero" then chosen[c.id] = true end end end
  for _, side in ipairs({ "A", "B" }) do
    for slot = 1, 3 do
      local u = V.cfg[side][slot]
      if u and u.kind == "hero" then
        -- The placeholders are the save's party. Reuse one that already IS this hero (respawning a hero right
        -- after kicking it fails), otherwise kick a placeholder nobody picked, then spawn.
        local same = V.takePlaceholder(phHeroes, function(id) return id == u.id end)
        local ok, actor, msg
        if same then
          ok, actor, msg = pcall(function() return same, U.setSide(same, side == "A", spotOf[slot]) end)
        else
          local ph = V.takePlaceholder(phHeroes, function(id) return not chosen[id] end) or table.remove(phHeroes)
          if ph then pcall(U.kick, ph) end
          ok, actor, msg = pcall(U.spawnHero, u.id, side == "A", spotOf[slot])
        end
        if ok then pcall(V.capHero, actor, u.id); register(actor, side, u, msg) else log("spawn failed " .. unitLabel(u) .. ": " .. tostring(actor)) end
      end
    end
  end
  -- 4. leftovers
  for _, ph in ipairs(phHeroes) do pcall(U.kick, ph) end
  for _, ph in ipairs(phEnemies) do if ph then pcall(U.kick, ph) end end
  log(("setup done: players=%d enemies=%d, strays removed: %d"):format(#bm.PlayerCharacters, #bm.Enemies, V.cleanupStrays()))
  if MU then pcall(MU.start) end
  if SYNC and SYNC.active() then pcall(SYNC.sendStats); pcall(SYNC.applyStats) end   -- same stats on both PCs
  pcall(V.preloadStart)
  local okH, errH = pcall(V.rebuildHUD); if not okH then log("HUD rebuild: " .. tostring(errH)) end
  bm.FleeImpossible = true   -- no "Fuir" in versus
end

-- Attack sequences of every unit (lib/preload_data.lua, from the game's file list), loaded a few per frame right after
-- setup: an enemy move loads its sequence on first use, which started that move late on one PC (late parry outcomes
-- in the server logs). Loaded objects may be collected again later; the disk cache stays warm.
V.PRELOAD_PER_FRAME = 2
function V.preloadStart()
  local q, seen = {}, {}
  for _, u in ipairs(V.units or {}) do
    local row = V.rowOf and V.rowOf[u:GetAddress()]
    row = row and tostring(row):gsub("#.*$", "")
    -- once per game session per sequence: loading one again after a level reload (it may be half unloaded) crashed
    -- inside the engine (rematch 2026-10-08 11:33); one already in memory is skipped too
    for _, p in ipairs((PRELOAD_DATA or {})[row or ""] or {}) do
      if not seen[p] and not (E33V_PRELOADED and E33V_PRELOADED[p]) then
        seen[p] = true
        local ok, o = pcall(StaticFindObject, p)
        if not (ok and o and o:IsValid()) then q[#q + 1] = p end
      end
    end
  end
  V.preloadQ, V.preloadN, V.preloadAt = q, 0, os.clock()
  if #q > 0 then log(("preload: %d sequences"):format(#q)) end
end
function V.preloadFrame()
  local q = V.preloadQ; if not q then return end
  for _ = 1, V.PRELOAD_PER_FRAME do
    local p = table.remove(q, 1); if not p then break end
    E33V_PRELOADED = E33V_PRELOADED or {}; E33V_PRELOADED[p] = true
    local ok, obj = pcall(LoadAsset, p)
    if ok and obj then V.preloadN = V.preloadN + 1 end
  end
  if #q == 0 then log(("preload done: %d loaded in %.2f s"):format(V.preloadN, os.clock() - V.preloadAt)); V.preloadQ = nil end
end

-- Counter watchdog: a full parry makes the defender counter. Enemy-class defenders have no counter attack, so the
-- battle would wait forever (HasActiveCounterAttack). Moves reset CanBeCountered themselves (in the same call as the
-- parry check: clearing it per frame or in hooks did not stop it, tested 2026-10-08), so we end it instead, on the first
-- frame: during the old 0.6 s grace the game played its counter camera and prompt on a unit that has no counter (#11).
V.COUNTER_GRACE = 0
-- Units seen countering (address -> clock). The counter's OnTurnStart can come AFTER we ended a monster's counter
-- (flag already cleared): V.isCounterTurn still recognises it for V.COUNTER_WINDOW seconds, once. Monsters only.
V.counterUnits = V.counterUnits or {}
V.COUNTER_WINDOW = 6.0   -- measured 1-3 s between our skip and the counter's turn start
function V.counterWatch()
  local bm = U.bm()
  if not (bm and bm:IsValid() and bm.HasActiveCounterAttack) then V.counterSince = nil; return end
  local stuck = {}
  for i = 1, #bm.CurrentlyCounteringCharacters do
    local st = bm.CurrentlyCounteringCharacters[i]
    local ok, owner = pcall(function() return st:GetOwner() end)
    if ok and owner and owner:IsValid() and P.isEnemyClass(owner) then stuck[#stuck + 1] = owner:GetAddress() end
  end
  if #stuck == 0 then stuck = nil end
  if not stuck then V.counterSince = nil; return end
  local now = os.clock()
  V.counterSince = V.counterSince or now
  if now - V.counterSince >= V.COUNTER_GRACE then
    V.counterSince = nil
    log("counter skipped (enemy-class defender has no counter)")
    -- only these: their counter's turn start comes later (V.isCounterTurn). A HERO counters during the attacker's
    -- action, so its next turn start is a real turn (skipping it froze match 2026-10-08 11:53).
    for _, a in ipairs(stuck) do V.counterUnits[a] = os.clock() end
    bm:OnCounterAttackFinished()
  end
end

-- Versus win check: if a side has no units left, restore the canonical labelling (team 1 = heroes) and let the
-- game's CheckBattleEnd run (empty Enemies -> victory, empty PlayerCharacters -> defeat).
-- Enemy-class attacks run no skill script, so a victim's death is processed IMMEDIATELY inside the damage call
-- (stats.OnKilledByDamage) -> CheckBattleEnd under the attacker's flipped labels -> DEFEAT. A victim whose own
-- CurrentBattleSkill is valid gets its death QUEUED to turn end instead (that's the hero-attack path). So at the start
-- of an enemy-class action we give its targets a placeholder skill (the skill-script class default object); V.frameCheck
-- then sees the wipe in that window and ends the battle from our side. Cleared at the next turn start.
V.SKILL_CDO_PATH = "/Game/Gameplay/Battle/Skills/BP_Battle_SkillScript.Default__BP_Battle_SkillScript_C"
function V.skillPlaceholder()
  if V._skillCDO and V._skillCDO:IsValid() then return V._skillCDO end
  local o = StaticFindObject(V.SKILL_CDO_PATH)
  if not (o and o:IsValid()) then pcall(LoadAsset, "/Game/Gameplay/Battle/Skills/BP_Battle_SkillScript.BP_Battle_SkillScript"); o = StaticFindObject(V.SKILL_CDO_PATH) end
  V._skillCDO = (o and o:IsValid()) and o or nil
  return V._skillCDO
end
function V.cbActionStart(ctx)
  local c = ctx:get()
  if not (c and c:IsValid() and V.sideOf and V.sideOf[c:GetAddress()] and P.isEnemyClass(c)) or V.ended then return end
  local ph = V.skillPlaceholder(); if not ph then return end
  local mine = V.sideOf[c:GetAddress()]
  V.queuedDeathUnits = {}
  for _, u in ipairs(V.units or {}) do
    if u:IsValid() and V.sideOf[u:GetAddress()] ~= mine and not u.CurrentBattleSkill:IsValid() then
      u.CurrentBattleSkill = ph; V.queuedDeathUnits[#V.queuedDeathUnits + 1] = u
    end
  end
end
function V.clearSkillPlaceholders()
  local ph = V._skillCDO
  for _, u in ipairs(V.queuedDeathUnits or {}) do
    pcall(function() if u:IsValid() and ph and u.CurrentBattleSkill:IsValid() and u.CurrentBattleSkill:GetAddress() == ph:GetAddress() then u.CurrentBattleSkill = nil end end)
  end
  V.queuedDeathUnits = nil
end
function V.hookActionStart()
  if E33V_ACTSTART then return end
  E33V_ACTSTART = pcall(RegisterHook, "/Game/jRPGTemplate/Blueprints/Basics/BP_jRPG_Character_Battle_Base.BP_jRPG_Character_Battle_Base_C:Acquire Targets", function(ctx) return V.cbActionStart(ctx) end)
  log("action-start hook: " .. tostring(E33V_ACTSTART))
end
-- Per-frame end-of-match check (from TICK.frame and V.tick); only once the battle is really running
-- (a freshly spawned hero can read 0 HP for a moment).
function V.frameCheck()
  if V.spawnPending or not (V.turnSeen and V.sideOf and next(V.sideOf) and not V.ended) then return end
  -- research: log every change of the per-side living counts (with HP) to see what the game shows mid-attack
  local sig, parts = "", {}
  for _, u in ipairs(V.units or {}) do
    if u:IsValid() then
      if PH then pcall(PH.watch, u) end
      local hp = u.AC_jRPG_CharacterStats.CurrentHP
      local dead = false; pcall(function() dead = u["Dead?"] == true end)
      local q = false; pcall(function() q = u.AC_jRPG_CharacterStats.bIsDeathQueuedForTurnEnd == true end)
      parts[#parts + 1] = ("%s:%.0f%s%s"):format(V.sideOf[u:GetAddress()] or "?", hp, dead and "D" or "", q and "Q" or "")
    end
  end
  sig = table.concat(parts, " ")
  if sig ~= V.lastSig then V.lastSig = sig; log("FRAME " .. sig) end
  local ok, err = pcall(V.checkSides, true)
  if not ok and not V.frameErr then V.frameErr = true; log("frameCheck error: " .. tostring(err)) end
end
-- forceEnd: also call the game's CheckBattleEnd (turn-start fallback). The per-frame watcher only re-labels, so the
-- game's own end check at action finish plays the right scene without cutting the killing animation.
function V.checkSides(forceEnd, dyingAddr)
  -- Count our own unit list (the game's PlayerCharacters/Enemies arrays can drop or keep dead units).
  -- dyingAddr: a unit that is being killed right now (kill hook) counts as dead.
  local bm = U.bm(); local alive = { A = 0, B = 0 }; local living = {}
  for _, u in ipairs(V.units or {}) do
    if u:IsValid() then
      local a = u:GetAddress()
      local s = V.sideOf[a]
      local dead = a == dyingAddr or (PH and PH.dead[a]) or false; pcall(function() dead = dead or u["Dead?"] == true end)
      local hp = 0; pcall(function() hp = u.AC_jRPG_CharacterStats.CurrentHP end)
      if s and not dead and type(hp) == "number" and hp > 0 then alive[s] = alive[s] + 1; living[#living + 1] = u end
    end
  end
  if alive.A > 0 and alive.B > 0 then return false end
  if V.ended then
    if forceEnd then bm.PendingResurrects:Empty(); local o = {}; bm:CheckBattleEnd(o) end
    return true
  end
  V.ended = true
  if MU then pcall(MU.stop, 2.0) end
  if AI then pcall(AI.unblock) end
  if V.online and ONLINE then pcall(ONLINE.uploadLog, "match-end") end   -- server owner gets both players' logs
  -- the owner of the last action tells the other PC the final state (its deaths end the match there too), and
  -- whichever PC gets here first tells the other the winner (SYNC.onEnd ends it the same way there)
  if SYNC and V.online and V.online.inMatch and (V.online.truthSide or "A") == V.online.me then
    pcall(SYNC.sendSnap, V.online.turnN, nil, true)
  end
  if SYNC and SYNC.sendEnd then pcall(SYNC.sendEnd, alive.A > 0 and "A" or "B", "sides") end
  -- Final labels from THIS screen's point of view, LIVING units only: the game's CheckBattleEnd says DEFEAT when
  -- PlayerCharacters is empty and VICTORY when Enemies is empty. My side = the "heroes" (local: team 1; online: own side).
  local mySide = (V.online and V.online.me) or "A"
  bm.PlayerCharacters:Empty(); bm.Enemies:Empty()
  for _, u in ipairs(living) do
    if V.sideOf[u:GetAddress()] == mySide then u["Enemy?"] = false; bm.PlayerCharacters[#bm.PlayerCharacters + 1] = u
    else u["Enemy?"] = true; bm.Enemies[#bm.Enemies + 1] = u end
  end
  V.heroSide = mySide
  if SYNC and SYNC.unblockInput then pcall(SYNC.unblockInput) end
  -- online: the finishing action has no "next turn": send it (and the final HP) now so the other PC can finish too
  if SYNC and SYNC.active and SYNC.active() then pcall(SYNC.flushMyHero, SYNC.lastUnit); pcall(SYNC.sendState) end
  log(("versus over: team 1 alive %d, team 2 alive %d -> %s (shown from side %s)"):format(alive.A, alive.B, alive.A > 0 and "TEAM 1 WINS" or "TEAM 2 WINS", mySide))
  -- Kicked/killed units can leave entries in PendingResurrects, which blocks CheckBattleEnd forever.
  bm.PendingResurrects:Empty()
  if forceEnd then
    local o = {}; bm:CheckBattleEnd(o)
    log(("end check: players=%d enemies=%d -> ended=%s state=%s cur=%s"):format(#bm.PlayerCharacters, #bm.Enemies,
      tostring(o.BattleHasEnded), tostring(bm.BattleEndState), tostring(bm.CurrentCharacter and bm.CurrentCharacter:IsValid() and bm.CurrentCharacter:GetFName():ToString())))
  end
  V.endWatch = os.clock()
  return true
end
-- research: which end flow the game really runs after our end check
function V.cbEndFlow(name)
  log("END FLOW " .. name .. " state=" .. tostring(U.bm() and U.bm().BattleEndState))
  -- The game ended the match by itself (not through V.checkSides: server log 2026-10-07, one PC only). Online: tell the
  -- other PC the result this screen shows, so both end the same way.
  if V.online and V.online.inMatch and not V.ended and SYNC and SYNC.sendEnd then
    local me = V.online.me
    local other = me == "A" and "B" or "A"
    if name:find("^OnAllHeroesKilled") then V.ended = true; pcall(SYNC.sendEnd, other, "game: all heroes killed")
    elseif name:find("^OnAllEnemiesKilledInternal") then V.ended = true; pcall(SYNC.sendEnd, me, "game: all enemies killed") end
  end
end
function V.hookEndFlows()
  if E33V_ENDHOOKS then return end
  E33V_ENDHOOKS = true
  local BM = "/Game/jRPGTemplate/Blueprints/Components/AC_jRPG_BattleManager.AC_jRPG_BattleManager_C:"
  for _, fn in ipairs({ "OnAllHeroesKilled", "OnBattleEndVictory", "OnAllEnemiesKilledInternal", "StartBattleEndFlow", "ProcessVictoryEndFlow", "PerformFlee" }) do
    pcall(RegisterHook, BM .. fn, function(ctx, a) return V.cbEndFlow(fn .. (a and (" arg=" .. tostring(pcall(function() return a:get() end) and a:get())) or "")) end)
  end
end
-- The game's kill handlers end with CheckBattleEnd. Our hook runs before their body: if this death wipes a side, set
-- the final labels now so the game's own check shows victory/defeat from our side (the per-frame check is too late).
function V.cbKill(ctx, who)
  local ok, c = pcall(function() return who:get() end)
  log("KILL hook (post) " .. tostring(ok and c and c.IsValid and c:IsValid() and c:GetFName():ToString()))
  if ok and c and c.IsValid and c:IsValid() and V.sideOf and next(V.sideOf) then pcall(V.checkSides, true, c:GetAddress()) end
end
function V.hookKills()
  if E33V_KILLHOOKS then return end
  local BM = "/Game/jRPGTemplate/Blueprints/Components/AC_jRPG_BattleManager.AC_jRPG_BattleManager_C:"
  local ok1 = pcall(RegisterHook, BM .. "OnPlayerCharacterKilled", function(ctx, who) return V.cbKill(ctx, who) end)
  local ok2 = pcall(RegisterHook, BM .. "OnEnemyKilled", function(ctx, who) return V.cbKill(ctx, who) end)
  E33V_KILLHOOKS = ok1 and ok2
  log("kill hooks: " .. tostring(ok1) .. " " .. tostring(ok2))
end

-- ---------- main-menu entry ----------
-- F6 on the title screen: list save slots (through the game's own load screen), load the chosen one,
-- then open the versus setup once the world is ready. Autosave is turned off as soon as the world exists.
-- The world controller, cached per world: readyCheck asks every frame while waiting for the opponent, and a per-frame
-- FindFirstOf while a reloaded level streams in crashed the game (rematch 2026-10-08 11:28). Searched at most 1x/s.
function V.inWorld()
  if V.loading then return false end
  local c = V.worldPC
  if c and c:IsValid() then return true end
  if os.clock() - (V.worldPCAt or 0) < 1 then return false end
  V.worldPCAt = os.clock()
  c = FindFirstOf("BP_jRPG_Controller_World_C")
  V.worldPC = (c and c:IsValid()) and c or nil
  return V.worldPC ~= nil
end
-- Title VERSUS button (Sparking Zero flow): character select first, then the save to fight in, then the fight.
function V.menuTitle()
  V.cfg.level = nil
  ONLINE.modeMenu()
end
function V.startFromTitle()
  V.travelTried = nil
  local mm
  for _, w in ipairs(FindAllOf("WBP_MM_MainMenu_C") or {}) do if w:IsValid() and w:GetFullName():find("/Engine/Transient", 1, true) then mm = w end end
  if not mm then log("no main menu"); return end
  V.fightWhenReady = os.clock()
  -- The game autosaves while the world loads (22:06 test wrote slot 2): turn autosave off BEFORE loading.
  log("versus: teams ready, pick the save to fight in (autosave off before load: " .. tostring(V.noAutoSave()) .. ")")
  mm:OnContinueClicked()
end
-- ---------- unit size ----------
-- Some bosses are far bigger than the arena cameras expect (Visages, Paintress...): scale oversized units down
-- so their height fits under V.MAX_HEIGHT (cm, Unreal units). Heroes are ~180 cm.
V.MAX_HEIGHT = 450
function V.fitSize(actor)
  local origin, extent = {}, {}
  actor:GetActorBounds(false, origin, extent, false)
  local h = (extent.Z or 0) * 2
  if h <= V.MAX_HEIGHT or h <= 0 then log(("size %s: %.0f cm (kept)"):format(actor:GetFName():ToString(), h)); return end
  local k = V.MAX_HEIGHT / h
  local sc = actor:GetActorScale3D()
  actor:SetActorScale3D({ X = sc.X * k, Y = sc.Y * k, Z = sc.Z * k })
  log(("size %s: %.0f cm -> scaled x%.2f"):format(actor:GetFName():ToString(), h, k))
end

-- ---------- arenas (locations) ----------
function V.arenaById(id) for _, a in ipairs(ARENAS or {}) do if a.id == id then return a end end end
function V.currentLevel()
  local w = V.inWorld() and V.worldPC or nil
  local n = w and w:IsValid() and w:GetFullName():match("/([^/%.]+)%.[^/]*:PersistentLevel") or nil
  return n or "?"
end
-- The same battle map on both PCs: the first one by object name (FindAllOf order can differ between machines).
function V.pickBattleMap()
  local maps = FindAllOf("BP_BattleMap_C") or {}
  table.sort(maps, function(a, b) return a:GetFName():ToString() < b:GetFName():ToString() end)
  return maps[1]
end
-- Returns true when a level change was started (the fight continues once the new world is ready).
-- Travel through the game's own map change (FL_jRPG_CustomFunctionLibrary:ChangeMapByAssetName -> GI ChangeMap):
-- it applies the level's DT_LevelData parameters (screen-space fog scattering, audio...). A raw console "open" skipped
-- them: wrong rendering after an arena teleport (issue #4). Console "open" stays as the fallback.
function V.levelSpawn(level)
  for _, a in ipairs(ARENAS or {}) do if a.level == level then return a.spawn end end
end
function V.travelTo(level)
  local pc = FindFirstOf("PlayerController")
  local spawn = V.levelSpawn(level)
  local ok, err = false, "no spawn point for " .. tostring(level)
  if spawn and spawn ~= "" then
    ok, err = pcall(function()
      local fl = StaticFindObject("/Game/jRPGTemplate/Blueprints/Basics/FL_jRPG_CustomFunctionLibrary.Default__FL_jRPG_CustomFunctionLibrary_C")
      fl:ChangeMapByAssetName(FName(level), { TagName = FName(spawn) }, pc)
    end)
  end
  log(("travel %s via ChangeMap (%s): %s"):format(level, tostring(spawn), ok and "ok" or ("FAILED " .. tostring(err) .. " -> console open")))
  if not ok then StaticFindObject("/Script/Engine.Default__KismetSystemLibrary"):ExecuteConsoleCommand(pc, "open " .. level, pc) end
end
function V.travelIfNeeded()
  local a = V.cfg.arenaId and V.arenaById(V.cfg.arenaId)
  -- Rematch in the same world: reload the level first. A second battle in a world runs on new battle objects while
  -- the wheel widget, cameras and caches still hold the first battle's (hero camera low and close, actions lost).
  -- A fresh level makes every match a first match.
  if (V.matchesHere or 0) > 0 and (not a or V.currentLevel() == a.level) then
    local lvl = V.currentLevel()
    if V.travelTried ~= lvl then
      V.travelTried = lvl
      log("rematch: reloading " .. lvl .. " for a clean battle")
      V.travelTo(lvl)
      return true
    end
    return false
  end
  if not a or V.currentLevel() == a.level then return false end
  if V.travelTried == a.level then log("travel to " .. a.level .. " did not happen, fighting here"); return false end
  V.travelTried = a.level
  log("travel: " .. V.currentLevel() .. " -> " .. a.level .. " (" .. a.name .. ")")
  V.travelTo(a.level)
  return true
end
-- A raw level open skips the game's fade-in: lift the camera fade so exploration is not left black.
function V.clearFade()
  local pc = (TICK and TICK.pc and TICK.pc:IsValid()) and TICK.pc or FindFirstOf("PlayerController")
  if pc and pc:IsValid() and pc.PlayerCameraManager then pc.PlayerCameraManager:StopCameraFade() end
end
function V.readyCheck()
  if not (V.openWhenReady or V.fightWhenReady) or not V.inWorld() then return end
  -- waiting for the opponent's "loaded": nothing to do (the steps below search objects; per frame while a level
  -- streams in, that crashed the game: rematch 2026-10-08 11:28)
  if V.fightWhenReady and V.online and V.online.sentLoaded and not V.online.peerLoaded then return end
  if not V.worldSeen then V.worldSeen = os.clock(); V.noAutoSave(); return end
  if os.clock() - V.worldSeen < 3 then return end
  V.worldSeen = nil
  V.noAutoSave()
  pcall(V.clearFade)
  -- arena: travel to the chosen location first (same level for both online players), then continue here
  if V.fightWhenReady and V.travelIfNeeded() then return end
  if V.fightWhenReady and V.online then
    -- online: both start the fight together. ALWAYS tell the opponent we are here, even if their "loaded" came first:
    -- sending it only while still waiting left the faster PC waiting forever (the slower one fought alone).
    if not V.online.sentLoaded then V.online.sentLoaded = true; NET.msg("loaded", {}); log("online: loaded" .. (V.online.peerLoaded and "" or ", waiting for the opponent")) end
    if not V.online.peerLoaded then
      V.worldSeen = os.clock() - 3   -- re-check next frame without re-waiting 3 s
      return
    end
  end
  if V.fightWhenReady then
    V.fightWhenReady = nil
    if V.online then V.online.inMatch = true end
    V.battleMap = V.pickBattleMap()
    for _, side in ipairs({ "A", "B" }) do for i = 1, 3 do local u = V.cfg[side][i]
      if u and u.kind == "hero" then local o = {}; local cm = FindFirstOf("AC_jRPG_CharactersManager_C")
        pcall(function() cm:GetCharacterData(FName(u.id), o) end)
        if not (o.CharacterData and o.CharacterData:IsValid()) then log("WARNING: this save has no " .. u.name .. " -> slot left empty"); V.cfg[side][i] = nil end
      end end end
    log("world ready -> versus fight at " .. V.currentLevel() .. " / " .. tostring(V.battleMap and V.battleMap:GetFName():ToString()))
    V.cfg.level = V.cfg.level or V.avgHeroLevel()
    V.start()
  else
    V.openWhenReady = nil
    log("world ready -> versus setup")
    SEL.open("world")
  end
end

-- ---------- hooks & keys (once) ----------
-- The game's damage/targeting code assumes "heroes" (Enemy?=false, PlayerCharacters) vs "enemies" (Enemy?=true, Enemies).
-- Each turn, re-label the two versus sides so the acting unit sees the world the way its class expects:
-- a hero-class unit's own side are the heroes; an enemy-class unit's OPPONENTS are the heroes.
-- heroSide: which side the game should see as "heroes". Default: the acting unit's side for hero classes, the
-- opposite side for enemy classes (their AI attacks "heroes"). The native wheel/targeting needs the acting side as heroes.
function V.applyPerspective(c, forceHeroSide)
  local mySide = V.sideOf[c:GetAddress()]
  if not mySide then return end
  local heroSide = forceHeroSide or (P.isEnemyClass(c) and (mySide == "A" and "B" or "A") or mySide)
  local bm = U.bm(); local all = {}
  for _, arr in ipairs({ bm.PlayerCharacters, bm.Enemies }) do for i = 1, #arr do all[#all + 1] = arr[i] end end
  local heroes, enemies = {}, {}
  for _, u in ipairs(all) do
    local side = V.sideOf[u:GetAddress()]
    if side == heroSide then heroes[#heroes + 1] = u; u["Enemy?"] = false else enemies[#enemies + 1] = u; u["Enemy?"] = true end
  end
  bm.PlayerCharacters:Empty(); bm.Enemies:Empty()
  for i, u in ipairs(heroes) do bm.PlayerCharacters[i] = u end
  for i, u in ipairs(enemies) do bm.Enemies[i] = u end
  V.heroSide = heroSide
end
-- Balance telemetry for every action (heroes too): HP lost per unit since the previous turn start,
-- credited to the unit that acted in between.
function V.damageLog(next)
  local snap = {}
  for _, u in ipairs(V.units or {}) do
    if u:IsValid() then snap[u:GetAddress()] = { u = u, hp = u.AC_jRPG_CharacterStats.CurrentHP } end
  end
  if V.lastActor and V.lastSnap then
    local parts, total = {}, 0
    for a, o in pairs(V.lastSnap) do
      local now = snap[a] and snap[a].hp or 0
      local d = o.hp - now
      if math.abs(d) >= 1 then
        total = total + math.max(0, d)
        parts[#parts + 1] = ("%s %+.0f (%.1f%%, left %.1f)"):format(V.short(o.u), -d, 100 * d / math.max(1, o.max), now)
      end
    end
    log(("DMG %s [side %s]: %.0f total | %s"):format(V.lastActor, tostring(V.lastSide), total, #parts > 0 and table.concat(parts, ", ") or "no HP change"))
  end
  for _, o in pairs(snap) do o.max = V.maxHP(o.u) end
  V.lastSnap, V.lastActor, V.lastSide = snap, V.short(next), V.sideOf and V.sideOf[next:GetAddress()]
end
function V.short(u) local ok, n = pcall(function() return u:GetFName():ToString():gsub("^BP_", ""):gsub("_C_%d+$", "") end); return ok and n or "?" end
function V.isCounterTurn(c, bm)
  local addr = c:GetAddress()
  local seen = V.counterUnits and V.counterUnits[addr]
  if seen then
    V.counterUnits[addr] = nil
    log(("counter check: %s countered %.1f s ago"):format(c:GetFName():ToString(), os.clock() - seen))
  end
  local okC, active = pcall(function() return bm.HasActiveCounterAttack == true end)
  return (okC and active) or (seen ~= nil and os.clock() - seen < V.COUNTER_WINDOW)
end
function V.onTurnStart(ctx)
  local c = ctx:get(); local addr = c:GetAddress(); local bm = U.bm()
  if V.spawnPending then return end   -- placeholder battle, our teams are not set up yet
  pcall(V.clearSkillPlaceholders)
  if WH then pcall(WH.onAnyTurn, c) end
  pcall(V.damageLog, c)
  V.turnSeen = true
  bm.DEBUG_RandomHeroAcquireOverride = nil
  pcall(E.flush)
  if V.sideOf and next(V.sideOf) and V.checkSides(true) then return end
  if V.sideOf and V.sideOf[addr] then V.applyPerspective(c) end
  for _, u in ipairs(V.units or {}) do if u:IsValid() then pcall(PH.afterTransition, u) end end
  local okP, skipped = pcall(PH.onTurn, c)
  if okP and skipped then log("turn: " .. c:GetFName():ToString() .. " is dead (phase death) -> skipped"); return end
  -- A counter-attack (after a full parry) fires OnTurnStart for the defender but is NOT a turn: no turn number, no
  -- turn message to the opponent, no wheel / AI (monsters cannot counter: V.counterWatch ends it; heroes counter
  -- automatically on both PCs, the parries that trigger it are mirrored). Online it was taken for a real turn: the
  -- opponent acted during the next unit's turn (local test 2026-10-08).
  if V.isCounterTurn(c, bm) then log("turn: " .. c:GetFName():ToString() .. " counter-attack (not a turn)"); return end
  if SYNC and SYNC.active() then
    if E33V_CONTROLLED[addr] then E.onTurn(c) end
    local okS, remote = pcall(SYNC.onTurn, c)
    if not okS then log("SYNC turn error " .. tostring(remote)) end
    if okS and remote then log("turn: " .. c:GetFName():ToString() .. " -> opponent"); return end
    if E33V_CONTROLLED[addr] then
      c["ControlledByBattleAI?"] = false
      local begin = function() local ok, err = pcall(WH.beginTurn, c); if not ok then log("WHEEL ERROR " .. tostring(err)) end end
      if SYNC.mustWait() then SYNC.holdTurn(begin, false) else begin() end
    elseif SYNC.mustWait() then
      SYNC.holdTurn(nil, true)   -- my hero: hands off the wheel until the opponent's state is applied
    end
    return
  end
  if AI then
    local okA, mine = pcall(AI.onTurn, c)
    if not okA then log("AI turn error " .. tostring(mine)) end
    if okA and mine then return end
  end
  if E33V_CONTROLLED[addr] then
    E.onTurn(c)
    c["ControlledByBattleAI?"] = false
    log("turn: " .. c:GetFName():ToString() .. " (heroes=side " .. tostring(V.heroSide) .. ") -> wheel")
    local ok, err = pcall(WH.beginTurn, c); if not ok then log("WHEEL ERROR " .. tostring(err)) end
  else
    log("turn: " .. c:GetFName():ToString() .. " (heroes=side " .. tostring(V.heroSide) .. ")")
  end
end
-- Registered lazily: the battle character class is only loaded once a battle exists.
function V.hookTurns()
  pcall(V.hookKills); pcall(V.hookEndFlows); pcall(V.hookActionStart)
  if E33V_TURNS_HOOKED then return end
  local ok, err = pcall(RegisterHook, "/Game/jRPGTemplate/Blueprints/Basics/BP_jRPG_Character_Battle_Base.BP_jRPG_Character_Battle_Base_C:OnTurnStart", function(ctx) V.onTurnStart(ctx) end)
  E33V_TURNS_HOOKED = ok
  log("turn hook: " .. tostring(ok) .. (ok and "" or (" " .. tostring(err))))
end
function V.onF6()
  -- online room: F6 never drops to local versus (issue #3). During a match it does nothing; after one it opens the
  -- online select screen of the same room (new teams + both Ready = rematch).
  if ONLINE and ONLINE.inRoom() then
    if ONLINE.battleRunning() then
      pcall(function() U.bm():ShowBattleMenuTooltip(FText("Online match in progress"), FText("Finish the match first")) end)
      return
    end
    if not SEL.active then ONLINE.enterSelect() end
    return
  end
  if V.inWorld() then SEL.open() else V.menuTitle() end
end
-- Per-frame work. Hooks only call V.* so that reloading this file updates behaviour.
function V.tick(pc)
  if V.loadCheck() then return end
  if TICK and TICK.fallback then pcall(TICK.fallback) end   -- window minimized: the widget ticker is silent
  -- A finishing blow by an enemy-class unit happens while its OPPONENTS are labelled "heroes": the game would see
  -- "all heroes dead" and play the defeat scene. Re-label from our side the frame a side is wiped (before the game's
  -- own end check at action finish).
  V.frameCheck()
  if TICK and os.clock() - (V.tickEnsureAt or 0) > 1 then V.tickEnsureAt = os.clock(); pcall(TICK.ensure) end
  pcall(V.counterWatch)
  pcall(GP.poll, pc)
  pcall(GP.lockMovement, pc, SEL and SEL.active or false)
  pcall(V.readyCheck)
  V.spawnCheck()
end
-- Swap the placeholder battle for our teams as soon as it exists. Called from the world-controller tick AND the widget
-- ticker: in the 11:33 rematch the setup never ran and the placeholder Chroma Maelle got a real turn (one-shot Gustave).
function V.spawnCheck()
  if not V.spawnPending then return end
  local bm = U.bm()
  -- the cached manager can be the previous battle's: follow the world controller's own one (a property read).
  -- No FindAllOf here: searching objects while the battle's assets stream in crashed the game (rematch 2026-10-08).
  if not (bm and bm:IsValid() and #bm.PlayerCharacters + #bm.Enemies > 0 and bm.BattleEndState == 0) then
    local own = U.bmFromPC()
    if own and (not bm or own:GetAddress() ~= bm:GetAddress()) then U._bm = own; bm = own end
  end
  local ready = bm and bm:IsValid() and bm.BattleEndState == 0 and bm.HasSpawnedHeroes and bm.HasSpawnedEnemies and #bm.PlayerCharacters > 0 and #bm.Enemies > 0
  if ready then
    V.spawnPending = false
    local ok, err = pcall(V.setup); if not ok then log("SETUP ERROR " .. tostring(err)) end
  elseif V.spawnAt and os.clock() - V.spawnAt > 6 and not V.spawnWarned then
    -- last resort, once, when the battle has been up for a while (assets loaded): search every battle manager
    V.spawnWarned = true
    log(("setup still waiting after 6 s: P=%s E=%s -> searching battle managers"):format(tostring(bm and #bm.PlayerCharacters), tostring(bm and #bm.Enemies)))
    local found = U.findBM(true); if found then U._bm = found end
  end
end
-- Level loads: stop all per-frame work and object searches from the map-load start until 3 s after the new
-- world's game state exists (searching objects mid-load is a known UE crash).
-- A level change destroys every actor, widget and component of the old world. Lua handles to them stay around, and
-- touching one later (even :IsValid() / IsInViewport on freed memory) crashed inside UE4SS's class walk
-- (UE4SS+0x2f6cee, always entered from the same engine frame: rematches 2026-10-08 10:37, 11:19, 11:28, 11:38,
-- 11:45). Drop them all when a load starts; everything is looked up again in the new world.
function V.dropHandles()
  U._bm, V.worldPC = nil, nil
  V.units, V.sideOf, V.uidOf, V.rowOf, V.customOf, V.lastSnap = {}, {}, {}, {}, {}, nil
  if CUSTOM then CUSTOM.dropHandles() end   -- imported textures, mesh components and HUD widgets of the old level
  if TICK then TICK.pc, TICK.w = nil, nil end
  if GP then GP.titlePC = nil end
  if SYNC then
    SYNC.lastUnit, SYNC.waiting, SYNC.held, SYNC.pendingHero, SYNC.turnSnap, SYNC.hero = nil, nil, nil, nil, nil, nil
    SYNC.queue = {}
  end
  if DEF then DEF.act, DEF.watch = nil, nil end
  if WH then WH.cur, WH._bmAddr, WH._tm, WH._wc = nil, nil, nil, nil end
  if MU then MU.comp, MU.trackId = nil, nil end
  if TB then TB.button = nil end
end
function V.onLoadStart() V.loading = true; V.worldAt = nil; V.searchWatchUntil = os.clock() + 40; V.dropHandles() end
function V.onWorldInit()
  V.loading = true; V.matchesHere = 0; V.searchWatchUntil = os.clock() + 40
  V.dropHandles()
  V.loadDoneAt = os.clock() + 5      -- cleared by V.loadCheck() from the per-frame hooks (no timers: they run off-thread)
end
function V.loadCheck()
  if V.loading and V.loadDoneAt and os.clock() >= V.loadDoneAt then V.loading, V.loadDoneAt = false, nil end
  return V.loading
end
function V.installHooks()
  if E33V_TICK_HOOKED then return true end
  local ok = pcall(RegisterHook, "/Game/jRPGTemplate/Blueprints/Basics/BP_jRPG_Controller_World.BP_jRPG_Controller_World_C:ReceiveTick", function(ctx) V.tick(ctx:get()) end)
  if ok then
    E33V_TICK_HOOKED = true
    E33V_CONTROLLED, E33V_SWITCHED, E33V_TARGET_FOR = E33V_CONTROLLED or {}, E33V_SWITCHED or {}, E33V_TARGET_FOR or {}
  end
  return ok
end
if not E33V_LOADHOOKS then
  E33V_LOADHOOKS = true
  pcall(RegisterLoadMapPreHook, function() V.onLoadStart() end)
  RegisterInitGameStatePostHook(function() V.onWorldInit() end)
end
if not V.installHooks() and not E33V_INITHOOK then
  -- World classes are not loaded at game start: retry whenever a new world's game state initializes.
  E33V_INITHOOK = true
  RegisterInitGameStatePostHook(function() V.installHooks() end)
end
-- Key dispatch: the character select screen (SEL) takes all keys while open; otherwise the list menus (UI).
function V.key(k)
  if SCR and SCR.active then SCR.key(k); return end
  if SEL and SEL.active then SEL.key(k); return end
  if k == "F6" then V.onF6()
  elseif k == "UP" then if UI.lines then WH.sfx("move") end; UI.move(-1)
  elseif k == "DOWN" then if UI.lines then WH.sfx("move") end; UI.move(1)
  elseif k == "ENTER" then if UI.lines and UI.onPick then WH.sfx("ok"); UI.onPick(UI.sel) end
  elseif k == "BACK" then if UI.lines and UI.onBack then WH.sfx("back"); UI.onBack() end end
end
-- Keyboard: UE4SS key binds (the title's menu system swallows arrows/Enter/S before the game's own input sees them, so
-- polling cannot work there). Each key is bound exactly ONCE; one handler on the game thread decides whether the key
-- types a character (a text field is being edited) or is a menu action.
KB = KB or {}
KB.CHAR = {}      -- Key code name -> { lower, upper }
for code = string.byte("A"), string.byte("Z") do local L = string.char(code); KB.CHAR[L] = { L:lower(), L } end
local digitKeys = { "ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE" }
for d, n in ipairs(digitKeys) do KB.CHAR[n] = { tostring(d - 1), tostring(d - 1) }; KB.CHAR["NUM_" .. n] = { tostring(d - 1), tostring(d - 1) } end
KB.CHAR.OEM_PERIOD = { ".", "." }; KB.CHAR.DECIMAL = { ".", "." }; KB.CHAR.OEM_MINUS = { "-", "-" }; KB.CHAR.SUBTRACT = { "-", "-" }
KB.ACTION = { F6 = "F6", UP_ARROW = "UP", DOWN_ARROW = "DOWN", LEFT_ARROW = "LEFT", RIGHT_ARROW = "RIGHT", RETURN = "ENTER",
  BACKSPACE = "BACK", TAB = "TAB", Q = "Q", E = "E", R = "R", F7 = "F7", F8 = "F8", SPACE = "SPACE" }
KB.last = KB.last or {}
KB.queue = KB.queue or {}
function KB.drain()
  local q = KB.queue; if #q == 0 then return end
  KB.queue = {}
  KB.lastUsed = os.clock()   -- footers show keyboard or controller hints by the last device used
  for _, n in ipairs(q) do pcall(KB.handle, n) end
end
local shiftKeys = { { KeyName = FName("LeftShift") }, { KeyName = FName("RightShift") } }
function KB.handle(name)
  local typing = SCR and SCR.active and SCR.typing
  local ch = KB.CHAR[name]
  if typing and ch then
    local pc = TICK and TICK.pc
    local shift = false
    if pc and pc:IsValid() then shift = pc:IsInputKeyDown(shiftKeys[1]) or pc:IsInputKeyDown(shiftKeys[2]) end
    SCR.typeChar(shift and ch[2] or ch[1])
    return
  end
  local action = KB.ACTION[name]
  if not action then return end
  local t = os.clock(); if KB.last[action] and t - KB.last[action] < 0.15 then return end; KB.last[action] = t
  local ok, err = pcall(V.key, action); if not ok then log("key " .. action .. ": " .. tostring(err)) end
end
if not E33V_KEYS4 then
  E33V_KEYS4 = true
  local names = {}
  for n in pairs(KB.CHAR) do names[n] = true end
  for n in pairs(KB.ACTION) do names[n] = true end
  for n in pairs(names) do
    if Key[n] then
      -- only queue: ExecuteInGameThread ran our Lua on the next engine event, which can be inside the level load the
      -- key just started (F on the load screen crashed the game 3x, UE4SS C++ exception). TICK.frame drains the queue
      -- and pauses during loads.
      local ok, err = pcall(RegisterKeyBind, Key[n], function() local q = KB.queue; q[#q + 1] = n end)
      if not ok then log("bind " .. n .. " failed: " .. tostring(err)) end
    end
  end
end

-- Team 1's portrait HUD is bound to the save's placeholder heroes, which setup destroys: rebuild it from the
-- real team-1 units (restored 00:26 after the keyboard rewrite cut it off the end of this file).
function V.rebuildHUD()
  local bm = U.bm(); local h = bm.BattleScreenWidget.WBP_HUD_DisplayCharacterPortraits
  local arr = h.CharacterPortraitWidgets
  for i = 1, #arr do pcall(function() arr[i]:RemoveFromParent() end) end
  arr:Empty()
  local n = 0
  for _, u in ipairs(V.units or {}) do
    if u:IsValid() and V.sideOf[u:GetAddress()] == "A" then
      local o = {}; h:AddCharacter(u.AC_jRPG_CharacterStats, o); n = n + 1
      local cu = V.customOf and V.customOf[u:GetAddress()]
      if cu and CUSTOM then pcall(CUSTOM.setPortrait, o.CreatedWidget, cu)
      elseif P.isEnemyClass(u) then pcall(V.setPortrait, o.CreatedWidget, (ROSTER[V.rowOf and V.rowOf[u:GetAddress()] or ""] or {}).portrait) end
    end
  end
  pcall(function() h:Set_CharactersCount(n) end)
  log("HUD rebuilt: " .. n .. " team-1 portraits")
end
