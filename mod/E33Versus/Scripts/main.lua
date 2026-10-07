-- E33 Versus loader (UE4SS 3.0.1 Lua mod). Loads lib/*.lua in order; every path comes from here.
-- No LoopAsync / ExecuteWithDelay / ExecuteInGameThread anywhere: in UE4SS 3.0.1 those run Lua on another thread that
-- shares this mod's Lua state, while the mod runs Lua every frame on the game thread (lib/ticker.lua) -> crashes.
local function here()
  local src = debug.getinfo(1, "S").source or ""
  src = src:gsub("^@", ""):gsub("\\", "/")
  return src:match("^(.*/)[^/]*$") or "./"
end

E33V_ROOT = here()                                    -- .../Mods/E33Versus/Scripts/
E33V_MOD = E33V_ROOT:gsub("Scripts/$", "")            -- .../Mods/E33Versus/
E33V_DATA = E33V_MOD .. "data/"                       -- logs, server list, network bridge (writable)
E33V_SIDECAR = E33V_MOD .. "bin/e33net.exe"           -- network sidecar (built by the release workflow)
E33V_SIDECAR_PY = nil                                 -- dev: path to sidecar/e33net.py (runs through pythonw)
E33V_DEV = false                                      -- dev channels: hot reload + data/title.lua
E33V_VERSION = "dev"

-- optional overrides: version.lua (written by the release workflow), dev.lua (developer machine, never shipped)
for _, f in ipairs({ "version.lua", "dev.lua" }) do
  local h = io.open(E33V_ROOT .. f, "r")
  if h then h:close(); local ok, err = pcall(dofile, E33V_ROOT .. f); if not ok then print("[E33Versus] " .. f .. ": " .. tostring(err) .. "\n") end end
end
os.execute('mkdir "' .. E33V_DATA:gsub("/", "\\"):gsub("\\$", "") .. '" 2>nul')

local FILES = { "unitlib.lua", "uilib.lua", "picker.lua", "roster_data.lua", "move_data.lua", "arena_data.lua", "music_data.lua", "versus.lua", "music.lua",
  "battlelib.lua", "economy.lua", "phases.lua", "wheel.lua", "select.lua", "gamepad.lua", "titlebutton.lua", "json.lua",
  "net.lua", "screens.lua", "online.lua", "sync.lua", "defense.lua", "ai.lua", "ticker.lua" }
function E33V_LOADALL(tag)
  local bad = 0
  for _, f in ipairs(FILES) do
    local ok, err = pcall(dofile, E33V_ROOT .. "lib/" .. f)
    if not ok then bad = bad + 1 end
    print("[E33Versus] " .. tag .. " " .. f .. (ok and " ok" or (" FAILED: " .. tostring(err))) .. "\n")
  end
  return bad
end
print("[E33Versus] " .. E33V_VERSION .. " from " .. E33V_MOD .. "\n")
E33V_LOADALL("load")
