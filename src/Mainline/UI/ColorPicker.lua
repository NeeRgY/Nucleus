local _, ns = ...
local N = ns.N
local M = N.Media

-- Custom HSV colour picker (ported from the author's Key Herald addon):
-- a saturation/value square, a hue strip, a hex field, preset swatches and a
-- live preview. Replaces Blizzard's ColorPickerFrame.

local CP = {}
N.ColorPicker = CP

local function clamp01(x) return x < 0 and 0 or (x > 1 and 1 or x) end

local function rgb2hsv(r, g, b)
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local d, h, s, v = mx - mn, 0, 0, mx
    if mx > 0 then s = d / mx end
    if d > 0 then
        if mx == r then h = ((g - b) / d) % 6
        elseif mx == g then h = (b - r) / d + 2
        else h = (r - g) / d + 4 end
        h = h / 6
        if h < 0 then h = h + 1 end
    end
    return h, s, v
end

local function hsv2rgb(h, s, v)
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    i = i % 6
    if i == 0 then return v, t, p
    elseif i == 1 then return q, v, p
    elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v
    elseif i == 4 then return t, p, v
    else return v, p, q end
end

local function toHex(r, g, b)
    return ("%02X%02X%02X"):format(
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function fromHex(str)
    str = tostring(str):gsub("[^%x]", "")
    if #str ~= 6 then return nil end
    return tonumber(str:sub(1, 2), 16) / 255,
           tonumber(str:sub(3, 4), 16) / 255,
           tonumber(str:sub(5, 6), 16) / 255
end

local PRESETS = {
    "3399F2", "22C1C3", "3FCF5C", "F2C14E", "FF7A45",
    "FF5C8A", "B55CFF", "7A5CFF", "E0E0E0", "9AA0A6",
}

-- A rounded, bordered container (the same skin the options window uses).
local function panel(parent)
    local f = CreateFrame("Frame", nil, parent)
    N.SkinRound(f, M.color.base, M.color.line, true)
    return f
end

local function fs(parent, size, color)
    local t = N.FontString(parent, size)
    if color then t:SetTextColor(color[1], color[2], color[3]) end
    return t
end

local function scaledCursor()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    return x / s, y / s
end

local frame

local PAD, SV_W, SV_H, HUE_W = 14, 200, 150, 20

local function build()
    if frame then return frame end

    frame = CreateFrame("Frame", "NucleusColorPicker", UIParent)
    frame._nucUI = true
    frame:SetSize(PAD * 2 + SV_W + 12 + HUE_W, 348)
    frame:SetPoint("CENTER", 0, 60)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:Hide()
    N.SkinRound(frame, M.color.windowBg, M.color.line)
    N.AddShadow(frame, 14, 0.7, -5)

    -- Header: draggable title strip with a close button.
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(38)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    local title = fs(header, 14)
    title:SetPoint("LEFT", header, "LEFT", PAD + 2, 0)
    title:SetTextColor(M.color.accentBright[1], M.color.accentBright[2], M.color.accentBright[3])
    frame.title = title

    local close = CreateFrame("Button", nil, header)
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", header, "RIGHT", -10, 0)
    N.SkinRound(close, M.color.base, M.color.line, true)
    local tint = N.MakeCross(close, 10, 2)
    tint(M.color.textDim[1], M.color.textDim[2], M.color.textDim[3], 1)
    close:HookScript("OnEnter", function()
        close._nucFill:SetColorTexture(0.80, 0.22, 0.22, 1)
        tint(1, 1, 1, 1)
    end)
    close:HookScript("OnLeave", function()
        close._nucFill:SetColorTexture(M.color.base[1], M.color.base[2], M.color.base[3], M.color.base[4] or 1)
        tint(M.color.textDim[1], M.color.textDim[2], M.color.textDim[3], 1)
    end)

    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetTexture(M.flat)
    rule:SetColorTexture(M.color.line[1], M.color.line[2], M.color.line[3], 1)
    rule:SetPoint("TOPLEFT", PAD, -38)
    rule:SetPoint("TOPRIGHT", -PAD, -38)
    rule:SetHeight(1)

    N.OnRecolor(function()
        title:SetTextColor(M.color.accentBright[1], M.color.accentBright[2], M.color.accentBright[3])
    end)

    frame.h, frame.s, frame.v = 0, 0, 1
    local function currentRGB() return hsv2rgb(frame.h, frame.s, frame.v) end

    -- Saturation / value square.
    local sv = panel(frame)
    sv:SetSize(SV_W, SV_H)
    sv:SetPoint("TOPLEFT", PAD, -50)

    local hueTex = sv:CreateTexture(nil, "BACKGROUND", nil, 1)
    hueTex:SetPoint("TOPLEFT", 2, -2); hueTex:SetPoint("BOTTOMRIGHT", -2, 2)
    hueTex:SetColorTexture(1, 1, 1, 1)

    local whiteGrad = sv:CreateTexture(nil, "ARTWORK")
    whiteGrad:SetPoint("TOPLEFT", 2, -2); whiteGrad:SetPoint("BOTTOMRIGHT", -2, 2)
    whiteGrad:SetColorTexture(1, 1, 1, 1)
    whiteGrad:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 0))

    local blackGrad = sv:CreateTexture(nil, "OVERLAY")
    blackGrad:SetPoint("TOPLEFT", 2, -2); blackGrad:SetPoint("BOTTOMRIGHT", -2, 2)
    blackGrad:SetColorTexture(0, 0, 0, 1)
    blackGrad:SetGradient("VERTICAL", CreateColor(0, 0, 0, 1), CreateColor(0, 0, 0, 0))

    -- Round marker: a dark ring around a bright dot.
    local svRing = sv:CreateTexture(nil, "OVERLAY", nil, 6)
    svRing:SetSize(14, 14)
    svRing:SetTexture(M.tex.circle)
    svRing:SetVertexColor(0, 0, 0, 0.85)
    local svDot = sv:CreateTexture(nil, "OVERLAY", nil, 7)
    svDot:SetSize(10, 10)
    svDot:SetTexture(M.tex.circle)

    -- Hue strip.
    local hue = panel(frame)
    hue:SetSize(HUE_W, SV_H)
    hue:SetPoint("TOPLEFT", sv, "TOPRIGHT", 12, 0)

    local hueStops = { { 1, 0, 0 }, { 1, 1, 0 }, { 0, 1, 0 }, { 0, 1, 1 }, { 0, 0, 1 }, { 1, 0, 1 }, { 1, 0, 0 } }
    local segH = (SV_H - 4) / 6
    for i = 1, 6 do
        local seg = hue:CreateTexture(nil, "BACKGROUND", nil, 1)
        seg:SetPoint("TOPLEFT", 2, -2 - (i - 1) * segH)
        seg:SetPoint("TOPRIGHT", -2, 0)
        seg:SetHeight(segH)
        seg:SetColorTexture(1, 1, 1, 1)
        local a, b = hueStops[i], hueStops[i + 1]
        seg:SetGradient("VERTICAL", CreateColor(b[1], b[2], b[3], 1), CreateColor(a[1], a[2], a[3], 1))
    end

    local hueRim = hue:CreateTexture(nil, "OVERLAY", nil, 6)
    hueRim:SetSize(HUE_W + 4, 6)
    hueRim:SetColorTexture(0, 0, 0, 0.85)
    local hueDot = hue:CreateTexture(nil, "OVERLAY", nil, 7)
    hueDot:SetSize(HUE_W + 2, 4)
    hueDot:SetColorTexture(1, 1, 1, 1)

    -- Preview swatch + hex field.
    local prevBox = CreateFrame("Frame", nil, frame)
    prevBox:SetSize(44, 24)
    prevBox:SetPoint("TOPLEFT", sv, "BOTTOMLEFT", 0, -12)
    N.SkinRound(prevBox, M.color.base, M.color.line, true)
    local prev = prevBox._nucFill

    local hexLabel = fs(frame, 12, M.color.textDim)
    hexLabel:SetPoint("LEFT", prevBox, "RIGHT", 12, 0)
    hexLabel:SetText("#")

    local hexBox = CreateFrame("Frame", nil, frame)
    hexBox:SetSize(84, 24)
    hexBox:SetPoint("LEFT", hexLabel, "RIGHT", 4, 0)
    N.SkinRound(hexBox, M.color.base, M.color.line, true)
    local hex = CreateFrame("EditBox", nil, hexBox)
    hex:SetPoint("TOPLEFT", 8, 0)
    hex:SetPoint("BOTTOMRIGHT", -8, 0)
    hex:SetAutoFocus(false)
    hex:SetFont(M.font, 12, "")
    N.RegisterFont(hex, 12, "")
    hex:SetTextColor(M.color.text[1], M.color.text[2], M.color.text[3])
    hex:SetMaxLetters(6)
    hex:SetScript("OnEditFocusGained", function() N.SetPanelBorder(hexBox, M.color.accent) end)
    hex:SetScript("OnEditFocusLost", function() N.SetPanelBorder(hexBox, M.color.line) end)

    -- Preset swatches (2 rows of 5).
    local cols, gap = 5, 8
    local swW = (SV_W + 12 + HUE_W - (cols - 1) * gap) / cols
    for i, hexStr in ipairs(PRESETS) do
        local pr, pg, pb = fromHex(hexStr)
        local col = (i - 1) % cols
        local row = math.floor((i - 1) / cols)
        local b = CreateFrame("Button", nil, frame)
        b:SetSize(swW, 18)
        b:SetPoint("TOPLEFT", prevBox, "BOTTOMLEFT", col * (swW + gap), -12 - row * 24)
        N.SkinRound(b, { pr, pg, pb, 1 }, M.color.line, true)
        b:SetScript("OnEnter", function(self) N.SetPanelBorder(self, M.color.accentBright) end)
        b:SetScript("OnLeave", function(self) N.SetPanelBorder(self, M.color.line) end)
        b:SetScript("OnClick", function()
            frame.h, frame.s, frame.v = rgb2hsv(pr, pg, pb)
            frame:Sync()
        end)
    end

    -- Buttons in the same style as the options window; OK in the accent colour.
    local function mkBtn(label, accent)
        local b = CreateFrame("Button", nil, frame)
        b:SetSize(100, 28)
        if accent then
            N.SkinButton(b, { rest = M.color.accent, hover = M.color.accentBright })
        else
            N.SkinButton(b)
        end
        b.text = fs(b, 12, M.color.text)
        b.text:SetPoint("CENTER")
        b.text:SetText(label)
        return b
    end
    local ok = mkBtn(OKAY, true)
    ok:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    local cancel = mkBtn(CANCEL)
    cancel:SetPoint("BOTTOMRIGHT", ok, "BOTTOMLEFT", -8, 0)

    function frame:Sync()
        local hr, hg, hb = hsv2rgb(self.h, 1, 1)
        hueTex:SetColorTexture(hr, hg, hb, 1)
        local r, g, b = currentRGB()
        prev:SetColorTexture(r, g, b, 1)
        local x = 2 + self.s * (sv:GetWidth() - 4)
        local y = -(2 + (1 - self.v) * (sv:GetHeight() - 4))
        svDot:ClearAllPoints(); svDot:SetPoint("CENTER", sv, "TOPLEFT", x, y)
        svRing:ClearAllPoints(); svRing:SetPoint("CENTER", sv, "TOPLEFT", x, y)
        svDot:SetVertexColor(1, 1, 1, 1)
        local hy = -(2 + self.h * (hue:GetHeight() - 4))
        hueDot:ClearAllPoints(); hueDot:SetPoint("CENTER", hue, "TOP", 0, hy)
        hueRim:ClearAllPoints(); hueRim:SetPoint("CENTER", hue, "TOP", 0, hy)
        if not hex:HasFocus() then hex:SetText(toHex(r, g, b)) end
        if self._onChange then self._onChange(r, g, b) end
    end

    local function updateSV()
        local x, y = scaledCursor()
        frame.s = clamp01((x - sv:GetLeft()) / sv:GetWidth())
        frame.v = clamp01(1 - (sv:GetTop() - y) / sv:GetHeight())
        frame:Sync()
    end
    local function updateHue()
        local _, y = scaledCursor()
        frame.h = clamp01((hue:GetTop() - y) / hue:GetHeight())
        frame:Sync()
    end

    frame:SetScript("OnUpdate", function()
        if (frame.dragSV or frame.dragHue) and not IsMouseButtonDown("LeftButton") then
            frame.dragSV, frame.dragHue = false, false
        end
        if frame.dragSV then updateSV() end
        if frame.dragHue then updateHue() end
    end)
    sv:EnableMouse(true)
    sv:SetScript("OnMouseDown", function() frame.dragSV = true; updateSV() end)
    sv:SetScript("OnMouseUp", function() frame.dragSV = false end)
    hue:EnableMouse(true)
    hue:SetScript("OnMouseDown", function() frame.dragHue = true; updateHue() end)
    hue:SetScript("OnMouseUp", function() frame.dragHue = false end)

    hex:SetScript("OnEnterPressed", function(self)
        local r, g, b = fromHex(self:GetText())
        if r then frame.h, frame.s, frame.v = rgb2hsv(r, g, b) end
        self:ClearFocus(); frame:Sync()
    end)
    hex:SetScript("OnEscapePressed", function(self) self:ClearFocus(); frame:Sync() end)

    ok:SetScript("OnClick", function()
        frame:Hide()
        if frame._onAccept then frame._onAccept(currentRGB()) end
    end)
    cancel:SetScript("OnClick", function()
        frame:Hide()
        if frame._onCancel then frame._onCancel() end
    end)
    close:SetScript("OnClick", function() cancel:Click() end)
    frame:SetScript("OnKeyDown", function(_, key) if key == "ESCAPE" then cancel:Click() end end)
    frame:SetScript("OnShow", function(self) self:SetPropagateKeyboardInput(false) end)
    frame:EnableKeyboard(true)

    return frame
end

-- CP:Open{ r, g, b, title=, onChange=fn(r,g,b), onAccept=fn(r,g,b), onCancel=fn() }
function CP:Open(opts)
    local f = build()
    f.title:SetText(opts.title or "")
    f.h, f.s, f.v = rgb2hsv(opts.r or 1, opts.g or 1, opts.b or 1)
    f._onAccept, f._onCancel, f._onChange = opts.onAccept, opts.onCancel, opts.onChange
    f:Show()
    f:Sync()
    if f.Raise then f:Raise() end
end
