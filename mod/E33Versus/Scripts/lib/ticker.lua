-- E33 Versus per-frame driver on the GAME THREAD, everywhere (title screen included).
-- UE4SS 3.0.1 LoopAsync callbacks run Lua on a second thread that shares the mod's Lua state; fast loops (15/40 ms)
-- next to heavy game-thread Lua (screen rebuilds while typing) crashed the game. Instead we keep one invisible
-- instance of a game widget that has a Blueprint Tick (WBP_DPISizeBox) in the viewport and hook that Tick.
TICK = TICK or {}
TICK.PATH = "/Game/UI/Widgets/CommonElements/ScalingText/WBP_DPISizeBox"
TICK.CLASS = TICK.PATH .. ".WBP_DPISizeBox_C"

-- Called on the game thread from the title activation hook and from the world tick: (re)create the ticking widget.
-- force: called from the title activation event (the title is fully loaded even if the 3 s load window is still open)
function TICK.ensure(force)
  if V and not force and V.loadCheck and V.loadCheck() then return end
  if TICK.w and TICK.w:IsValid() and TICK.w:IsInViewport() then return end
  pcall(LoadAsset, TICK.PATH)
  local c = StaticFindObject(TICK.CLASS)
  if not (c and c:IsValid()) then return end
  if not E33V_TICKHOOK then
    E33V_TICKHOOK = pcall(RegisterHook, TICK.CLASS .. ":Tick", function(ctx)
      if TICK.w and ctx:get():GetAddress() == TICK.w:GetAddress() then TICK.frame() end
    end)
  end
  local pc = FindFirstOf("PlayerController")
  if not (pc and pc:IsValid()) then return end
  local w = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary"):Create(pc, c, pc)
  w:SetRenderOpacity(0.0); w:SetVisibility(3)   -- HitTestInvisible: invisible, never takes input, still ticks
  w:AddToViewport(-100)
  TICK.w = w
end

function TICK.frame()
  if V and V.loadCheck and V.loadCheck() then return end
  local now = os.clock()
  local pc = TICK.pc
  if not (pc and pc:IsValid()) then pc = FindFirstOf("PlayerController"); TICK.pc = pc end
  if KB and KB.drain then pcall(KB.drain) end                  -- keyboard (queued by the key binds)
  if V and V.spawnCheck then pcall(V.spawnCheck) end           -- versus setup (world controller may not tick in battle)
  if V and V.frameCheck then pcall(V.frameCheck) end           -- end of match (also during cinematic attacks)
  if WH and WH.frame then pcall(WH.frame) end                   -- monster wheel: skill page, targeting labels, camera
  if SYNC and SYNC.tick then pcall(SYNC.tick) end               -- online: delayed own moves, replayed defenses
  if GP and GP.pollTitle then pcall(GP.pollTitle) end           -- title menus: gamepad + text fields
  if TB and TB.poll then pcall(TB.poll) end                     -- title VERSUS button timing
  if now - (TICK.devAt or 0) >= 1 then TICK.devAt = now; pcall(TICK.dev) end
  if NET and NET.started and now - (TICK.netAt or 0) >= 0.1 then
    TICK.netAt = now; pcall(NET.pump)
  end
end

-- Dev channels (were in main.lua's LoopAsync): hot reload flag and bridge/title.lua, checked once per second.
function TICK.dev()
  if not E33V_DEV then return end   -- developer channels only (dev.lua next to main.lua)
  local B = E33V_DEVDIR or E33V_DATA
  local fh = io.open(B .. "reload.flag", "r")
  if fh then
    fh:close(); os.remove(B .. "reload.flag")
    local bad = E33V_LOADALL and E33V_LOADALL("reload") or -1
    local out = io.open(B .. "reload.done", "w"); if out then out:write(os.date("%H:%M:%S") .. " failed=" .. bad .. "\n"); out:close() end
  end
  local th = io.open(B .. "title.lua", "r")
  if th then
    local src = th:read("a"); th:close(); os.remove(B .. "title.lua")
    local fn, perr = load(src)
    local ok, r = false, perr
    if fn then ok, r = pcall(fn) end
    local out = io.open(B .. "title.out", "w"); if out then out:write(os.date("%H:%M:%S") .. " " .. tostring(ok) .. " " .. tostring(r) .. "\n"); out:close() end
  end
end
