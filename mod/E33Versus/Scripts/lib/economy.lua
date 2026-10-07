-- E33 Versus move economy for non-hero units (requires picker.lua, versus.lua).
E = E or {}
E.AP_START, E.AP_PER_TURN, E.AP_MAX = 2, 1, 9
-- Costs come from a frozen table shipped with the mod (identical on both PCs online); new telemetry is appended to
-- the data folder and only becomes costs when a developer regenerates move_costs.tsv.
E.COSTS_FILE = (E33V_ROOT or "") .. "move_costs.tsv"
E.TELEMETRY = (E33V_DATA or "") .. "move_telemetry.txt"
-- Overrides: ["<ClassName>::<handle property>"] = cost (filled from playtests / telemetry).
E.COST_OVERRIDES = E.COST_OVERRIDES or {}
E.ap = E.ap or {}
function E.reset() E.ap = {}; E.loadMeasured() end
-- Measured costs: average "% of one unit's max HP dealt" per class::move from the telemetry file
-- -> cost = 1 + 4 x share (25% of a unit = 2 AP, a full unit = 5, two units = 9), clamped 1..9.
-- Rows with no damage (buffs, misses) are ignored so they fall back to the name heuristic.
function E.loadMeasured()
  local sum, n = {}, {}
  local f = io.open(E.COSTS_FILE, "r"); if not f then E.MEASURED = {}; return end
  for line in f:lines() do
    local _, cls, move, _, hits, _, pct = line:match("^([^	]*)	([^	]*)	([^	]*)	([^	]*)	([^	]*)	([^	]*)	([^	]*)")
    pct = tonumber(pct)
    if cls and pct and pct > 0 then local k = cls .. "::" .. move; sum[k] = (sum[k] or 0) + pct; n[k] = (n[k] or 0) + 1 end
  end
  f:close()
  E.MEASURED = {}
  for k, v in pairs(sum) do E.MEASURED[k] = math.max(1, math.min(9, 1 + math.floor(4 * v / n[k] + 0.5))) end
end
function E.moveCost(u, move) return E.costFor(u:GetClass():GetFName():ToString(), move.prop) end
-- By class name, so the select screen can price a loadout without a spawned unit (MOVES[row].cls).
function E.costFor(cls, prop)
  local key = cls .. "::" .. prop
  if E.COST_OVERRIDES[key] then return E.COST_OVERRIDES[key] end
  if not E.MEASURED then E.loadMeasured() end
  if E.MEASURED[key] then return E.MEASURED[key] end
  local l = prop:lower()
  if l:find("ultimate") or l:find("ult") or l:find("mayhem") or l:find("meteor") or l:find("beam") or l:find("wipe") then return 5 end
  if l:find("phase2") or l:find("phase3") or l:find("combo") or l:find("aoe") or l:find("all") then return 3 end
  return 1
end
function E.onTurn(u)
  local a = u:GetAddress()
  if WH and WH.readAP then pcall(WH.readAP, u) end
  E.ap[a] = math.min(E.AP_MAX, (E.ap[a] or (E.AP_START - E.AP_PER_TURN)) + E.AP_PER_TURN)
  return E.ap[a]
end
-- Telemetry: snapshot HP before an action; at the next turn start, log damage done per target.
function E.snapshot(u, move, target)
  local bm = U.bm(); local hp = {}
  for _, arr in ipairs({ bm.PlayerCharacters, bm.Enemies }) do for i = 1, #arr do local c = arr[i]
    hp[c:GetAddress()] = { c = c, hp = c.AC_jRPG_CharacterStats.CurrentHP, max = V.maxHP(c) } end end
  E.pending = { u = u, cls = u:GetClass():GetFName():ToString(), move = move.prop, target = target, hp = hp, cost = E.moveCost(u, move) }
end
function E.flush()
  local p = E.pending; E.pending = nil
  if not p then return end
  local total, pct, hits = 0, 0, 0
  for _, s in pairs(p.hp) do
    if s.c:IsValid() then
      local now = s.c.AC_jRPG_CharacterStats.CurrentHP
      local d = s.hp - now
      if d > 0 then total = total + d; pct = pct + d / math.max(1, s.max); hits = hits + 1 end
    else total = total + s.hp; pct = pct + 1; hits = hits + 1 end
  end
  local f = io.open(E.TELEMETRY, "a")
  if f then f:write(table.concat({ os.date("%Y-%m-%d %H:%M:%S"), p.cls, p.move, p.cost, hits, math.floor(total), string.format("%.3f", pct) }, "\t") .. "\n"); f:close() end
  V.log(("TELEMETRY %s %s: %d targets hit, %d dmg, %.0f%% of max HP total"):format(p.cls, p.move, hits, total, pct * 100))
end
