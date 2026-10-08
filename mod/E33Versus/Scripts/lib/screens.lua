-- E33 Versus generic game-styled menu screen (requires select.lua for its drawing helpers and textures).
-- SCR.show{ title = "Online", items = { {label, sub, on = fn, input = {value, hint}} ... }, info = {lines},
--           back = fn, footer = "..." }
-- Keys (through V.key): Up/Down move, Enter activate (on an input: type, Enter again to confirm), Backspace/F6 back.
SCR = SCR or {}
local function C(name) return SEL.COLORS[name] end

function SCR.show(def)
  SCR.def, SCR.active = def, true
  SCR.sel = math.max(1, math.min(def.sel or SCR.sel or 1, #def.items))
  SCR.typing = nil
  SEL.hideTitle(true)
  E33V_TITLE_PAD = true
  SCR.build()
end
function SCR.close()
  SCR.active = false
  if SCR.widget and SCR.widget:IsValid() then SCR.widget:RemoveFromParent() end
  SCR.widget, SCR.boxes = nil, nil
  E33V_TITLE_PAD = SEL.active or false
end
-- Leave the menus entirely (back to the title).
function SCR.exit() SCR.close(); SEL.hideTitle(false) end
-- Rebuild in place (e.g. after a network event) keeping the cursor.
function SCR.refresh() if SCR.active and not SCR.typing then SCR.build() end end

function SCR.build()
  local L = SEL.lib
  local new, ctext = L.new, L.ctext
  if SCR.widget and SCR.widget:IsValid() then SCR.widget:RemoveFromParent() end
  local def = SCR.def
  local pc = FindFirstOf("PlayerController")
  local uw = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary"):Create(pc, L.cls("/Script/UMG.UserWidget"), pc)
  local tree = new(uw, "/Script/UMG.WidgetTree"); uw.WidgetTree = tree
  local canvas = new(tree, "/Script/UMG.CanvasPanel"); tree.RootWidget = canvas
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
  local function bar(x, y, w, h, c)
    local b = new(tree, "/Script/UMG.Image"); b:SetColorAndOpacity({ R = c[1], G = c[2], B = c[3], A = 1 }); place(b, x, y, w, h)
  end

  -- backdrop (same family as the select screen)
  local black = new(tree, "/Script/UMG.Image"); black:SetColorAndOpacity({ R = 0.01, G = 0.01, B = 0.012, A = 1.0 })
  place(black, 0, 0, W, H)
  place(image(SEL.T.bg), 0, 0, W, H)
  place(image(SEL.T.edgeL, { 1, 1, 1, 0.95 }), 0, 0, H * 0.55, H)
  place(image(SEL.T.edgeR, { 1, 1, 1, 0.95 }), W - H * 0.28, 0, H * 0.28, H)
  place(image(SEL.T.pattern, { 0.93, 0.80, 0.52, 0.10 }), W * 0.25, 0, W * 0.75, H)

  -- title
  local t = def.title or "Versus"
  local title = new(tree, "/Script/UMG.HorizontalBox")
  title:AddChildToHorizontalBox(ctext(tree, t:sub(1, 1), "first", nil, 40))
  title:AddChildToHorizontalBox(ctext(tree, t:sub(2), "title", nil, 30))
  place(title, 64, 28)
  place(image(SEL.T.line, { 1, 1, 1, 0.9 }), 30, 84, 520, 62)
  if def.subtitle then place(ctext(tree, def.subtitle, "body", C("GREY"), 18), 70, 150) end

  -- items
  SCR.boxes = {}
  local x0, y0, iw, ih = 90, 210, 640, 96
  for i, it in ipairs(def.items) do
    local y = y0 + (i - 1) * (ih + 14)
    local sel = i == SCR.sel
    place(image(SEL.T.slot, it.disabled and { 1, 1, 1, 0.35 } or { 1, 1, 1, 1 }), x0, y, iw, ih)
    if sel then   -- the game's own hover highlight (#10)
      local b = SEL.hoverButton()
      if b then place(b, x0, y, iw, ih); SCR.hoverBtn = b end
    end
    local col = it.disabled and C("GREY") or (sel and C("WHITE") or { 0.62, 0.60, 0.56 })
    if it.input then
      -- our own text field (an engine text box never gets keyboard focus under the game's menu system)
      local typing = SCR.typing == i
      place(ctext(tree, it.label, "small", sel and C("GOLD") or C("GREY"), 15), x0 + 40, y + 10)
      local field = new(tree, "/Script/UMG.Image")
      field:SetColorAndOpacity(typing and { R = 0.10, G = 0.07, B = 0.03, A = 0.95 } or { R = 0.02, G = 0.02, B = 0.02, A = 0.85 })
      place(field, x0 + 36, y + 40, iw - 90, 40)
      local v = it.input.value or ""
      local shown = (v == "" and not typing) and (it.input.hint or "") or (v .. (typing and "_" or ""))
      place(ctext(tree, shown, "body", (v == "" and not typing) and C("GREY") or C("WHITE"), 18), x0 + 48, y + 46)
    else
      place(ctext(tree, it.label, "body", col, 22), x0 + 40, y + (it.sub and 16 or 30))
      if it.sub then place(ctext(tree, it.sub, "small", C("GREY"), 15), x0 + 40, y + 56) end
    end
  end

  -- info panel (connection status, room, messages)
  if def.info and #def.info > 0 then
    local px, py, pw, ph = math.max(x0 + iw + 80, W * 0.48), 210, math.min(720, W * 0.42), 360
    place(image(SEL.T.detail, { 1, 1, 1, 0.97 }), px, py, pw, ph)
    for i, line in ipairs(def.info) do
      local txt, col = line, C("WHITE")
      if type(line) == "table" then txt, col = line[1], C(line[2]) or C("WHITE") end
      place(ctext(tree, txt, i == 1 and "h2" or "body", i == 1 and C("GOLD") or col, i == 1 and 24 or 18), px + 70, py + 40 + (i - 1) * 44)
    end
  end
  if SCR.msg then place(ctext(tree, SCR.msg, "body", C("RED"), 18), x0, H - 110); SCR.msg = nil end
  if def.footer then place(ctext(tree, def.footer, "small", C("GREY"), 14), x0, H - 52)
  else place(SEL.prompts(tree, "menu", 30), x0, H - 54) end   -- game-style button prompts (#9)

  uw:AddToViewport(1100)
  SCR.widget = uw
  SEL.applyColors()
  SEL.hoverNow(SCR.hoverBtn); SCR.hoverBtn = nil
end

function SCR.inputText(i) return SCR.def.items[i].input.value or "" end
-- Typed characters (from the key binds in TYPE below) go straight into the field being edited.
function SCR.typeChar(c)
  local i = SCR.typing; if not (SCR.active and i) then return end
  local inp = SCR.def.items[i].input
  if inp.allow and not c:find(inp.allow) then return end
  local v = inp.value or ""
  if #v < (inp.max or 40) then inp.value = v .. c; SCR.build() end
end
function SCR.key(k)
  local def = SCR.def
  if SCR.typing then
    local i = SCR.typing
    local inp = def.items[i].input
    if k == "BACK" then inp.value = (inp.value or ""):sub(1, -2); SCR.build(); return end
    if k == "ENTER" or k == "TAB" or k == "UP" or k == "DOWN" then WH.sfx("ok") end
    if k == "ENTER" or k == "TAB" or k == "UP" or k == "DOWN" then
      SCR.typing = nil
      if inp.on then pcall(inp.on, inp.value or "") end
      if k == "TAB" or k == "DOWN" then SCR.sel = math.min(#def.items, i + 1) elseif k == "UP" then SCR.sel = math.max(1, i - 1) end
      SCR.build()
    end
    return
  end
  if k == "UP" then SCR.sel = (SCR.sel - 2) % #def.items + 1; WH.sfx("move"); SCR.build()
  elseif k == "DOWN" then SCR.sel = SCR.sel % #def.items + 1; WH.sfx("move"); SCR.build()
  elseif k == "ENTER" then
    local it = def.items[SCR.sel]
    if it.disabled then WH.sfx("deny"); return end
    WH.sfx("ok")
    if it.input then
      SCR.typing = SCR.sel; SCR.build()
    elseif it.on then
      local ok, err = pcall(it.on)
      if not ok then SCR.msg = tostring(err); SCR.refresh() end
    end
  elseif k == "BACK" or k == "F6" then
    WH.sfx("back")
    if def.back then def.back() else SCR.exit() end
  end
end

-- Text entry comes from the key binds in versus.lua (KB.handle -> SCR.typeChar). TYPE.poll is kept as a no-op for callers.
TYPE = TYPE or {}
function TYPE.poll() end
