local _, ns = ...
local N = ns.N
local M = N.Media

-- Widget set for the options window. Every control is a full-width row, label left, control right.
-- Cards (MakeCard) own vertical stacking and width. Extend here instead of pulling in a UI
-- library.

local function unpackColor(c) return c[1], c[2], c[3], c[4] or 1 end

local ROW_CHECK = 24
local ROW_CONTROL = 30

-- Section card: a rounded surface with a small accent tab and the title on top, a hairline beneath
-- it and rows flowing below with inner padding.

local CARD_PAD = 12
local CARD_HEADER = 32
local ROW_GAP = 8

-- Exposed so panels that lay out their own text inside a card line up with the standard rows: x
-- inset, and y where content starts.
N.CARD_PAD = CARD_PAD
N.CARD_TOP = CARD_HEADER + ROW_GAP

N.CONTENT_WIDTH = 512

-- Tooltip in the options window's own style: rounded card, shadow, accent title.
-- N.SetTip(widget, title, text, colorFn) hooks a widget; title / text may be strings or functions;
-- colorFn() -> {r,g,b} adds a color chip beside the title.

local tip
local TIP_W, TIP_PAD = 250, 9
local function buildTip()
    tip = CreateFrame("Frame", nil, UIParent)
    tip._nucUI = true
    tip:SetFrameStrata("TOOLTIP")
    tip:SetClampedToScreen(true)
    tip:EnableMouse(false)
    tip:Hide()
    N.SkinRound(tip, M.color.base, M.color.line, true)
    N.AddShadow(tip, 10, 0.55, -3)

    tip.chip = CreateFrame("Frame", nil, tip)
    tip.chip:SetSize(12, 12)
    N.SkinRound(tip.chip, M.color.base, M.color.line, true)

    tip.title = N.FontString(tip, 12)
    tip.title:SetJustifyH("LEFT")
    tip.title:SetWordWrap(true)
    tip.body = N.FontString(tip, 11)
    tip.body:SetJustifyH("LEFT")
    tip.body:SetWordWrap(true)
    tip.body:SetTextColor(unpackColor(M.color.textDim))
end

function N.ShowTip(owner, title, text, color)
    if not tip then buildTip() end
    tip.title:SetTextColor(unpackColor(M.color.accent))
    local inner = TIP_W - 2 * TIP_PAD
    local x0 = TIP_PAD
    tip.chip:Hide()
    if color then
        tip.chip._nucFill:SetColorTexture(color[1], color[2], color[3])
        tip.chip:ClearAllPoints()
        tip.chip:SetPoint("TOPLEFT", tip, "TOPLEFT", TIP_PAD, -TIP_PAD)
        tip.chip:Show()
        x0 = TIP_PAD + 18
    end
    tip.title:ClearAllPoints()
    tip.title:SetPoint("TOPLEFT", tip, "TOPLEFT", x0, -TIP_PAD)
    tip.title:SetWidth(TIP_W - TIP_PAD - x0)
    tip.title:SetText(title or "")
    local h = TIP_PAD + math.max(tip.title:GetStringHeight(), color and 12 or 0)
    if text and text ~= "" then
        tip.body:ClearAllPoints()
        tip.body:SetPoint("TOPLEFT", tip, "TOPLEFT", TIP_PAD, -(h + 4))
        tip.body:SetWidth(inner)
        tip.body:SetText(text)
        tip.body:Show()
        h = h + 4 + tip.body:GetStringHeight()
    else
        tip.body:Hide()
    end
    tip:SetSize(TIP_W, h + TIP_PAD)
    tip:ClearAllPoints()
    tip:SetPoint("LEFT", owner, "RIGHT", 12, 0)
    tip:Show()
    local right = tip:GetRight()
    if right and right > UIParent:GetRight() then
        tip:ClearAllPoints()
        tip:SetPoint("RIGHT", owner, "LEFT", -12, 0)
    end
end

function N.HideTip()
    if tip then tip:Hide() end
end

function N.SetTip(widget, title, text, colorFn)
    widget:HookScript("OnEnter", function(self)
        local t = type(title) == "function" and title() or title
        local b = type(text) == "function" and text() or text
        N.ShowTip(self, t, b, colorFn and colorFn() or nil)
    end)
    widget:HookScript("OnLeave", N.HideTip)
    widget:HookScript("OnHide", N.HideTip)
end

function N.MakeCard(parent, title)
    local card = CreateFrame("Frame", nil, parent)
    local w = (parent and parent._cardW) or N.CONTENT_WIDTH
    card:SetSize(w - 4, CARD_HEADER)
    N.SkinRound(card, M.color.card, M.color.line)

    local tab = card:CreateTexture(nil, "ARTWORK")
    tab:SetTexture(M.flat)
    tab:SetColorTexture(unpackColor(M.color.accent))
    tab:SetPoint("TOPLEFT", CARD_PAD, -11)
    tab:SetSize(3, 12)

    local head = N.FontString(card, 12)
    head:SetPoint("LEFT", tab, "RIGHT", 7, 0)
    head:SetText(title)
    head:SetTextColor(unpackColor(M.color.text))

    local rule = card:CreateTexture(nil, "ARTWORK")
    rule:SetTexture(M.flat)
    rule:SetColorTexture(unpackColor(M.color.line))
    rule:SetPoint("TOPLEFT", CARD_PAD, -(CARD_HEADER - 4))
    rule:SetPoint("TOPRIGHT", -CARD_PAD, -(CARD_HEADER - 4))
    rule:SetHeight(1)

    N.OnRecolor(function() tab:SetColorTexture(unpackColor(M.color.accent)) end)

    card._y = -CARD_HEADER - ROW_GAP

    function card:AddRow(widget)
        widget:SetParent(self)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", self, "TOPLEFT", CARD_PAD, card._y)
        widget:SetPoint("RIGHT", self, "RIGHT", -CARD_PAD, 0)
        local h = widget._rowHeight or ROW_CONTROL
        widget:SetHeight(h)
        card._y = card._y - h - ROW_GAP
        self:SetHeight(-card._y + CARD_PAD - ROW_GAP)
        return widget
    end

    return card
end

--------------------------------------------------------------------------------
-- Controls
--------------------------------------------------------------------------------

function N.MakeColorPicker(parent, label, get, set, desc)
    local f = CreateFrame("Button", nil, parent)
    f._rowHeight = 20

    local sw = CreateFrame("Button", nil, f)
    sw:SetSize(20, 14)
    sw:SetPoint("LEFT")
    N.SkinRound(sw, M.color.base, M.color.line, true)
    local tex = sw._nucFill
    sw:SetScript("OnEnter", function() N.SetPanelBorder(sw, M.color.accent) end)
    sw:SetScript("OnLeave", function() N.SetPanelBorder(sw, M.color.line) end)

    local lb = N.FontString(f, 12)
    lb:SetPoint("LEFT", sw, "RIGHT", 8, 0)
    lb:SetText(label)

    local function refresh()
        local c = get()
        tex:SetColorTexture(c[1], c[2], c[3])
    end
    local function open()
        local c = get()
        N.ColorPicker:Open({
            r = c[1], g = c[2], b = c[3], title = label,
            onChange = function(r, g, b) tex:SetColorTexture(r, g, b) end,
            onAccept = function(r, g, b) set({ r, g, b }); refresh() end,
            onCancel = refresh,
        })
    end
    sw:SetScript("OnClick", open)
    f:SetScript("OnClick", open)
    local function colorText()
        local c = get()
        local r, g, b = math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5)
        local line = string.format("#%02X%02X%02X   (%d, %d, %d)", r, g, b, r, g, b)
        return desc and (desc .. "\n" .. line) or line
    end
    N.SetTip(sw, label, colorText, get)
    N.SetTip(f, label, colorText, get)
    refresh()
    f.Refresh = refresh
    return f
end

-- A 16px rounded box on the LEFT, label to its right. Unchecked: raised grey
-- with a hairline rim; checked: solid accent with a white tick.
function N.MakeCheckbox(parent, label, get, set)
    local f = CreateFrame("Button", nil, parent)
    f._rowHeight = 22

    local box = CreateFrame("Frame", nil, f)
    box:SetSize(16, 16)
    box:SetPoint("LEFT")
    N.SkinRound(box, M.color.base, M.color.line, true)

    local ticks = {}
    for i, d in ipairs({
        { rot = -45, w = 4.5, x = -2.6, y = -1.2 },
        { rot =  45, w = 8.5, x =  1.4, y =  0.6 },
    }) do
        local t = box:CreateTexture(nil, "OVERLAY")
        t:SetTexture(M.flat)
        t:SetVertexColor(1, 1, 1, 1)
        t:SetSize(d.w, 2)
        t:SetPoint("CENTER", box, "CENTER", d.x, d.y)
        t:SetRotation(math.rad(d.rot))
        ticks[i] = t
    end

    local lb = N.FontString(f, 12)
    lb:SetPoint("LEFT", box, "RIGHT", 8, 0)
    lb:SetPoint("RIGHT", f, "RIGHT", -2, 0)
    lb:SetJustifyH("LEFT")
    lb:SetWordWrap(false)
    lb:SetText(label)

    local function refresh()
        local on = get() and true or false
        box._nucFill:SetColorTexture(unpackColor(on and M.color.accent or M.color.base))
        for _, t in ipairs(ticks) do t:SetShown(on) end
    end
    f:SetScript("OnClick", function() set(not get()); refresh() end)
    f:SetScript("OnEnter", function() N.SetPanelBorder(box, M.color.accentBright) end)
    f:SetScript("OnLeave", function() N.SetPanelBorder(box, M.color.line) end)
    refresh()
    f.Refresh = refresh

    N.OnRecolor(refresh)
    return f
end

-- Label on the left, an editable value box on the right, and below them a
-- rounded track that fills with accent up to a round thumb. get()/set(v) in
-- real units.
function N.MakeSlider(parent, label, minV, maxV, step, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f._rowHeight = 38

    local lb = N.FontString(f, 12)
    lb:SetPoint("TOPLEFT", 0, -1)
    lb:SetText(label)

    local slider = CreateFrame("Slider", nil, f)
    slider:SetPoint("TOPLEFT", 0, -22)
    slider:SetPoint("TOPRIGHT", 0, -22)
    slider:SetHeight(16)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    -- Capsule bars are a flat body plus half-circle end caps (the circle texture split at its
    -- middle), so even a 5px bar gets truly round ends; 9-slicing can't shrink corners below its
    -- margin.
    local BAR_H = 5
    local function capsule(layer, color, rightCap)
        local parts = {}
        local l = slider:CreateTexture(nil, layer)
        l:SetTexture(M.tex.circle)
        l:SetTexCoord(0, 0.5, 0, 1)
        l:SetSize(BAR_H / 2, BAR_H)
        l:SetPoint("LEFT")
        parts[#parts + 1] = l
        local body = slider:CreateTexture(nil, layer)
        body:SetTexture(M.flat)
        body:SetHeight(BAR_H)
        body:SetPoint("LEFT", l, "RIGHT")
        parts[#parts + 1] = body
        local r
        if rightCap then
            r = slider:CreateTexture(nil, layer)
            r:SetTexture(M.tex.circle)
            r:SetTexCoord(0.5, 1, 0, 1)
            r:SetSize(BAR_H / 2, BAR_H)
            r:SetPoint("RIGHT")
            body:SetPoint("RIGHT", r, "LEFT")
            parts[#parts + 1] = r
        end
        local function tint(c)
            for _, t in ipairs(parts) do t:SetVertexColor(unpackColor(c)) end
        end
        tint(color)
        return body, tint
    end

    capsule("BACKGROUND", M.color.segment, true)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture(M.tex.circle)
    thumb:SetVertexColor(0.96, 0.97, 1.0, 1)
    thumb:SetSize(14, 14)
    slider:SetThumbTexture(thumb)

    local fillBody, tintFill = capsule("ARTWORK", M.color.accent, false)
    fillBody:SetPoint("RIGHT", thumb, "CENTER")

    N.OnRecolor(function() tintFill(M.color.accent) end)

    local decimals = step < 1
    local function fmt(v) return decimals and string.format("%.2f", v) or tostring(N.Round(v)) end

    local eb = CreateFrame("EditBox", nil, f)
    eb:SetSize(54, 18)
    eb:SetPoint("TOPRIGHT", 0, 1)
    eb:SetFont(M.fontUI, 11, "")
    N.RegisterFont(eb, 11, "")
    eb:SetJustifyH("CENTER")
    eb:SetAutoFocus(false)
    eb:SetTextInsets(2, 2, 0, 0)
    N.SkinRound(eb, M.color.base, M.color.line, true)
    eb:SetScript("OnEditFocusGained", function() N.SetPanelBorder(eb, M.color.accent) end)
    eb:HookScript("OnEditFocusLost", function() N.SetPanelBorder(eb, M.color.line) end)

    local guard
    slider:SetScript("OnValueChanged", function(_, v)
        if not guard then eb:SetText(fmt(v)) end
        if not guard then set(v) end
    end)
    eb:SetScript("OnEnterPressed", function(self)
        local v = tonumber(self:GetText())
        if v then
            if v < minV then v = minV elseif v > maxV then v = maxV end
            slider:SetValue(v)
        end
        self:SetText(fmt(slider:GetValue()))
        self:ClearFocus()
    end)
    eb:SetScript("OnEscapePressed", function(self)
        self:SetText(fmt(slider:GetValue())); self:ClearFocus()
    end)

    local function refresh()
        guard = true
        slider:SetValue(get())
        guard = nil
        eb:SetText(fmt(get()))
    end
    refresh()
    f.Refresh = refresh
    return f
end

-- Single-line text field. Label above, full-width box below, commits on Enter or focus loss.
function N.MakeTextInput(parent, label, get, set)
    local f = CreateFrame("Frame", nil, parent)
    local compact = (label == nil)
    f._rowHeight = compact and 24 or 42

    if not compact then
        local lb = N.FontString(f, 12)
        lb:SetPoint("TOPLEFT", 0, 0)
        lb:SetText(label)
    end

    local box = CreateFrame("Frame", nil, f)
    box:SetPoint("TOPLEFT", 0, compact and 0 or -17)
    box:SetPoint("TOPRIGHT", 0, compact and 0 or -17)
    box:SetHeight(compact and 24 or 22)
    N.SkinRound(box, M.color.base, M.color.line, true)

    local edit = CreateFrame("EditBox", nil, box)
    edit:SetPoint("TOPLEFT", 6, 0)
    edit:SetPoint("BOTTOMRIGHT", -6, 0)
    edit:SetFont(M.fontUI, 12, "")
    N.RegisterFont(edit, 12, "")
    edit:SetTextColor(unpackColor(M.color.text))
    edit:SetAutoFocus(false)
    edit:SetText(get() or "")
    edit:SetScript("OnEditFocusGained", function() N.SetPanelBorder(box, M.color.accent) end)
    edit:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(s) s:ClearFocus() end)
    edit:SetScript("OnEditFocusLost", function(s) N.SetPanelBorder(box, M.color.line); set(s:GetText()) end)

    f.Refresh = function() if not edit:HasFocus() then edit:SetText(get() or "") end end
    return f
end

-- Multi-line text box (whitelist entry). get() -> string ; set(string) on
-- focus loss / Enter-less commit. Sits below its label, full row width.
function N.MakeMultiEdit(parent, label, get, set)
    local f = CreateFrame("Frame", nil, parent)
    f._rowHeight = 80

    local lb = N.FontString(f, 12)
    lb:SetPoint("TOPLEFT", 0, 0)
    lb:SetText(label)

    local box = CreateFrame("Frame", nil, f)
    box:SetPoint("TOPLEFT", 0, -18)
    box:SetPoint("TOPRIGHT", 0, -18)
    box:SetHeight(54)
    N.SkinRound(box, M.color.base, M.color.line, true)

    local edit = CreateFrame("EditBox", nil, box)
    edit:SetMultiLine(true)
    edit:SetPoint("TOPLEFT", 6, -5)
    edit:SetPoint("BOTTOMRIGHT", -6, 5)
    edit:SetFont(M.fontUI, 12, "")
    N.RegisterFont(edit, 12, "")
    edit:SetTextColor(unpackColor(M.color.text))
    edit:SetAutoFocus(false)
    edit:SetText(get() or "")
    edit:SetScript("OnEditFocusGained", function() N.SetPanelBorder(box, M.color.accent) end)
    edit:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    edit:SetScript("OnEditFocusLost", function(s) N.SetPanelBorder(box, M.color.line); set(s:GetText()) end)

    f.Refresh = function() if not edit:HasFocus() then edit:SetText(get() or "") end end
    return f
end

-- Shared click-catcher so an open dropdown closes when clicking elsewhere.
local openList
local catcher = CreateFrame("Button", nil, UIParent)
catcher:SetFrameStrata("FULLSCREEN_DIALOG")
catcher:SetAllPoints(UIParent)
catcher:EnableMouse(true)
catcher:Hide()
catcher:SetScript("OnClick", function()
    if openList then openList:Hide() end
end)

local DD_ROW = 22
local DD_BTN_W = 160

-- Flat triangular caret drawn by collapsing two quad corners, so it needs no
-- texture asset and stays crisp at any UI scale. dir "down" | "up".
local function shapeCaret(tex, dir)
    local w = tex:GetWidth()
    if dir == "up" then
        tex:SetVertexOffset(1, w / 2, 0)   -- UPPER_LEFT  -> top centre
        tex:SetVertexOffset(3, -w / 2, 0)  -- UPPER_RIGHT -> top centre
        tex:SetVertexOffset(2, 0, 0)
        tex:SetVertexOffset(4, 0, 0)
    else
        tex:SetVertexOffset(1, 0, 0)
        tex:SetVertexOffset(3, 0, 0)
        tex:SetVertexOffset(2, w / 2, 0)   -- LOWER_LEFT  -> bottom centre
        tex:SetVertexOffset(4, -w / 2, 0)  -- LOWER_RIGHT -> bottom centre
    end
end

function N.MakeDropdown(parent, label, options, get, set)
    local f = CreateFrame("Frame", nil, parent)
    local compact = (label == nil)
    f._rowHeight = compact and 24 or 42

    if not compact then
        local lb = N.FontString(f, 12)
        lb:SetPoint("TOPLEFT", 0, 0)
        lb:SetText(label)
    end

    local button = CreateFrame("Button", nil, f)
    button:SetPoint("TOPLEFT", 0, compact and 0 or -17)
    button:SetPoint("TOPRIGHT", 0, compact and 0 or -17)
    button:SetHeight(compact and 24 or 22)
    N.SkinRound(button, M.color.base, M.color.line, true)

    local current = N.FontString(button, 12)
    current:SetPoint("LEFT", 9, 0)
    current:SetPoint("RIGHT", -20, 0)
    current:SetJustifyH("LEFT")
    current:SetWordWrap(false)

    local caret = button:CreateTexture(nil, "ARTWORK")
    caret:SetColorTexture(1, 1, 1, 1)
    caret:SetVertexColor(unpackColor(M.color.textDim))
    caret:SetSize(7, 4)
    caret:SetPoint("RIGHT", -8, 0)
    shapeCaret(caret, "down")

    local function setState(open, hover)
        button._nucFill:SetColorTexture(unpackColor((open or hover) and M.color.baseHover or M.color.base))
        caret:SetVertexColor(unpackColor(open and M.color.accent or M.color.textDim))
        shapeCaret(caret, open and "up" or "down")
        N.SetPanelBorder(button, open and M.color.accent or M.color.line)
    end

    local list = CreateFrame("Frame", nil, UIParent)
    list._nucUI = true
    list:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -3)
    list:SetHeight(#options * DD_ROW + 6)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetFrameLevel(catcher:GetFrameLevel() + 5)
    N.SkinRound(list, { 0.095, 0.103, 0.125, 1 }, M.color.line, true)
    N.AddShadow(list, 14, 0.5, -3)
    list:Hide()

    local function label_for(v)
        for _, o in ipairs(options) do if o.value == v then return o.text end end
        return tostring(v)
    end

    local rows, maxTextW = {}, 0
    for i, o in ipairs(options) do
        local row = CreateFrame("Button", nil, list)
        row:SetPoint("TOPLEFT", 3, -3 - (i - 1) * DD_ROW)
        row:SetPoint("TOPRIGHT", -3, -3 - (i - 1) * DD_ROW)
        row:SetHeight(DD_ROW)

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetColorTexture(unpackColor(M.color.accent))
        hl:SetAlpha(0.35)
        hl:SetAllPoints()

        local bar = row:CreateTexture(nil, "ARTWORK")
        bar:SetColorTexture(unpackColor(M.color.accent))
        bar:SetPoint("TOPLEFT")
        bar:SetPoint("BOTTOMLEFT")
        bar:SetWidth(2)

        local rt = N.FontString(row, 12)
        rt:SetPoint("LEFT", 10, 0)
        rt:SetText(o.text)
        row.rt, row.bar, row.hl, row.value = rt, bar, hl, o.value
        maxTextW = math.max(maxTextW, rt:GetStringWidth())

        row:SetScript("OnClick", function()
            set(o.value)
            current:SetText(label_for(o.value))
            list:Hide()
        end)
        rows[i] = row
    end
    list:SetWidth(math.max(DD_BTN_W, maxTextW + 28))

    local function markSelected()
        local v = get()
        for _, row in ipairs(rows) do
            local on = row.value == v
            row.bar:SetShown(on)
            row.rt:SetTextColor(unpackColor(on and M.color.accentBright or M.color.text))
        end
    end

    list:SetScript("OnHide", function()
        openList = nil
        catcher:Hide()
        setState(false, button:IsMouseOver())
    end)
    list:SetScript("OnShow", function()
        if openList and openList ~= list then openList:Hide() end
        openList = list
        catcher:Show()
        setState(true)
        markSelected()
    end)

    button:SetScript("OnClick", function() list:SetShown(not list:IsShown()) end)
    button:SetScript("OnEnter", function() if not list:IsShown() then setState(false, true) end end)
    button:SetScript("OnLeave", function() if not list:IsShown() then setState(false, false) end end)

    setState(false, false)
    current:SetText(label_for(get()))
    f.Refresh = function() current:SetText(label_for(get())) end

    N.OnRecolor(function()
        for _, row in ipairs(rows) do
            row.hl:SetColorTexture(unpackColor(M.color.accent))
            row.bar:SetColorTexture(unpackColor(M.color.accent))
        end
        setState(list:IsShown(), button:IsMouseOver())
        markSelected()
    end)

    return f
end

-- Key capture: a button that, once clicked, waits for the next modifier + mouse click anywhere and
-- reports it. Used for click-cast bindings.

local grabber
local function getGrabber()
    if grabber then return grabber end
    grabber = CreateFrame("Button", nil, UIParent)
    grabber:SetFrameStrata("FULLSCREEN_DIALOG")
    grabber:SetFrameLevel(catcher:GetFrameLevel() + 20)
    grabber:SetAllPoints(UIParent)
    grabber:EnableMouse(true)
    grabber:EnableKeyboard(true)
    grabber:RegisterForClicks("AnyUp")
    grabber:Hide()

    local dim = grabber:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints()
    dim:SetColorTexture(0, 0, 0, 0.45)

    local plate = CreateFrame("Frame", nil, grabber)
    plate:SetSize(380, 64)
    plate:SetPoint("CENTER")
    N.SkinRound(plate, M.color.card, M.color.accent)
    local hint = N.FontString(plate, 13)
    hint:SetPoint("CENTER", 0, 8)
    hint:SetText(N.L["KEYCAPTURE_HINT"])
    local sub = N.FontString(plate, 11)
    sub:SetPoint("CENTER", 0, -12)
    sub:SetTextColor(unpackColor(M.color.textDim))
    sub:SetText(N.L["KEYCAPTURE_ESC"])

    grabber:SetScript("OnClick", function(self, btn)
        local done = self.onDone
        self.onDone, self.onCancel = nil, nil
        self:Hide()
        if done then done(btn) end
    end)
    grabber:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            local cancel = self.onCancel
            self.onDone, self.onCancel = nil, nil
            self:Hide()
            if cancel then cancel() end
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    return grabber
end

-- getText() -> string shown on the button; onCapture(modifier, button) gets the
-- canonical modifier ("none" | "alt-ctrl-shift" subset) and the button name.
function N.MakeKeyCapture(parent, getText, onCapture)
    local b = CreateFrame("Button", nil, parent)
    b._rowHeight = 24
    N.SkinRound(b, M.color.base, M.color.line, true)

    local fs = N.FontString(b, 12)
    fs:SetPoint("LEFT", 8, 0)
    fs:SetPoint("RIGHT", -8, 0)
    fs:SetJustifyH("CENTER")
    fs:SetWordWrap(false)

    local listening = false
    local function refresh()
        if listening then
            fs:SetText(N.L["Press a key..."])
            fs:SetTextColor(unpackColor(M.color.accentBright))
            N.SetPanelBorder(b, M.color.accent)
        else
            fs:SetText(getText())
            fs:SetTextColor(unpackColor(M.color.text))
            N.SetPanelBorder(b, M.color.line)
        end
    end

    b:SetScript("OnEnter", function()
        if not listening then b._nucFill:SetColorTexture(unpackColor(M.color.baseHover)) end
    end)
    b:SetScript("OnLeave", function() b._nucFill:SetColorTexture(unpackColor(M.color.base)) end)
    b:SetScript("OnClick", function()
        if listening then return end
        listening = true
        refresh()
        local g = getGrabber()
        g.onDone = function(btn)
            listening = false
            onCapture(N.ClickCasting.CurrentModifier(), btn)
            refresh()
        end
        g.onCancel = function() listening = false; refresh() end
        g:Show()
    end)

    b.Refresh = refresh
    refresh()
    return b
end

-- Icon picker: a compact dropdown whose entries carry icons, with a search box and a scrolling
-- list, for long lists (spells, macros, items).
--   getOptions() -> { { value, text, icon }, ... }   built each time it opens
--   resolve(value) -> text, icon   for a saved value that is not in the list

local PICK_ROW, PICK_VISIBLE, PICK_MIN_W = 22, 9, 250
local QUESTION_ICON = 134400

function N.MakeIconPicker(parent, getOptions, get, set, resolve)
    local f = CreateFrame("Frame", nil, parent)
    f._rowHeight = 24

    local button = CreateFrame("Button", nil, f)
    button:SetAllPoints()
    N.SkinRound(button, M.color.base, M.color.line, true)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", 5, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local current = N.FontString(button, 12)
    current:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    current:SetPoint("RIGHT", -20, 0)
    current:SetJustifyH("LEFT")
    current:SetWordWrap(false)

    local caret = button:CreateTexture(nil, "ARTWORK")
    caret:SetColorTexture(1, 1, 1, 1)
    caret:SetVertexColor(unpackColor(M.color.textDim))
    caret:SetSize(7, 4)
    caret:SetPoint("RIGHT", -8, 0)
    shapeCaret(caret, "down")

    local function refreshCurrent()
        local v = get()
        if v == nil or v == "" then
            icon:Hide()
            current:ClearAllPoints()
            current:SetPoint("LEFT", 9, 0)
            current:SetPoint("RIGHT", -20, 0)
            current:SetText(N.L["Select..."])
            current:SetTextColor(unpackColor(M.color.textDim))
        else
            local text, tex = resolve(v)
            icon:SetTexture(tex or QUESTION_ICON)
            icon:Show()
            current:ClearAllPoints()
            current:SetPoint("LEFT", icon, "RIGHT", 6, 0)
            current:SetPoint("RIGHT", -20, 0)
            current:SetText(text or v)
            current:SetTextColor(unpackColor(M.color.text))
        end
    end

    local function setState(open, hover)
        button._nucFill:SetColorTexture(unpackColor((open or hover) and M.color.baseHover or M.color.base))
        caret:SetVertexColor(unpackColor(open and M.color.accent or M.color.textDim))
        shapeCaret(caret, open and "up" or "down")
        N.SetPanelBorder(button, open and M.color.accent or M.color.line)
    end

    local list = CreateFrame("Frame", nil, UIParent)
    list._nucUI = true
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetFrameLevel(catcher:GetFrameLevel() + 5)
    list:SetClampedToScreen(true)
    N.SkinRound(list, { 0.095, 0.103, 0.125, 1 }, M.color.line, true)
    N.AddShadow(list, 14, 0.5, -3)
    list:Hide()

    local search = CreateFrame("EditBox", nil, list)
    search:SetPoint("TOPLEFT", 6, -6)
    search:SetPoint("TOPRIGHT", -6, -6)
    search:SetHeight(22)
    search:SetFont(M.fontUI, 12, "")
    N.RegisterFont(search, 12, "")
    search:SetTextInsets(8, 8, 0, 0)
    search:SetAutoFocus(false)
    N.SkinRound(search, M.color.base, M.color.line, true)
    local ph = N.FontString(search, 12)
    ph:SetPoint("LEFT", 8, 0)
    ph:SetTextColor(unpackColor(M.color.textDim))
    ph:SetText(N.L["Search..."])

    local scroll, child = N.MakeScroll(list, -3)
    scroll:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -34)
    scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -9, 4)

    local empty = N.FontString(list, 12)
    empty:SetPoint("TOP", list, "TOP", 0, -44)
    empty:SetTextColor(unpackColor(M.color.textDim))
    empty:SetText(N.L["Nothing found"])
    empty:Hide()

    local rows, all = {}, {}

    local function newRow(i)
        local row = CreateFrame("Button", nil, child)
        row:SetHeight(PICK_ROW)
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(i - 1) * PICK_ROW)
        row:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -(i - 1) * PICK_ROW)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetColorTexture(unpackColor(M.color.accent))
        hl:SetAlpha(0.35)
        hl:SetAllPoints()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 6, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.text = N.FontString(row, 12)
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
        row.text:SetPoint("RIGHT", -6, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
        row:SetScript("OnClick", function()
            set(row.opt.value)
            refreshCurrent()
            list:Hide()
        end)
        rows[i] = row
        return row
    end

    local function populate(filter)
        filter = (filter or ""):lower()
        local shownCount, selected = 0, get()
        for _, o in ipairs(all) do
            if filter == "" or (o.text or ""):lower():find(filter, 1, true) then
                shownCount = shownCount + 1
                local row = rows[shownCount] or newRow(shownCount)
                row.opt = o
                row.icon:SetTexture(o.icon or QUESTION_ICON)
                row.text:SetText(o.text)
                row.text:SetTextColor(unpackColor(o.value == selected and M.color.accentBright or M.color.text))
                row:Show()
            end
        end
        for i = shownCount + 1, #rows do rows[i]:Hide() end
        empty:SetShown(shownCount == 0)
        child:SetHeight(math.max(shownCount, 1) * PICK_ROW)
        list:SetHeight(34 + math.max(1, math.min(shownCount, PICK_VISIBLE)) * PICK_ROW + 8)
        if scroll.SetOffset then scroll.SetOffset(0) end
    end

    search:SetScript("OnTextChanged", function(self)
        ph:SetShown(self:GetText() == "")
        populate(self:GetText())
    end)
    search:SetScript("OnEscapePressed", function() list:Hide() end)
    search:SetScript("OnEditFocusGained", function() N.SetPanelBorder(search, M.color.accent) end)
    search:SetScript("OnEditFocusLost", function() N.SetPanelBorder(search, M.color.line) end)

    list:SetScript("OnShow", function()
        if openList and openList ~= list then openList:Hide() end
        openList = list
        catcher:Show()
        setState(true)
        local w = math.max(button:GetWidth(), PICK_MIN_W)
        list:SetWidth(w)
        child:SetWidth(w - 13)
        list:ClearAllPoints()
        list:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -3)
        all = getOptions() or {}
        search:SetText("")
        ph:Show()
        populate("")
        search:SetFocus()
    end)
    list:SetScript("OnHide", function()
        openList = nil
        catcher:Hide()
        setState(false, button:IsMouseOver())
        search:ClearFocus()
    end)

    button:SetScript("OnClick", function() list:SetShown(not list:IsShown()) end)
    button:SetScript("OnEnter", function() if not list:IsShown() then setState(false, true) end end)
    button:SetScript("OnLeave", function() if not list:IsShown() then setState(false, false) end end)

    setState(false, false)
    refreshCurrent()
    f.Refresh = refreshCurrent
    return f
end

-- Custom scroll area: thin auto-hiding accent scrollbar with wheel support.

-- trackX: how far the bar sits right of the scroll area's edge (default 10, i.e.
-- in the margin; pass a negative number to tuck it inside a small panel).
function N.MakeScroll(parent, trackX)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)

    local track = CreateFrame("Frame", nil, parent)
    track:SetWidth(4)
    track:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", trackX or 10, 0)
    track:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", trackX or 10, 0)
    local trackTex = track:CreateTexture(nil, "BACKGROUND")
    trackTex:SetColorTexture(unpackColor(M.color.scrollTrack))
    trackTex:SetAllPoints()

    local thumb = CreateFrame("Frame", nil, track)
    thumb:SetPoint("LEFT")
    thumb:SetPoint("RIGHT")
    thumb:SetHeight(40)
    local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
    thumbTex:SetColorTexture(unpackColor(M.color.scrollThumb))
    thumbTex:SetAllPoints()
    thumb:EnableMouse(true)
    thumb:SetScript("OnEnter", function() thumbTex:SetColorTexture(unpackColor(M.color.accent)) end)
    thumb:SetScript("OnLeave", function() thumbTex:SetColorTexture(unpackColor(M.color.scrollThumb)) end)

    local function range()
        return math.max(0, child:GetHeight() - scroll:GetHeight())
    end

    local function updateThumb()
        local r = range()
        if r <= 0 then
            track:Hide()
            return
        end
        track:Show()
        local h = track:GetHeight()
        local th = math.max(24, h * (scroll:GetHeight() / child:GetHeight()))
        thumb:SetHeight(th)
        local pct = scroll:GetVerticalScroll() / r
        thumb:ClearAllPoints()
        thumb:SetPoint("LEFT")
        thumb:SetPoint("RIGHT")
        thumb:SetPoint("TOP", track, "TOP", 0, -pct * (h - th))
    end

    local function setScroll(v)
        v = math.max(0, math.min(v, range()))
        scroll:SetVerticalScroll(v)
        updateThumb()
    end
    scroll.SetOffset = setScroll

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(_, d) setScroll(scroll:GetVerticalScroll() - d * 42) end)
    scroll:SetScript("OnScrollRangeChanged", updateThumb)
    scroll:SetScript("OnSizeChanged", updateThumb)

    thumb:RegisterForDrag("LeftButton")
    thumb:SetScript("OnDragStart", function()
        thumb.dragY = select(2, GetCursorPosition())
        thumb.startScroll = scroll:GetVerticalScroll()
        thumb:SetScript("OnUpdate", function()
            local _, y = GetCursorPosition()
            local scale = thumb:GetEffectiveScale()
            -- Cursor Y decreases downward; dragging the thumb down must
            -- increase the scroll offset (move the view down).
            local deltaDown = (thumb.dragY - y) / scale
            local h = track:GetHeight()
            local th = thumb:GetHeight()
            local travel = h - th
            if travel > 0 then
                setScroll(thumb.startScroll + deltaDown * (range() / travel))
            end
        end)
    end)
    thumb:SetScript("OnDragStop", function() thumb:SetScript("OnUpdate", nil) end)

    return scroll, child, updateThumb
end

--------------------------------------------------------------------------------
-- Copy-link popup (the client cannot open external URLs)
--------------------------------------------------------------------------------

function N.ShowLinkPopup(label, url)
    N.Dialog.Link(label, url)
end
