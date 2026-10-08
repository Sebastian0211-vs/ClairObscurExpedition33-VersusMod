-- E33 Versus in-battle list menu (move picker, targets, "opponent's turn"), drawn like the game's own command list:
-- paint-slash rows, orange brush on the selected row, AP costs as numbers, game fonts.
-- API (unchanged): UI.make(title, options) / UI.move(d) / UI.close() / UI.title:SetText(FText) / UI.lines, UI.sel, UI.options.
-- Option text conventions from the picker: "[n AP] Name" -> AP badge; a leading "x " = not affordable (dimmed).
UI = UI or {}
local function cls(p) local c = StaticFindObject(p); assert(c and c:IsValid(), "class missing " .. p); return c end
local TX = "/Game/UI/Resources/Textures/"
UI.T = {
  slash = TX .. "Generic/BackgroundPaint/T_Generic_PaintSlash_Text_Variation1",
  stain = TX .. "Buttons/Stain/T_UI_HoveredButtonStain",
}
local seq = 0
local function new(tree, path) seq = seq + 1; return StaticConstructObject(cls(path), tree, FName("E33V_UI_" .. seq .. "_" .. os.time())) end
local function tex(path)
  if SEL and SEL.tex then return SEL.tex(path) end
  local name = path:match("([^/]+)$"); local t = StaticFindObject(path .. "." .. name)
  if not (t and t:IsValid()) then pcall(LoadAsset, path); t = StaticFindObject(path .. "." .. name) end
  return (t and t:IsValid()) and t or nil
end
-- Game font via the select screen's style helper when available, plain sized text otherwise.
local function text(tree, s, style, color, size)
  if SEL and SEL.lib and SEL.lib.ctext then return SEL.lib.ctext(tree, s, style, color, size) end
  local t = new(tree, "/Script/UMG.TextBlock"); t.Font.Size = size or 18; t:SetText(FText(s))
  if color then t:SetColorAndOpacity({ SpecifiedColor = { R = color[1], G = color[2], B = color[3], A = 1 }, ColorUseRule = 0 }) end
  return t
end
local DARK, GOLD, WHITE, GREY = { 0.03, 0.025, 0.02, 0.92 }, { 0.72, 0.45, 0.13 }, { 0.92, 0.9, 0.86 }, { 0.32, 0.30, 0.28 }

-- Stand-in for the old title TextBlock: callers still do UI.title:SetText(FText("...")) to show a message.
UI.title = UI.title or {}
function UI.title:SetText(ft)
  local ok, s = pcall(function() return ft:ToString() end)
  UI.titleText = ok and s or tostring(ft)
  if UI.widget then UI.build() end
end

function UI.make(title, options)
  UI.titleText, UI.options, UI.sel = title, options, 1
  UI.lines = options   -- non-nil while a menu is open (key routing checks it)
  UI.build()
  return UI.widget
end

function UI.build()
  if UI.widget and UI.widget:IsValid() then UI.widget:RemoveFromParent() end
  local pc = FindFirstOf("PlayerController")
  local uw = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary"):Create(pc, cls("/Script/UMG.UserWidget"), pc)
  local tree = new(uw, "/Script/UMG.WidgetTree"); uw.WidgetTree = tree
  local canvas = new(tree, "/Script/UMG.CanvasPanel"); tree.RootWidget = canvas
  local vp = { X = 1920.0, Y = 1080.0 }
  pcall(function() local o = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary"):GetViewportSize(pc); if o and o.X then vp = o end end)
  local scale = 1.0
  pcall(function() scale = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary"):GetViewportScale(pc) end)
  local H = vp.Y / scale
  if SEL then SEL.recolor = {} end
  local function place(w, x, y, sx, sy)
    local s = canvas:AddChildToCanvas(w); s:SetPosition({ X = x, Y = y })
    if sx then s:SetAutoSize(false); s:SetSize({ X = sx, Y = sy }) else s:SetAutoSize(true) end
  end
  local function image(path, c)
    local img = new(tree, "/Script/UMG.Image"); local t = tex(path)
    if t then img:SetBrushFromTexture(t, false) end
    img:SetColorAndOpacity({ R = c[1], G = c[2], B = c[3], A = t and (c[4] or 1) or 0 })
    return img
  end

  local n = #UI.options
  local rowH, gap, w = 56, 6, 560
  local x0 = 90
  local y0 = math.max(120, H * 0.5 - (n * (rowH + gap)) / 2)
  -- title on a dark stroke
  place(image(UI.T.slash, DARK), x0 - 30, y0 - 78, w + 60, 64)
  place(text(tree, UI.titleText or "", "h3", GOLD, 20), x0, y0 - 64)
  for i, o in ipairs(UI.options) do
    local y = y0 + (i - 1) * (rowH + gap)
    local sel = i == UI.sel
    local dim = o:sub(1, 2) == "x "
    local label = dim and o:sub(3) or o
    local ap = label:match("^%[(%d+) AP%]%s*")
    if ap then label = label:gsub("^%[%d+ AP%]%s*", "") end
    -- dark stroke per row; the selected one gets the game's own button hover highlight (#10)
    place(image(UI.T.slash, DARK), x0 - 10, y, w, rowH)
    if sel then local b = SEL.hoverButton(); if b then place(b, x0 - 10, y, w, rowH); UI.hoverBtn = b end end
    place(text(tree, label, "body", dim and GREY or (sel and WHITE or { 0.62, 0.60, 0.56 }), 20), x0 + 30, y + 12)
    if ap then place(text(tree, ap, "num", dim and GREY or GOLD, 22), x0 + w - 60, y + 10) end
  end
  place(SEL.prompts(tree, "menu", 28), x0, y0 + n * (rowH + gap) + 12)   -- game-style button prompts (#9)
  uw:AddToViewport(1000)
  UI.widget = uw
  if SEL and SEL.applyColors then SEL.applyColors() end
  SEL.hoverNow(UI.hoverBtn); UI.hoverBtn = nil
end
function UI.refresh() if UI.lines then UI.build() end end
function UI.move(d) if not UI.lines then return end; UI.sel = (UI.sel - 1 + d) % #UI.options + 1; UI.build() end
function UI.close() if UI.widget and UI.widget:IsValid() then UI.widget:RemoveFromParent() end; UI.widget, UI.lines = nil, nil end
