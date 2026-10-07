-- E33 Versus online: game side of the network bridge (requires json.lua).
-- The sidecar (sidecar/e33net.py, shipped as bin/e33net.exe) holds the TCP connection to the relay; we talk to it
-- through data/net/out.jsonl (we append) and data/net/in.jsonl (it appends, we read from our offset).
NET = NET or {}
NET.DIR = (E33V_DATA or "") .. "net/"
-- release: bin/e33net.exe (built by CI, no Python needed); dev: the .py through pythonw (E33V_SIDECAR_PY)
NET.SIDECAR = E33V_SIDECAR
NET.SIDECAR_PY = E33V_SIDECAR_PY
NET.SERVERS = (E33V_DATA or "") .. "servers.json"
NET.handlers = NET.handlers or {}     -- t or "msg:<k>" -> function(m)
NET.status = NET.status or { state = "offline" }

local function nlog(s) if V and V.log then V.log("NET " .. s) end end

function NET.touchAlive()
  local f = io.open(NET.DIR .. "alive", "w"); if f then f:write(os.date("%H:%M:%S")); f:close() end
  NET.aliveAt = os.clock()
end
-- Start the sidecar once per game session (it resets both files and exits 30 s after the game stops touching "alive").
function NET.start()
  if NET.started then return end
  os.execute('mkdir "' .. NET.DIR:gsub("/", "\\") .. '" 2>nul')
  NET.touchAlive()
  -- fresh session: empty both files BEFORE the sidecar starts (it never truncates, so nothing we queue is lost)
  for _, f in ipairs({ "out.jsonl", "in.jsonl" }) do local h = io.open(NET.DIR .. f, "w"); if h then h:close() end end
  NET.inOff = 0
  local bridge = NET.DIR:sub(1, -2)
  local cmd = NET.SIDECAR_PY and ('start "" /B pythonw "%s" --bridge "%s"'):format(NET.SIDECAR_PY, bridge)
    or ('start "" /B "%s" --bridge "%s"'):format(NET.SIDECAR, bridge)
  os.execute(cmd)
  NET.started = os.clock()
  nlog("sidecar started")
end
function NET.send(obj)
  local f = io.open(NET.DIR .. "out.jsonl", "a")
  if not f then nlog("cannot write out.jsonl"); return false end
  f:write(JSON.encode(obj) .. "\n"); f:close()
  return true
end
-- Game message to the opponent: NET.msg("pick", {side = "A", ...})
function NET.msg(k, fields)
  local m = fields or {}; m.t = "msg"; m.k = k
  return NET.send(m)
end
function NET.connect(server, name)
  NET.start()
  NET.server = server
  NET.send({ t = "connect", host = server.host, port = tonumber(server.port) or 33033, name = name or NET.playerName(), key = server.key or "",
    mod = E33V_VERSION })
end
function NET.playerName()
  local n = os.getenv("USERNAME") or "player"
  return n:sub(1, 16)
end
function NET.on(key, fn) NET.handlers[key] = fn end

-- Called on the game thread ~10x per second while online UI or an online match is active.
function NET.pump()
  if not NET.started then return end
  if os.clock() - (NET.aliveAt or 0) > 5 then NET.touchAlive() end
  local f = io.open(NET.DIR .. "in.jsonl", "rb"); if not f then return end
  local size = f:seek("end")
  if size < (NET.inOff or 0) then NET.inOff = 0 end          -- sidecar restarted and reset the file
  if size == NET.inOff then f:close(); return end
  f:seek("set", NET.inOff)
  local data = f:read("a"); f:close()
  local last = data:match(".*()\n")
  if not last then return end
  NET.inOff = NET.inOff + last
  for line in data:sub(1, last):gmatch("([^\n]+)\n") do
    local ok, m = pcall(JSON.decode, line)
    if ok and type(m) == "table" then NET.dispatch(m) end
  end
end
function NET.dispatch(m)
  local t = m.t
  if t == "net" then
    NET.status.state = m.state
    for k, v in pairs(m) do if k ~= "t" then NET.status[k] = v end end
  elseif t == "joined" then NET.status.room, NET.status.role, NET.status.peer = m.room, m.role, m.peer
  elseif t == "peer_joined" then NET.status.peer = m.name
  elseif t == "peer_left" then NET.status.peer = nil
  end
  nlog("<- " .. (t == "msg" and ("msg:" .. tostring(m.k)) or tostring(t)))
  local h = NET.handlers[t == "msg" and ("msg:" .. tostring(m.k)) or t] or NET.handlers["*"]
  if h then local ok, err = pcall(h, m); if not ok then nlog("handler " .. tostring(t) .. ": " .. tostring(err)) end end
  if NET.onAny then pcall(NET.onAny, m) end
end

-- ---------- saved servers (like a Minecraft server list) ----------
function NET.loadServers()
  local f = io.open(NET.SERVERS, "r")
  if not f then return {} end
  local s = f:read("a"); f:close()
  local ok, list = pcall(JSON.decode, s)
  return (ok and type(list) == "table") and list or {}
end
function NET.saveServers(list)
  local f = io.open(NET.SERVERS, "w"); if not f then return false end
  f:write(JSON.encode(list)); f:close(); return true
end
