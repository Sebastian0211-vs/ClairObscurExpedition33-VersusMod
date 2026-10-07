-- E33 Versus online flow (requires net.lua, screens.lua, select.lua, versus.lua).
-- Title VERSUS -> Local / Online -> server list (add like Minecraft) -> lobby (create / join by code / open rooms)
-- -> room -> character select (each player edits only their own team, both Ready) -> each picks a save -> fight.
-- The host is Team 1 (side A), the guest Team 2 (side B).
ONLINE = ONLINE or {}

-- ---------- unit <-> wire ----------
function ONLINE.packTeam(side)
  local out = {}
  for i = 1, 3 do local u = V.cfg[side][i]
    if u then out[#out + 1] = u.kind == "hero" and { kind = "hero", id = u.id } or { kind = "enemy", row = u.row, loadout = u.loadout } end
  end
  return out
end
function ONLINE.unpackTeam(list)
  local out = {}
  for _, w in ipairs(list or {}) do
    if w.kind == "hero" then
      for _, h in ipairs(V.HEROES) do if h.id == w.id then out[#out + 1] = { kind = "hero", id = h.id, name = h.name or h.label, label = h.label } end end
    elseif w.row and ROSTER[w.row] then
      local d = ROSTER[w.row]
      out[#out + 1] = { kind = "enemy", row = w.row, name = d.name, cost = d.cost, label = d.name, loadout = w.loadout }
    end
  end
  return out
end
function ONLINE.mySide() return NET.status.role == "guest" and "B" or "A" end
function ONLINE.otherSide() return ONLINE.mySide() == "A" and "B" or "A" end
function ONLINE.isHost() return NET.status.role ~= "guest" end

-- ---------- menus ----------
function ONLINE.modeMenu()
  ONLINE.where = nil
  SCR.show({
    title = "Versus", subtitle = "Choose how to play",
    items = {
      { label = "Local versus", sub = "Two players on this PC, one controller each or shared keyboard", on = function() SCR.close(); V.cfg.level = nil; SEL.open("title") end },
      { label = "Online versus", sub = "Play against someone through a server", on = function() ONLINE.serverList() end },
      { label = "Back", on = function() SCR.exit() end },
    },
    back = function() SCR.exit() end,
  })
end

function ONLINE.serverList()
  ONLINE.where = nil
  local servers = NET.loadServers()
  local items = {}
  for i, s in ipairs(servers) do
    items[#items + 1] = { label = s.name or ("Server " .. i), sub = ("%s:%s"):format(s.host, s.port or 33033), on = function() ONLINE.connect(s) end }
  end
  items[#items + 1] = { label = "Add server", sub = "Name, address and key, saved for next time", on = function() ONLINE.addServer() end }
  if #servers > 0 then items[#items + 1] = { label = "Remove a server", on = function() ONLINE.removeServer() end } end
  items[#items + 1] = { label = "Back", on = function() ONLINE.modeMenu() end }
  SCR.show({ title = "Online", subtitle = "Servers", items = items, sel = 1, back = function() ONLINE.modeMenu() end })
end

function ONLINE.addServer()
  local f = { name = "", host = "", port = "33033", key = "" }
  SCR.show({
    title = "Online", subtitle = "Add server  -  Enter on a field to type, Enter again to confirm",
    items = {
      { label = "Server name", input = { value = "", hint = "My server", max = 24, on = function(v) f.name = v end } },
      { label = "Address", input = { value = "", hint = "example.com or 1.2.3.4", allow = "[%w%.%-]", max = 60, on = function(v) f.host = v end } },
      { label = "Port", input = { value = "33033", allow = "%d", max = 5, on = function(v) f.port = v end } },
      { label = "Server key", input = { value = "", hint = "leave empty if the server has none", max = 40, on = function(v) f.key = v end } },
      { label = "Save", on = function()
        local items = SCR.def.items
        f.name, f.host, f.port, f.key = items[1].input.value or "", items[2].input.value or "", items[3].input.value or "", items[4].input.value or ""
        if f.host == "" then SCR.msg = "Enter the server address"; SCR.refresh(); return end
        local list = NET.loadServers()
        list[#list + 1] = { name = (f.name ~= "" and f.name or f.host), host = f.host, port = tonumber(f.port) or 33033, key = f.key }
        NET.saveServers(list)
        ONLINE.serverList()
      end },
      { label = "Cancel", on = function() ONLINE.serverList() end },
    },
    sel = 1, back = function() ONLINE.serverList() end,
  })
end

function ONLINE.removeServer()
  local servers = NET.loadServers()
  local items = {}
  for i, s in ipairs(servers) do
    items[#items + 1] = { label = "Remove " .. (s.name or "?"), sub = ("%s:%s"):format(s.host, s.port or 33033), on = function()
      table.remove(servers, i); NET.saveServers(servers); ONLINE.serverList() end }
  end
  items[#items + 1] = { label = "Back", on = function() ONLINE.serverList() end }
  SCR.show({ title = "Online", subtitle = "Remove a server", items = items, sel = #items, back = function() ONLINE.serverList() end })
end

-- ---------- connection / lobby ----------
function ONLINE.connect(server)
  ONLINE.server, ONLINE.rooms = server, {}
  ONLINE.installHandlers()
  NET.connect(server)
  ONLINE.lobby()
end
function ONLINE.disconnect()
  ONLINE.where = nil
  NET.send({ t = "disconnect" })
  NET.status.room, NET.status.role, NET.status.peer = nil, nil, nil
  ONLINE.askedRooms = nil
  ONLINE.serverList()
end
-- Send this PC's game log to the server (the relay stores it for the server owner). reason: match-end, peer-left,
-- desync, manual. The sidecar reads the file itself (last 1 MB) and sends it in parts.
function ONLINE.uploadLog(reason)
  if NET.status.state ~= "online" then return false end
  NET.send({ t = "upload_log", path = V.LOGF, reason = reason or "manual" })
  V.log("NET log upload requested (" .. tostring(reason) .. ")")
  return true
end
function ONLINE.statusLines()
  local s = NET.status
  local lines = { ONLINE.server and ONLINE.server.name or "Server" }
  if s.state == "online" then lines[#lines + 1] = { "Connected" .. (s.ping_ms and ("  -  " .. s.ping_ms .. " ms") or ""), "WHITE" }
  elseif s.state == "connecting" then lines[#lines + 1] = { "Connecting...", "GREY" }
  else lines[#lines + 1] = { "Offline" .. (s.error and ("  -  " .. tostring(s.error)) or ""), "RED" } end
  if s.motd and s.state == "online" then lines[#lines + 1] = { tostring(s.motd), "GREY" } end
  if s.room then
    lines[#lines + 1] = { "Room " .. s.room .. "   (" .. (s.role == "host" and "you host" or "guest") .. ")", "GOLD" }
    lines[#lines + 1] = { s.peer and ("Opponent: " .. s.peer) or "Waiting for an opponent...", s.peer and "WHITE" or "GREY" }
  end
  return lines
end
function ONLINE.lobby()
  local s = NET.status
  if s.room then return ONLINE.roomScreen() end
  ONLINE.where = "lobby"
  local online = s.state == "online"
  local items = {
    { label = "Create room", sub = "Get a code to give your opponent", disabled = not online, on = function() NET.send({ t = "create" }) end },
    { label = "Join room", input = { value = ONLINE.joinCode or "", hint = "room code, e.g. K7QD", allow = "%w", max = 4, on = function(v)
      ONLINE.joinCode = v:upper(); if v ~= "" then NET.send({ t = "join", room = ONLINE.joinCode }) end end } },
    { label = "Refresh open rooms", disabled = not online, on = function() NET.send({ t = "rooms" }) end },
  }
  for _, r in ipairs(ONLINE.rooms or {}) do
    if r.players < 2 then items[#items + 1] = { label = "Join " .. r.room, sub = "hosted by " .. tostring(r.host), on = function() NET.send({ t = "join", room = r.room }) end } end
  end
  if s.state == "offline" then
    items[#items + 1] = { label = "Reconnect", sub = s.error and tostring(s.error) or nil, on = function() ONLINE.connect(ONLINE.server) end }
  end
  items[#items + 1] = { label = "Send logs", sub = "Upload your game log to this server (bug reports)", disabled = not online,
    on = function() SCR.msg = ONLINE.uploadLog("manual") and "Sending logs..." or "Not connected"; SCR.refresh() end }
  items[#items + 1] = { label = "Disconnect", on = function() ONLINE.disconnect() end }
  SCR.show({ title = "Online", subtitle = "Lobby", items = items, info = ONLINE.statusLines(),
    back = function() ONLINE.disconnect() end })
  if online and not ONLINE.askedRooms then ONLINE.askedRooms = true; NET.send({ t = "rooms" }) end
end
function ONLINE.roomScreen()
  ONLINE.where = "room"
  SCR.show({ title = "Online", subtitle = "Room " .. tostring(NET.status.room) .. "  -  give this code to your opponent",
    items = { { label = "Leave room", on = function() NET.send({ t = "leave" }); NET.status.room = nil; ONLINE.lobby() end },
      { label = "Send logs", sub = "Upload your game log to this server (bug reports)",
        on = function() SCR.msg = ONLINE.uploadLog("manual") and "Sending logs..." or "Not connected"; SCR.refresh() end } },
    info = ONLINE.statusLines(), back = function() NET.send({ t = "leave" }); NET.status.room = nil; ONLINE.lobby() end })
end

-- ---------- online character select ----------
function ONLINE.enterSelect()
  ONLINE.where = nil
  SCR.close()
  V.cfg.A, V.cfg.B, V.cfg.level = {}, {}, nil
  SEL.online = { me = ONLINE.mySide(), ready = { A = false, B = false } }
  SEL.side = SEL.online.me
  SEL.open(V.inWorld() and "world" or "title")
end
function ONLINE.sendTeam()
  local me = SEL.online.me
  SEL.online.ready[me] = false
  NET.msg("team", { side = me, units = ONLINE.packTeam(me) })
  NET.msg("ready", { side = me, ready = false })
end
function ONLINE.toggleReady()
  local o = SEL.online; local me = o.me
  if ONLINE.battleRunning() then SEL.msg = "A battle is still running here: finish it first (or restart the game)"; return end
  if not V.cfg[me][1] then SEL.msg = "Pick at least one unit first"; return end
  o.ready[me] = not o.ready[me]
  NET.msg("ready", { side = me, ready = o.ready[me] })
  ONLINE.maybeGo()
end
function ONLINE.sendSettings() if ONLINE.isHost() then NET.msg("settings", { arena = V.cfg.arena, arenaId = V.cfg.arenaId, level = V.cfg.level, music = V.cfg.music }) end end
function ONLINE.maybeGo()
  local o = SEL.online
  if not (o and o.ready.A and o.ready.B and ONLINE.isHost()) then return end
  -- music: "Random" is resolved here once so both PCs play the same track
  local go = { arena = V.cfg.arena, arenaId = V.cfg.arenaId, level = V.cfg.level, music = MU.resolve(V.cfg.music), seed = os.time(), A = ONLINE.packTeam("A"), B = ONLINE.packTeam("B") }
  NET.msg("go", go)
  ONLINE.go(go)
end
-- An online match is running from "go" until its end screen. (The battle manager's arrays stay filled after a match
-- ended, which made Ready say "a battle is still running" with nothing running: issue #3.)
function ONLINE.battleRunning()
  return V.online ~= nil and (V.fightWhenReady ~= nil or V.online.inMatch == true) and not V.ended
end
function ONLINE.inRoom() return NET.status.room ~= nil and NET.status.state == "online" end
-- The opponent opened the select screen after a match (F6): open it here too so their team / ready state lands.
function ONLINE.followPeer()
  if not SEL.online and ONLINE.inRoom() and not ONLINE.battleRunning() then ONLINE.enterSelect() end
end
function ONLINE.go(g)
  V.cfg.A, V.cfg.B = ONLINE.unpackTeam(g.A), ONLINE.unpackTeam(g.B)
  V.cfg.arena, V.cfg.arenaId, V.cfg.level = g.arena or V.cfg.arena, g.arenaId, g.level
  V.matchMusic = g.music
  V.online = { me = ONLINE.mySide(), seed = g.seed, peerLoaded = false }
  SEL.online = nil
  SEL.close()
  if V.inWorld() then
    -- already in a world (rematch): no save to load. V.readyCheck sends "loaded" once this PC is really ready
    -- (a rematch first reloads the level: announcing it here let the opponent start while we were still loading).
    V.fightWhenReady, V.worldSeen = os.clock(), os.clock() - 3
  else
    V.startFromTitle()
  end
end

-- ---------- network events ----------
function ONLINE.installHandlers()
  -- redraw only while the lobby / room screen is showing (after Disconnect these events re-opened the lobby: issue #1)
  NET.on("net", function() if SCR.active and ONLINE.where then if NET.status.room then ONLINE.roomScreen() else ONLINE.lobby() end end end)
  NET.on("rooms", function(m) ONLINE.rooms = m.rooms or {}; if SCR.active and ONLINE.where == "lobby" and not NET.status.room then ONLINE.lobby() end end)
  NET.on("error", function(m) SCR.msg = tostring(m.why); if SEL.active then SEL.msg = tostring(m.why); SEL.build() else SCR.refresh() end end)
  NET.on("joined", function(m)
    if m.peer then ONLINE.enterSelect() else ONLINE.roomScreen() end
  end)
  NET.on("peer_joined", function() ONLINE.enterSelect() end)
  NET.on("peer_left", function()
    if SEL.active and SEL.online then SEL.online = nil; SEL.close() end
    SCR.msg = "Your opponent left"
    if V.online and V.online.inMatch and not V.ended then V.log("NET opponent left during the match"); ONLINE.uploadLog("peer-left") end
    ONLINE.roomScreen()
  end)
  NET.on("msg:team", function(m)
    ONLINE.followPeer()
    if not SEL.online or m.side == SEL.online.me then return end
    V.cfg[m.side] = ONLINE.unpackTeam(m.units)
    if SEL.active then SEL.build() end
  end)
  NET.on("msg:ready", function(m)
    ONLINE.followPeer()
    if not SEL.online or m.side == SEL.online.me then return end
    SEL.online.ready[m.side] = m.ready and true or false
    ONLINE.maybeGo()
    if SEL.active then SEL.build() end
  end)
  NET.on("msg:settings", function(m)
    if ONLINE.isHost() then return end
    V.cfg.arena, V.cfg.arenaId, V.cfg.level, V.cfg.music = m.arena or V.cfg.arena, m.arenaId, m.level, m.music
    if SEL.active then SEL.build() end
  end)
  NET.on("msg:go", function(m) if not ONLINE.isHost() then ONLINE.go(m) end end)
  NET.on("msg:loaded", function() if V.online then V.online.peerLoaded = true end end)
  NET.on("log_ok", function(m)
    if m.part ~= m.parts then return end
    V.log("NET log upload done")
    if SCR.active then SCR.msg = "Logs sent to the server"; SCR.refresh() end
  end)
  SYNC.install()

  NET.onAny = function() if SCR.active and not SCR.typing and (NET.status.state ~= ONLINE.lastState) then ONLINE.lastState = NET.status.state; SCR.refresh() end end
end
