-- E33 Versus: a "VERSUS" entry in the title screen's button list (built from the game's own button widgets).
TB = TB or {}
local TITLE_CLS = "/Game/UI/Widgets/MainMenu/WBP_MM_TitleScreen.WBP_MM_TitleScreen_C"
-- FindFirstOf can return the template inside WBP_MM_MainMenu's class (no ButtonsBox); take the live instance.
function TB.liveTitle()
  for _, t in ipairs(FindAllOf("WBP_MM_TitleScreen_C") or {}) do
    if t:IsValid() and t.ButtonsBox:IsValid() and t:GetFullName():find("/Engine/Transient", 1, true) then return t end
  end
end
function TB.add(title)
  title = title or TB.liveTitle()
  if not (title and title:IsValid()) then return "no title" end
  if TB.button and TB.button:IsValid() then return "already" end
  local pc = FindFirstOf("PlayerController")
  local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
  local cont = title.ContinueButton
  local btn = wbl:Create(pc, cont:GetClass(), pc)
  local head = wbl:Create(pc, title.ContinueText:GetClass(), pc)
  -- Continue's label sits centred in an Overlay inside the button's ButtonContent slot: copy that.
  local ov = StaticConstructObject(StaticFindObject("/Script/UMG.Overlay"), title.WidgetTree, FName("E33V_VersusOverlay"))
  ov:AddChildToOverlay(head):SetHorizontalAlignment(2)
  -- Parent everything in this same call: unparented widgets held only from Lua get garbage-collected.
  btn.ButtonContent:SetContent(ov)
  local s = title.ButtonsBox:AddChildToVerticalBox(btn)   -- InsertChildAt is not a UFunction (not callable from Lua)
  local cp = cont.Slot.Padding
  s:SetPadding({ Left = cp.Left, Top = cp.Top, Right = cp.Right, Bottom = cp.Bottom })
  for _, k in ipairs({ "HideBackgroundWhenNotFocused", "HasHoverStain", "IsSelectedInstant", "HidePressedAnim" }) do btn[k] = cont[k] end
  btn.Background:SetRenderOpacity(0.0)
  TB.button, TB.head = btn, head
  TB.setText()
  TB.textAt = os.clock()   -- the heading's OnNextTick resets the text to its default: set it again from TB.poll
  return "added"
end
-- The heading draws a big first letter + the rest. Its "Set Text" takes a by-ref FText UE4SS can't pass, and
-- FText/FString property writes corrupt memory in UE4SS 3.0.1, so set the two inner text blocks natively.
function TB.setText()
  local h = TB.head
  if h and h:IsValid() then h.FirstLetter:SetText(FText("V")); h.Heading.Text:SetText(FText("ersus")) end
end
-- The title screen class is not loaded at mod start (NotifyOnNewObject never fired), so hook its activation
-- event once it exists: retry on every BeginPlay until RegisterHook succeeds.
function TB.tryHook()
  if E33V_TB_TITLEHOOK then return end
  local c = StaticFindObject(TITLE_CLS)
  if not (c and c:IsValid()) then return end
  -- Only remember the title here; the button is built later from main.lua's idle poll (TB.poll), never
  -- inside BeginPlay/activation (the 21:11 crash ran widget code there).
  local ok = pcall(RegisterHook, TITLE_CLS .. ":BP_OnActivated", function(ctx)
    TB.pendingAt = os.clock()
    V.log("title activated")
    if TICK then pcall(TICK.ensure, true) end   -- game thread: start the per-frame driver on the title
  end)
  E33V_TB_TITLEHOOK = ok
end
-- Called every frame from TICK.frame (game thread): build the button 2 s after the title activated.
TB.AUTO = true    -- same code verified manually 21:18 (title.sh); auto timing (2 s after activation) not yet seen
function TB.poll()
  if TB.textAt and os.clock() - TB.textAt > 1 then TB.textAt = nil; pcall(TB.setText) end
  if not (TB.AUTO and TB.pendingAt) or os.clock() - TB.pendingAt < 2 then return end
  TB.pendingAt = nil
  local ok, r = pcall(TB.add); V.log("title button: " .. tostring(ok) .. " " .. tostring(r))
end
if not E33V_TB_HOOKED then
  E33V_TB_HOOKED = true
  local lastTry = -1
  RegisterBeginPlayPostHook(function()
    if E33V_TB_TITLEHOOK then return end
    local t = os.clock(); if t - lastTry < 0.5 then return end; lastTry = t
    TB.tryHook()
  end)
  RegisterHook("/Script/CommonUI.CommonButtonBase:HandleButtonClicked", function(ctx)
    local b = ctx:get()
    if TB.button and TB.button:IsValid() and b:GetAddress() == TB.button:GetAddress() then
      local t = os.clock(); if TB.lastClick and t - TB.lastClick < 1.0 then return end; TB.lastClick = t
      pcall(V.menuTitle)   -- hook runs on the game thread
    end
  end)
end
