-- E33 Versus character select (Sparking Zero style), built at runtime from plain UMG widgets.
-- Layout: Team 1 panel (left) | portrait grid with name + cost (centre) | Team 2 panel (right).
-- Keys: arrows move, Enter pick, Backspace remove last pick of the active team, Tab switch team,
--       Q/E category, F7 arena, F8 level, Space START, F6 close.
SEL = SEL or {}
-- Shorten by CHARACTERS (byte cuts split accented letters -> invalid UTF-8 -> FText "bad conversion" -> screen not drawn).
function SEL.cut(s, n)
  s = tostring(s or "")
  local ok, len = pcall(utf8.len, s)
  if not ok or not len then s = s:gsub("[\128-\255]", "?"); len = #s end
  if len <= n then return s end
  return s:sub(1, utf8.offset(s, n + 1) - 1) .. "."
end
SEL.COLS, SEL.ROWS, SEL.ICON, SEL.CELL_W = 6, 3, 104, 140
SEL.HERO_ICONS = {
  Frey = "/Game/UI/Resources/Textures/CharactersWidget/T_HUD_Gustave_512x512",
  Maelle = "/Game/UI/Resources/Textures/CharactersWidget/T_HUD_Maelle_512x512",
  Lune = "/Game/UI/Resources/Textures/CharactersWidget/T_HUD_Lune_512x512",
  Sciel = "/Game/UI/Resources/Textures/CharactersWidget/T_HUD_Sciel_512x512",
  Verso = "/Game/UI/Resources/Textures/CharactersWidget/T_HUD_CharacterPortrait_Verso",
  Monoco = "/Game/UI/Resources/Textures/CharactersWidget/T_HUD_Monoco_512x512",
}
SEL.side, SEL.cat, SEL.page, SEL.cur = SEL.side or "A", SEL.cat or 1, SEL.page or 1, SEL.cur or 1

local texCache = {}
function SEL.tex(path)
  if not path or path == "" then return nil end
  local t = texCache[path]
  if t and t:IsValid() then return t end
  local name = path:match("([^/]+)$")
  t = StaticFindObject(path .. "." .. name)
  if not t or not t:IsValid() then pcall(LoadAsset, path .. "." .. name); t = StaticFindObject(path .. "." .. name) end
  if t and t:IsValid() then texCache[path] = t; return t end
  return nil
end
local function cls(p) local c = StaticFindObject(p); assert(c and c:IsValid(), "class missing " .. p); return c end
local seq = 0
local function new(tree, path)
  seq = seq + 1
  return StaticConstructObject(cls(path), tree, FName("E33V_SEL_" .. seq .. "_" .. os.time()))
end
local function text(tree, s, r, g, b, size)
  local t = new(tree, "/Script/UMG.TextBlock")
  if size then t.Font.Size = size end   -- int leaf of the font struct, before the widget is built
  t:SetText(FText(s))
  if r then t:SetColorAndOpacity({ SpecifiedColor = { R = r, G = g, B = b, A = 1.0 }, ColorUseRule = 0 }) end
  return t
end
local function icon(tree, path, size, dim)
  local sb = new(tree, "/Script/UMG.SizeBox")
  sb:SetWidthOverride(size); sb:SetHeightOverride(size)
  local img = new(tree, "/Script/UMG.Image")
  local tx = SEL.tex(path)
  if tx then img:SetBrushFromTexture(tx, false) end
  local v = dim and 0.35 or 1.0
  img:SetColorAndOpacity({ R = v, G = v, B = v, A = tx and 1.0 or 0.25 })
  sb:AddChild(img)
  return sb
end
function SEL.unitIcon(u)
  if not u then return nil end
  if u.kind == "hero" then return SEL.HERO_ICONS[u.id] end
  return (ROSTER[u.row] or {}).portrait
end
function SEL.list()
  local c = V.CATEGORIES[SEL.cat]
  SEL.cache = SEL.cache or {}
  if not SEL.cache[SEL.cat] then SEL.cache[SEL.cat] = c.list() end
  return SEL.cache[SEL.cat]
end

-- ---------- v2 look: an opaque, game-styled screen built from the game's own UI textures and text styles ----------
local TX = "/Game/UI/Resources/Textures/"
SEL.T = {
  bg = TX .. "GameMenu/Backgrounds/T_UI_GM_PlaceholderBackground",
  edgeL = TX .. "RestMenu/T_UI_SavePointLeftBackground", edgeR = TX .. "RestMenu/T_UI_SavePointRightBackground",
  pattern = TX .. "GameMenu/T_GM_Background_PaternFade",
  line = TX .. "GameMenu/Pictos/T_UI_PictoHorizontalLine",
  card = TX .. "Buttons/Generic/T_UI_CharacterSelectionCardBackground",
  stain = TX .. "Buttons/Stain/T_UI_CharacterSelectorButtonStain",
  slot = TX .. "Buttons/Generic/T_UI_TeamOverviewCartridgeBackground",
  slash = TX .. "Generic/BackgroundPaint/T_Generic_PaintSlash_Text_Variation1",
  detail = TX .. "Exploration/Loot/T_UI_LootCustomizationBackground",
  portraitBG = TX .. "CharactersWidget/BattlePortraits/T_HUD_BattlePortraitCharacterBG",
}
SEL.HERO_ART = {
  Frey = TX .. "CharactersWidget/VictoryPortraits/T_HUD_VictoryScreen_GUSTAVE", Maelle = TX .. "CharactersWidget/VictoryPortraits/T_HUD_VictoryScreen_MAELLE",
  Lune = TX .. "CharactersWidget/VictoryPortraits/T_HUD_VictoryScreen_LUNE", Sciel = TX .. "CharactersWidget/VictoryPortraits/T_HUD_VictoryScreen_SCIEL",
  Verso = TX .. "CharactersWidget/VictoryPortraits/T_HUD_VictoryScreen_VERSO", Monoco = TX .. "CharactersWidget/VictoryPortraits/T_HUD_VictoryScreen_MONOCO",
}
SEL.CAT_SHORT = { "Heroes", "Chroma", "Bosses", "Elites", "All" }
local ST = "/Game/UI/Resources/Styles/Text/"
SEL.STYLE = {
  first = ST .. "Heading/FirstLetter/CTS_H1First_TitleOutline", title = ST .. "Heading/Titles/CTS_H1_TitleOutline",
  h2 = ST .. "Heading/CTS_H2_Outline", h3 = ST .. "Heading/CTS_H3_Outline",
  body = ST .. "Body/Outline/CTS_B2_Outline", small = ST .. "Body/Outline/CTS_B4_Outline", num = ST .. "NumericalValues/CTS_NSans2_Outline",
}
local styleCache = {}
function SEL.style(path)
  if styleCache[path] ~= nil then return styleCache[path] or nil end
  local name = path:match("([^/]+)$"); local full = path .. "." .. name .. "_C"
  local c = StaticFindObject(full)
  if not (c and c:IsValid()) then pcall(LoadAsset, path); c = StaticFindObject(full) end
  styleCache[path] = (c and c:IsValid()) and c or false
  return styleCache[path] or nil
end
-- Game-styled text (CommonTextBlock + CTS style); falls back to a sized TextBlock if the style is missing.
-- Game-styled text. A CommonTextBlock forces its style colour on every refresh, so coloured text uses a plain
-- TextBlock that copies the style's font leaves (font, typeface, size, outline, spacing) instead.
local function ctext(tree, s, style, color, size)
  local sc = SEL.style(SEL.STYLE[style] or style)
  local t
  if sc and not color then
    t = new(tree, "/Script/CommonUI.CommonTextBlock"); t:SetStyle(sc)
  else
    t = new(tree, "/Script/UMG.TextBlock"); t.Font.Size = size or 18
    if sc then pcall(function()
      local f = sc:GetCDO().Font
      t.Font.FontObject = f.FontObject; t.Font.TypefaceFontName = f.TypefaceFontName; t.Font.Size = f.Size
      t.Font.LetterSpacing = f.LetterSpacing
      t.Font.OutlineSettings.OutlineSize = f.OutlineSettings.OutlineSize
      local oc = f.OutlineSettings.OutlineColor
      t.Font.OutlineSettings.OutlineColor.R = oc.R; t.Font.OutlineSettings.OutlineColor.G = oc.G
      t.Font.OutlineSettings.OutlineColor.B = oc.B; t.Font.OutlineSettings.OutlineColor.A = oc.A
    end) end
  end
  t:SetText(FText(s))
  if color then t:SetColorAndOpacity({ SpecifiedColor = { R = color[1], G = color[2], B = color[3], A = color[4] or 1.0 }, ColorUseRule = 0 }) end
  return t
end
-- Linear colour values (UMG tints are linear: sRGB gold 0.86,0.70,0.40 ~ linear 0.72,0.45,0.13)
SEL._ctext = ctext
local GOLD, WHITE, GREY, RED = { 0.72, 0.45, 0.13 }, { 0.9, 0.88, 0.84 }, { 0.30, 0.29, 0.27 }, { 0.70, 0.07, 0.04 }
SEL.COLORS = { GOLD = GOLD, WHITE = WHITE, GREY = GREY, RED = RED }

function SEL.build()
  if SEL.widget and SEL.widget:IsValid() then SEL.widget:RemoveFromParent() end
  if not SEL.active then SEL.widget = nil; return end   -- never draw a closed screen
  SEL.recolor = {}
  local pc = FindFirstOf("PlayerController")
  local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
  local uw = wbl:Create(pc, cls("/Script/UMG.UserWidget"), pc)
  local tree = new(uw, "/Script/UMG.WidgetTree")
  uw.WidgetTree = tree
  local canvas = new(tree, "/Script/UMG.CanvasPanel")
  tree.RootWidget = canvas
  local vp = { X = 1920.0, Y = 1080.0 }
  pcall(function() local o = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary"):GetViewportSize(pc); if o and o.X then vp = o end end)
  local scale = 1.0
  pcall(function() scale = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary"):GetViewportScale(pc) end)
  local W, H = vp.X / scale, vp.Y / scale
  local function place(w, x, y, sx, sy)
    local s = canvas:AddChildToCanvas(w); s:SetPosition({ X = x, Y = y })
    if sx then s:SetAutoSize(false); s:SetSize({ X = sx, Y = sy }) else s:SetAutoSize(true) end
    return s
  end
  local function image(path, tint)
    local img = new(tree, "/Script/UMG.Image")
    local t = SEL.tex(path)
    if t then img:SetBrushFromTexture(t, false) end
    local c = tint or { 1, 1, 1, 1 }
    img:SetColorAndOpacity({ R = c[1], G = c[2], B = c[3], A = t and (c[4] or 1) or 0 })
    return img
  end

  -- backdrop (opaque: hides the world and the HUD)
  local black = new(tree, "/Script/UMG.Image"); black:SetColorAndOpacity({ R = 0.01, G = 0.01, B = 0.012, A = 1.0 })
  place(black, 0, 0, W, H)
  place(image(SEL.T.bg), 0, 0, W, H)
  place(image(SEL.T.edgeL, { 1, 1, 1, 0.95 }), 0, 0, H * 0.55, H)
  place(image(SEL.T.edgeR, { 1, 1, 1, 0.95 }), W - H * 0.28, 0, H * 0.28, H)
  place(image(SEL.T.pattern, { 0.93, 0.80, 0.52, 0.10 }), W * 0.25, 0, W * 0.75, H)

  -- title: "V" + "ersus" in the game's heading styles, with the gold divider line
  local title = new(tree, "/Script/UMG.HorizontalBox")
  title:AddChildToHorizontalBox(ctext(tree, "V", "first", nil, 40))
  title:AddChildToHorizontalBox(ctext(tree, "ersus", "title", nil, 30))
  place(title, 64, 28)
  place(image(SEL.T.line, { 1, 1, 1, 0.9 }), 30, 84, 520, 62)

  -- category tabs (paint slash behind the active one)
  local colL, colR = 40, W - 470
  local gx0, gx1 = 540, W - 500
  local tabs = new(tree, "/Script/UMG.HorizontalBox")
  for i, lab in ipairs(SEL.CAT_SHORT) do
    local ov = new(tree, "/Script/UMG.Overlay")
    local sb = new(tree, "/Script/UMG.SizeBox"); sb:SetWidthOverride(150); sb:SetHeightOverride(44)
    sb:AddChild(image(SEL.T.slash, i == SEL.cat and { 0.08, 0.07, 0.06, 0.95 } or { 0, 0, 0, 0 }))
    ov:AddChildToOverlay(sb)
    local slot = ov:AddChildToOverlay(ctext(tree, lab, "body", i == SEL.cat and GOLD or GREY, 18))
    slot:SetHorizontalAlignment(2); slot:SetVerticalAlignment(2)
    tabs:AddChildToHorizontalBox(ov)
  end
  place(ctext(tree, "Q", "small", GREY, 14), gx0 - 24, 44)
  place(tabs, gx0, 32)
  place(ctext(tree, "E", "small", GREY, 14), gx0 + 150 * #SEL.CAT_SHORT + 8, 44)

  -- team columns
  local function teamPanel(side, x)
    local active = SEL.side == side
    local head = new(tree, "/Script/UMG.HorizontalBox")
    local label = side == "A" and "Team 1" or "Team 2"
    if SEL.online then
      label = (side == SEL.online.me) and "You" or (SEL.cut(NET.status.peer or "Opponent", 12))
      if SEL.online.ready[side] then label = label .. "  -  Ready" end
    end
    head:AddChildToHorizontalBox(ctext(tree, label, "h2", (SEL.online and SEL.online.ready[side]) and WHITE or (active and GOLD or GREY), 26))
    head:AddChildToHorizontalBox(ctext(tree, ("    %d / %d"):format(V.teamCost(side), V.CAP), "num", active and WHITE or GREY, 20))
    place(head, x + 14, 150)
    for i = 1, 3 do
      local u = V.cfg[side][i]
      local y = 200 + (i - 1) * 168
      place(image(SEL.T.slot, u and { 1, 1, 1, 1 } or { 1, 1, 1, 0.35 }), x, y, 430, 154)
      if u then
        place(image(SEL.T.portraitBG, { 1, 1, 1, 0.8 }), x + 18, y + 14, 126, 126)
        place(image(SEL.unitIcon(u)), x + 24, y + 18, 116, 116)
        local nm = u.name or u.label or "?"
        nm = SEL.cut(nm, 17)
        place(ctext(tree, nm, "body", WHITE, 20), x + 160, y + 44)
        place(ctext(tree, ("Cost %d"):format(V.cost(u)), "small", GOLD, 15), x + 160, y + 84)
        local pool = u.kind == "enemy" and WH and WH.rowMoves(u.row)
        if pool and #pool > WH.MAX_SKILLS then
          place(ctext(tree, ("Moves %d / %d   (R)"):format(#(u.loadout or {}), #pool), "small", GREY, 14), x + 160, y + 108)
        end
      else
        place(ctext(tree, "Empty", "body", GREY, 18), x + 170, y + 60)
      end
    end
  end
  teamPanel("A", colL)
  teamPanel("B", colR)

  if SEL.lo then
  -- loadout: pick up to 6 moves for a unit with a bigger move pool (they become its skill wheel in battle)
  local lo = SEL.lo
  local u = V.cfg[lo.side][lo.slot]
  local nm = u and (u.name or u.label) or "?"
  place(ctext(tree, "Moves  -  " .. nm, "h2", GOLD, 26), gx0, 104)
  place(ctext(tree, ("%d / %d chosen   (the wheel holds %d)"):format(SEL.loCount(), WH.MAX_SKILLS, WH.MAX_SKILLS), "body", WHITE, 17), gx0, 146)
  local cols = 2; local cw = math.floor(((gx1 - gx0) - 20) / cols); local rh = 54
  local perCol = math.max(1, math.floor((H - 300 - 196) / rh))
  SEL.loPerCol = perCol
  for i, m in ipairs(lo.moves) do
    local col = math.floor((i - 1) / perCol); local row = (i - 1) % perCol
    if col < cols then
      local x = gx0 + col * (cw + 20); local y = 190 + row * rh
      local on = lo.chosen[m.prop]; local sel = i == lo.cur
      place(image(SEL.T.slot, sel and { 1, 0.85, 0.55, 1 } or (on and { 1, 1, 1, 0.95 } or { 1, 1, 1, 0.3 })), x, y, cw, rh - 6)
      if sel then
        for _, r in ipairs({ { x - 3, y - 3, cw + 6, 2 }, { x - 3, y + rh - 7, cw + 6, 2 } }) do
          local bar = new(tree, "/Script/UMG.Image"); bar:SetColorAndOpacity({ R = 0.72, G = 0.45, B = 0.13, A = 1 }); place(bar, r[1], r[2], r[3], r[4])
        end
      end
      local label = SEL.cut(m.label, 26) .. ((m.phase and m.phase > 1) and ("  (Phase " .. m.phase .. ")") or "")
      place(ctext(tree, (on and "+  " or "    ") .. label, "body", on and GOLD or (sel and WHITE or GREY), 17), x + 18, y + 12)
      place(ctext(tree, m.cost .. " AP", "num", on and GOLD or GREY, 17), x + cw - 70, y + 12)
    end
  end
  elseif SEL.arenaMode then
  -- arena grid: locations with their artwork (F7 toggles)
  local arenas = SEL.arenaList()
  local acols, arows, agap = 4, 3, 14
  local aperPage = acols * arows
  local apages = math.max(1, math.ceil(#arenas / aperPage))
  SEL.apage = math.max(1, math.min(SEL.apage or 1, apages))
  local afirst = (SEL.apage - 1) * aperPage
  SEL.aonPage = math.max(0, math.min(aperPage, #arenas - afirst))
  SEL.acur = math.max(1, math.min(SEL.acur or 1, math.max(1, SEL.aonPage)))
  local aw = math.floor(((gx1 - gx0) - agap * (acols - 1)) / acols)
  local ah = math.floor(aw * 0.54)
  for k = 1, SEL.aonPage do
    local ar = arenas[afirst + k]
    local cx = gx0 + ((k - 1) % acols) * (aw + agap)
    local cy = 110 + math.floor((k - 1) / acols) * (ah + 34 + agap)
    local sel = k == SEL.acur
    local chosen = (V.cfg.arenaId or false) == (ar.id or false)
    if sel then
      for _, r in ipairs({ { cx - 5, cy - 5, aw + 10, 3 }, { cx - 5, cy + ah + 30, aw + 10, 3 }, { cx - 5, cy - 5, 3, ah + 38 }, { cx + aw + 2, cy - 5, 3, ah + 38 } }) do
        local bar = new(tree, "/Script/UMG.Image"); bar:SetColorAndOpacity({ R = 0.72, G = 0.45, B = 0.13, A = 1 })
        place(bar, r[1], r[2], r[3], r[4])
      end
    end
    if ar.icon then place(image(ar.icon), cx, cy, aw, ah)
    else local blk = new(tree, "/Script/UMG.Image"); blk:SetColorAndOpacity({ R = 0.03, G = 0.03, B = 0.03, A = 0.9 }); place(blk, cx, cy, aw, ah) end
    place(ctext(tree, SEL.cut((chosen and "> " or "") .. SEL.arenaName(ar), 24), "small", (sel or chosen) and GOLD or WHITE, 13), cx + 4, cy + ah + 6)
  end
  place(ctext(tree, ("%d / %d"):format(SEL.apage, apages), "small", GREY, 14), gx1 - 60, 110 + arows * (ah + 34 + agap))
  -- detail: big preview of the highlighted location
  local ca = arenas[afirst + SEL.acur]
  local dy = H - 300
  place(image(SEL.T.detail, { 1, 1, 1, 0.97 }), gx0 - 10, dy, (gx1 - gx0) + 20, 230)
  if ca then
    if ca.icon then place(image(ca.icon), gx0 + 30, dy + 20, 350, 189) end
    place(ctext(tree, SEL.arenaName(ca), "h2", GOLD, 26), gx0 + 400, dy + 36)
    place(ctext(tree, ca.id and "Both players travel here for the fight" or "Fight where the loaded save stands", "body", WHITE, 17), gx0 + 400, dy + 86)
    place(ctext(tree, "Enter choose    Backspace / F7 back", "small", GREY, 15), gx0 + 400, dy + 130)
  end
  else
  -- card grid
  local list = SEL.list()
  local perPage = SEL.COLS * SEL.ROWS
  local pages = math.max(1, math.ceil(#list / perPage))
  SEL.page = math.max(1, math.min(SEL.page, pages))
  local first = (SEL.page - 1) * perPage
  SEL.onPage = math.max(0, math.min(perPage, #list - first))
  SEL.cur = math.max(1, math.min(SEL.cur, math.max(1, SEL.onPage)))
  local gap = 14
  local cw = math.floor(math.min(140, ((gx1 - gx0) - gap * (SEL.COLS - 1)) / SEL.COLS))
  local ch = math.floor(cw * 1.40)
  local left = V.CAP - V.teamCost(SEL.side, SEL.slotToFill())
  for k = 1, SEL.onPage do
    local u = list[first + k]
    local cx = gx0 + ((k - 1) % SEL.COLS) * (cw + gap)
    local cy = 110 + math.floor((k - 1) / SEL.COLS) * (ch + gap)
    local sel = k == SEL.cur
    local tooExpensive = V.cost(u) > left
    if sel then
      place(image(SEL.T.stain, { 0.93, 0.78, 0.45, 0.55 }), cx - 34, cy - 30, cw + 68, ch + 60)
      -- gold rim: four thin solid bars (a texture tint cannot turn the black card art gold)
      for _, r in ipairs({ { cx - 5, cy - 5, cw + 10, 3 }, { cx - 5, cy + ch + 2, cw + 10, 3 }, { cx - 5, cy - 5, 3, ch + 10 }, { cx + cw + 2, cy - 5, 3, ch + 10 } }) do
        local bar = new(tree, "/Script/UMG.Image"); bar:SetColorAndOpacity({ R = 0.72, G = 0.45, B = 0.13, A = 1 })
        place(bar, r[1], r[2], r[3], r[4])
      end
    end
    place(image(SEL.T.card, tooExpensive and { 0.55, 0.5, 0.5, 1 } or { 1, 1, 1, 1 }), cx, cy, cw, ch)
    local ps = cw - 22
    place(image(SEL.unitIcon(u), tooExpensive and { 0.4, 0.4, 0.4, 1 } or { 1, 1, 1, 1 }), cx + 11, cy + 10, ps, ps)
    local nm = (u.name or u.label or "?"):gsub("^%[%d+%] ", "")
    nm = SEL.cut(nm, 15)
    place(ctext(tree, nm, "small", sel and GOLD or WHITE, 12), cx + 8, cy + ps + 14)
    place(ctext(tree, tostring(V.cost(u)), "num", tooExpensive and RED or GOLD, 18), cx + cw - 30, cy + ch - 34)
  end
  place(ctext(tree, ("%d / %d"):format(SEL.page, pages), "small", GREY, 14), gx0 + (cw + gap) * SEL.COLS - 70, 110 + SEL.ROWS * (ch + gap))

  -- detail panel: highlighted unit
  local cu = list[first + SEL.cur]
  local dy = H - 300
  place(image(SEL.T.detail, { 1, 1, 1, 0.97 }), gx0 - 10, dy, (gx1 - gx0) + 20, 230)
  if cu then
    local art = cu.kind == "hero" and SEL.HERO_ART[cu.id] or SEL.unitIcon(cu)
    place(image(art), gx0 + 20, dy + 15, 200, 200)
    local nm = (cu.name or cu.label or "?"):gsub("^%[%d+%] ", "")
    place(ctext(tree, nm, "h2", GOLD, 26), gx0 + 240, dy + 30)
    local d = cu.kind == "enemy" and ROSTER[cu.row] or nil
    local kind = cu.kind == "hero" and "Expeditioner - your own build" or ((d and d.arch or "?") .. ((d and d.boss and d.arch ~= "Boss") and "  -  Boss" or ""))
    local pool = cu.kind == "enemy" and WH and WH.rowMoves(cu.row)
    if pool then kind = kind .. ("      %d moves"):format(#pool) end
    place(ctext(tree, kind, "body", WHITE, 18), gx0 + 240, dy + 80)
    place(ctext(tree, ("Cost %d"):format(V.cost(cu)), "num", V.cost(cu) > left and RED or GOLD, 20), gx0 + 240, dy + 120)
    if d then
      local hp = (V.HP_BASE or 0.6) + (V.HP_PER_COST or 0.2) * V.cost(cu)
      local atk = V.ATK_BASE + V.ATK_PER_COST * V.cost(cu)
      place(ctext(tree, ("HP x%.1f    ATK x%.2f    of a hero"):format(hp, atk), "small", GREY, 15), gx0 + 240, dy + 172)
    end
  end

  end
  -- footer
  local keysHelp = SEL.lo and "Arrows move   Enter add / remove   Space or Backspace done" or SEL.online and "Arrows move   Enter pick   Backspace remove   Space ready" or "Arrows move   Enter pick   Backspace remove   Tab team   Space start   F6 close"
  local cur = V.cfg.arenaId and V.arenaById(V.cfg.arenaId)
  local footer = ("Arena: %s  (F7)        Level %s  (F8)        " .. keysHelp)
    :format(cur and SEL.arenaName(cur) or "save location", V.cfg.level and tostring(V.cfg.level) or "auto")
  place(ctext(tree, footer, "small", GREY, 14), gx0, H - 52)
  if SEL.msg then place(ctext(tree, SEL.msg, "body", RED, 18), gx0, H - 340); SEL.msg = nil end

  uw:AddToViewport(1100)
  SEL.widget = uw
  SEL.applyColors()
end

function SEL.applyColors()
  for _, rc in ipairs(SEL.recolor or {}) do
    local c = rc[2]
    pcall(function() if rc[1]:IsValid() then rc[1]:SetColorAndOpacity({ SpecifiedColor = { R = c[1], G = c[2], B = c[3], A = c[4] or 1.0 }, ColorUseRule = 0 }) end end)
  end
end
-- Arena list: "save location" (no travel) first, then every location from arena_data.lua.
function SEL.arenaList()
  if not SEL._arenas then
    SEL._arenas = { { id = nil, name = "Save location" } }
    for _, a in ipairs(ARENAS or {}) do SEL._arenas[#SEL._arenas + 1] = a end
  end
  return SEL._arenas
end
-- The game's own localized location name (string table), English fallback.
local arenaNames = {}
function SEL.arenaName(a)
  if not a.id then return a.name end
  if arenaNames[a.id] then return arenaNames[a.id] end
  local ok, t = pcall(function() return StaticFindObject("/Script/Engine.Default__KismetTextLibrary"):TextFromStringTable(FName(a.st), a.key):ToString() end)
  arenaNames[a.id] = (ok and t and t ~= "") and t or a.name
  return arenaNames[a.id]
end
function SEL.arenaKey(k)
  local acols, aperPage = 4, 12
  if k == "LEFT" or k == "RIGHT" then
    local n = SEL.acur + (k == "LEFT" and -1 or 1)
    if n < 1 and SEL.apage > 1 then SEL.apage = SEL.apage - 1; SEL.acur = aperPage
    elseif n > SEL.aonPage and SEL.aonPage == aperPage then SEL.apage = SEL.apage + 1; SEL.acur = 1
    else SEL.acur = math.max(1, math.min(SEL.aonPage, n)) end
  elseif k == "UP" or k == "DOWN" then
    local n = SEL.acur + (k == "UP" and -acols or acols)
    if n < 1 then if SEL.apage > 1 then SEL.apage = SEL.apage - 1; SEL.acur = n + aperPage end
    elseif n > SEL.aonPage then if SEL.aonPage == aperPage then SEL.apage = SEL.apage + 1; SEL.acur = math.max(1, n - aperPage) end
    else SEL.acur = n end
  elseif k == "ENTER" then
    local a = SEL.arenaList()[(SEL.apage - 1) * aperPage + SEL.acur]
    V.cfg.arenaId = a and a.id or nil
    SEL.arenaMode = false
    if SEL.online then ONLINE.sendSettings() end
  elseif k == "BACK" or k == "F7" then SEL.arenaMode = false
  end
  SEL.build()
end
-- ---------- loadout ----------
function SEL.loCount() local n = 0; for _ in pairs(SEL.lo and SEL.lo.chosen or {}) do n = n + 1 end; return n end
function SEL.openLoadout(side, slot)
  local u = V.cfg[side][slot]; if not (u and u.kind == "enemy") then return false end
  local moves = WH.rowMoves(u.row); if not (moves and #moves > WH.MAX_SKILLS) then return false end
  u.loadout = u.loadout or WH.defaultLoadoutFor(u.row)
  local chosen = {}; for _, p in ipairs(u.loadout) do chosen[p] = true end
  SEL.lo = { side = side, slot = slot, moves = moves, chosen = chosen, cur = 1 }
  return true
end
function SEL.closeLoadout()
  local lo = SEL.lo; SEL.lo = nil
  local u = lo and V.cfg[lo.side][lo.slot]; if not u then return end
  local out = {}
  for _, m in ipairs(lo.moves) do if lo.chosen[m.prop] then out[#out + 1] = m.prop end end   -- pool order = wheel order
  u.loadout = out
end
function SEL.loKey(k)
  local lo = SEL.lo; local n = #lo.moves
  if k == "UP" or k == "DOWN" then lo.cur = (lo.cur - 1 + (k == "UP" and -1 or 1)) % n + 1; WH.sfx("move")
  elseif k == "LEFT" or k == "RIGHT" then
    local c = lo.cur + (k == "LEFT" and -1 or 1) * (SEL.loPerCol or 8)
    if c >= 1 and c <= n then lo.cur = c; WH.sfx("move") end
  elseif k == "ENTER" then
    local m = lo.moves[lo.cur]
    if lo.chosen[m.prop] then lo.chosen[m.prop] = nil; WH.sfx("remove")
    elseif SEL.loCount() >= WH.MAX_SKILLS then SEL.msg = "The wheel holds 6 moves: remove one first"; WH.sfx("deny")
    else lo.chosen[m.prop] = true; WH.sfx("add") end
  elseif k == "SPACE" or k == "BACK" then
    if SEL.loCount() == 0 then SEL.msg = "Choose at least one move"; WH.sfx("deny")
    else SEL.closeLoadout(); WH.sfx("ok"); if SEL.online then ONLINE.sendTeam() end end
  end
  SEL.build()
end
function SEL.slotToFill() for i = 1, 3 do if not V.cfg[SEL.side][i] then return i end end return nil end
-- mode "title": opened from the title VERSUS button before any save is loaded (Sparking Zero flow);
-- mode "world": opened in a loaded world (F6 / L3+R3).
function SEL.open(mode)
  SEL.mode = mode or "world"
  if SEL.mode == "title" then SEL.hideTitle(true) end
  E33V_TITLE_PAD = SEL.mode == "title"
  UI.close()
  V.addPhaseEntries()
  if SEL.mode ~= "title" then V.cfg.level = V.cfg.level or V.avgHeroLevel() end
  SEL.cache = nil
  SEL.active = true
  SEL.build()
end
function SEL.close()
  SEL.active = false
  if SEL.widget and SEL.widget:IsValid() then SEL.widget:RemoveFromParent() end
  SEL.widget = nil
  E33V_TITLE_PAD = false
  if SEL.mode == "title" then SEL.hideTitle(false) end
end
-- While the select screen covers the title, collapse the game's main menu so its buttons cannot take Enter/arrows.
function SEL.hideTitle(hide)
  for _, mm in ipairs(FindAllOf("WBP_MM_MainMenu_C") or {}) do
    if mm:IsValid() and mm:GetFullName():find("/Engine/Transient", 1, true) then pcall(function() mm:SetVisibility(hide and 1 or 4) end) end
  end
end
function SEL.arenaCount()
  if SEL.mode == "title" then return 19 end   -- arenas only exist in a loaded level; checked again before the fight
  return math.max(1, #(FindAllOf("BP_BattleMap_C") or {}))
end
function SEL.key(k)
  local perPage = SEL.COLS * SEL.ROWS
  local on = SEL.online
  if on then
    SEL.side = on.me
    if k == "TAB" then return end
    if (k == "F7" or k == "F8") and not ONLINE.isHost() then SEL.msg = "The host chooses arena and level"; SEL.build(); return end
    if k == "SPACE" then ONLINE.toggleReady(); if SEL.active then SEL.build() end; return end   -- Ready may start the match (closes this screen)
    if k == "BACK" and not V.cfg[on.me][1] then NET.send({ t = "leave" }); NET.status.room = nil; SEL.online = nil; SEL.close(); ONLINE.lobby(); return end
    if k == "F6" then return end
  end
  if SEL.lo then SEL.loKey(k); return end
  if SEL.arenaMode then
    WH.sfx(k == "ENTER" and "ok" or ((k == "BACK" or k == "F7") and "back" or "move"))
    SEL.arenaKey(k); return
  end
  local before = on and JSON.encode(ONLINE.packTeam(on.me))
  if k == "LEFT" or k == "RIGHT" or k == "UP" or k == "DOWN" then WH.sfx("move") end
  if k == "LEFT" or k == "RIGHT" then
    local d = k == "LEFT" and -1 or 1
    local n = SEL.cur + d
    if n < 1 and SEL.page > 1 then SEL.page = SEL.page - 1; SEL.cur = perPage
    elseif n > SEL.onPage and SEL.onPage == perPage then SEL.page = SEL.page + 1; SEL.cur = 1
    else SEL.cur = math.max(1, math.min(SEL.onPage, n)) end
  elseif k == "UP" or k == "DOWN" then
    local n = SEL.cur + (k == "UP" and -SEL.COLS or SEL.COLS)
    if n < 1 then if SEL.page > 1 then SEL.page = SEL.page - 1; SEL.cur = n + perPage end
    elseif n > SEL.onPage then if SEL.onPage == perPage then SEL.page = SEL.page + 1; SEL.cur = n - perPage end
    else SEL.cur = n end
  elseif k == "Q" or k == "E" then
    SEL.cat = (SEL.cat - 1 + (k == "Q" and -1 or 1)) % #V.CATEGORIES + 1; SEL.page, SEL.cur = 1, 1; WH.sfx("tab")
  elseif k == "TAB" then SEL.side = SEL.side == "A" and "B" or "A"; WH.sfx("tab")
  elseif k == "ENTER" then
    local slot = SEL.slotToFill()
    local u = SEL.list()[(SEL.page - 1) * perPage + SEL.cur]
    if not slot then SEL.msg = "Team is full (Backspace removes the last pick)"
    elseif u and V.teamCost(SEL.side, slot) + V.cost(u) > V.CAP then
      SEL.msg = ("Too expensive: %d pts left"):format(V.CAP - V.teamCost(SEL.side, slot))
    elseif u then
      local c = {}; for kk, vv in pairs(u) do c[kk] = vv end   -- own copy per slot (it carries the loadout)
      V.cfg[SEL.side][slot] = c
      WH.sfx("add")
      SEL.openLoadout(SEL.side, slot)
    end
    if SEL.msg then WH.sfx("deny") end
  elseif k == "BACK" then
    if not V.cfg[SEL.side][1] and SEL.mode == "title" then WH.sfx("back"); SEL.close(); return end   -- B on an empty team = back to the title
    for i = 3, 1, -1 do if V.cfg[SEL.side][i] then V.cfg[SEL.side][i] = nil; WH.sfx("remove"); break end end
  elseif k == "R" then   -- edit the moves of the team's last unit with a big move pool
    local opened = false
    for i = 3, 1, -1 do if not opened and SEL.openLoadout(SEL.side, i) then opened = true end end
    WH.sfx(opened and "open" or "deny")
  elseif k == "F7" then SEL.arenaMode = true; WH.sfx("open")
  elseif k == "F8" then WH.sfx("tab"); V.cfg.level = V.cfg.level and (V.cfg.level < 95 and V.cfg.level + 5 or nil) or 20   -- ... 95 -> auto -> 20
  elseif k == "SPACE" then
    if not (V.cfg.A[1] and V.cfg.B[1]) then SEL.msg = "Each team needs at least one unit"; WH.sfx("deny")
    elseif SEL.mode == "title" then WH.sfx("start"); SEL.close(); V.startFromTitle(); return
    else
      -- in a world: same path as after a load (arena travel, hero checks, then the fight)
      WH.sfx("start"); SEL.close(); V.travelTried = nil; V.fightWhenReady = os.clock(); V.worldSeen = os.clock() - 3; return
    end
  elseif k == "F6" then WH.sfx("close"); SEL.close(); return
  end
  if on and SEL.online then
    if JSON.encode(ONLINE.packTeam(on.me)) ~= before then ONLINE.sendTeam() end
    if k == "F7" or k == "F8" then ONLINE.sendSettings() end
  end
  SEL.build()
end

-- Shared drawing helpers for the other game-styled screens (screens.lua).
SEL.lib = { new = new, cls = cls }
SEL.lib.ctext = function(...) return SEL._ctext(...) end
