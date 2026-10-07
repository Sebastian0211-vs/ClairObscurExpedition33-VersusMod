-- E33 Versus fight music (requires music_data.lua, versus.lua).
-- V.cfg.music: nil = a random battle track, "area" = keep the location's music, else a MUSIC id.
-- Versus battles start without battle music (the music system stays in its exploration context), so the chosen
-- track is played through the music system's own "Create New Audio Component" (music mix) while the current context
-- is paused, and faded out at the end of the match. (PushInteractiveMusicContext needs a struct UE4SS 3.0.1 cannot
-- build from Lua; SpawnSound2D returned nothing.)
MU = MU or {}
local function mlog(s) V.log("MUSIC " .. s) end

function MU.byId(id) for _, m in ipairs(MUSIC or {}) do if m.id == id then return m end end end
-- Picker list: the two special entries first.
function MU.list()
  if not MU._list then
    MU._list = { { id = nil, name = "Random battle track" }, { id = "area", name = "Location music (no battle track)" } }
    for _, m in ipairs(MUSIC or {}) do MU._list[#MU._list + 1] = m end
  end
  return MU._list
end
function MU.label(id)
  if id == nil then return "Random" end
  if id == "area" then return "Location" end
  local m = MU.byId(id); return m and m.name or tostring(id)
end
-- A concrete track for this match (online: the host resolves it once and sends it with "go").
function MU.resolve(id)
  if id == nil and MUSIC and #MUSIC > 0 then return MUSIC[math.random(#MUSIC)].id end
  return id
end

local function ims()
  local gi = FindFirstOf("BP_jRPG_GI_Custom_C")
  return gi and gi:IsValid() and gi.InteractiveMusicSystem or nil
end
-- Battle start (V.setup done): play the match's track.
function MU.start()
  MU.stop(0)
  local id = V.matchMusic or MU.resolve(V.cfg.music)
  V.matchMusic = nil
  if id == "area" then mlog("location music kept"); return end
  local m = MU.byId(id); if not m then mlog("no track " .. tostring(id)); return end
  local ok, err = pcall(function()
    -- LoadAsset's handle is rejected as a call argument and StaticFindObject wants the exact-case path (the pak
    -- index lists ".../MUSIC/..." for ".../Music/..."): look the object up under the name the loaded asset reports.
    -- Same frame as the load: an unreferenced asset is collected later.
    local loaded = LoadAsset(m.path)
    local full = loaded and loaded:GetFullName():match("^%S+%s+(.+)$") or m.path
    local snd = StaticFindObject(full)
    assert(snd and snd:IsValid(), "not loaded: " .. m.path)
    local sys = ims(); assert(sys and sys:IsValid(), "no music system")
    local o = {}
    sys["Create New Audio Component"](sys, snd, o)
    local comp = o.SpawnedComponent; assert(comp and comp:IsValid(), "no audio component")
    sys:PauseInteractiveMusicCurrentContext()
    comp:Play(0.0)
    MU.comp, MU.paused = comp, true
  end)
  mlog(("%s: %s"):format(m.name, ok and "playing" or ("FAILED " .. tostring(err))))
end
-- Match end / rematch / leaving: fade our track out and give the music back to the game.
function MU.stop(fade)
  local comp = MU.comp; MU.comp = nil
  if comp and comp:IsValid() then pcall(function() if (fade or 0) > 0 then comp:FadeOut(fade, 0.0, 0) else comp:Stop() end end) end
  if MU.paused then
    MU.paused = false
    pcall(function() local sys = ims(); if sys then sys:UnpauseInteractiveMusicCurrentContext() end end)
  end
end
