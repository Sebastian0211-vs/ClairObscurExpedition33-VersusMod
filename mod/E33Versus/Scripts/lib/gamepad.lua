-- E33 Versus gamepad support: UE4SS key binds are keyboard-only, so poll the game's own input each frame
-- (PlayerController:WasInputKeyJustPressed) and feed the same V.key dispatcher as the keyboard.
GP = GP or {}
GP.MAP = {
  Gamepad_DPad_Up = "UP", Gamepad_DPad_Down = "DOWN", Gamepad_DPad_Left = "LEFT", Gamepad_DPad_Right = "RIGHT",
  Gamepad_LeftStick_Up = "UP", Gamepad_LeftStick_Down = "DOWN", Gamepad_LeftStick_Left = "LEFT", Gamepad_LeftStick_Right = "RIGHT",
  Gamepad_FaceButton_Bottom = "ENTER", Gamepad_FaceButton_Right = "BACK", Gamepad_FaceButton_Top = "TAB",
  Gamepad_LeftShoulder = "Q", Gamepad_RightShoulder = "E", Gamepad_LeftTrigger = "F7", Gamepad_RightTrigger = "F8",
  Gamepad_FaceButton_Left = "SPACE",   -- X = START (Start/View are used by the game: pause menu / map)
  Gamepad_RightThumbstick = "R",        -- R3 = edit moves (L3 + R3 together still toggles the screen)
}
local keys = {}
local function key(name) local k = keys[name]; if not k then k = { KeyName = FName(name) }; keys[name] = k end; return k end
function GP.poll(pc)
  if not (pc and pc:IsValid()) then return end
  -- L3 + R3 toggles the versus select screen (open in the world, close when open).
  if pc:IsInputKeyDown(key("Gamepad_LeftThumbstick")) and pc:IsInputKeyDown(key("Gamepad_RightThumbstick")) then
    if not GP.comboHeld then GP.comboHeld = true; V.key("F6") end
    return
  else GP.comboHeld = false end
  local menuOpen = (SEL and SEL.active) or UI.lines ~= nil
  if not menuOpen then return end
  for name, action in pairs(GP.MAP) do
    if pc:WasInputKeyJustPressed(key(name)) then V.key(action) end
  end
end
-- Keep the explorer still while the select screen is open (counters are paired).
function GP.lockMovement(pc, lock)
  if not (pc and pc:IsValid()) or GP.locked == lock then return end
  GP.locked = lock
  pc:SetIgnoreMoveInput(lock); pc:SetIgnoreLookInput(lock)
end

-- On the title there is no per-frame hook: poll held state from a 40 ms async loop (main.lua) on the game thread,
-- with our own edge detection (WasInputKeyJustPressed is per-frame and would be missed).
GP.down = GP.down or {}
function GP.pollTitle()
  local onTitle = (SEL and SEL.active and SEL.mode == "title") or (SCR and SCR.active)
  if not onTitle or V.loading then return end
  local pc = GP.titlePC
  if not (pc and pc:IsValid()) then pc = FindFirstOf("PlayerController"); GP.titlePC = pc end
  if not (pc and pc:IsValid()) then return end
  if TYPE and TYPE.poll then pcall(TYPE.poll, pc) end
  for name, action in pairs(GP.MAP) do
    local d = pc:IsInputKeyDown(key(name))
    if d and not GP.down[name] then V.key(action) end
    GP.down[name] = d
  end
end
