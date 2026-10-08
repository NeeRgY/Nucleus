local _, ns = ...
local N = ns.N
local M = N.Media

-- Flat-skin primitives shared by frames and the options window: a 1px hard border, a matte fill
-- and a faint inner top highlight. No rounded corners, gradients or drop shadows.

local function unpackColor(c)
    return c[1], c[2], c[3], c[4] or 1
end

-- Pixel-snapped anchoring so every 1px line rasterizes to exactly one physical pixel at any UI
-- scale. Without it, identical SetHeight(1) textures land on different sub-pixel offsets and read
-- as different thicknesses.
local PU = PixelUtil or PixelUtil_Mixin
local function px_point(region, ...)
    if PU and PU.SetPoint then PU.SetPoint(region, ...) else region:SetPoint(...) end
end
local function px_height(region, h)
    if PU and PU.SetHeight then PU.SetHeight(region, h) else region:SetHeight(h) end
end
local function px_width(region, w)
    if PU and PU.SetWidth then PU.SetWidth(region, w) else region:SetWidth(w) end
end

-- A single hairline separator on `parent`, snapped to one physical pixel.
--   dir "h": horizontal line at y = `off`; a/b inset its left/right ends.
--   dir "v": vertical line at x = `off`; a/b inset its top/bottom ends
--            (a measured down from the top, b measured up from the bottom).
function N.Hairline(parent, dir, off, color, a, b)
    a, b = a or 0, b or 0
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetColorTexture(unpackColor(color or M.color.border))
    if dir == "v" then
        px_point(t, "TOPLEFT", parent, "TOPLEFT", off, -a)
        px_point(t, "BOTTOMLEFT", parent, "BOTTOMLEFT", off, b)
        px_width(t, 1)
    elseif dir == "hb" then
        px_point(t, "BOTTOMLEFT", parent, "BOTTOMLEFT", a, off)
        px_point(t, "BOTTOMRIGHT", parent, "BOTTOMRIGHT", -b, off)
        px_height(t, 1)
    else
        px_point(t, "TOPLEFT", parent, "TOPLEFT", a, off)
        px_point(t, "TOPRIGHT", parent, "TOPRIGHT", -b, off)
        px_height(t, 1)
    end
    return t
end

-- Apply the matte panel look to any frame. Creates 4 edge lines + optional
-- fill on first call, reuses them afterwards. borderColor defaults to hard
-- black; pass M.color.borderSoft for the lighter card/nav treatment.
function N.SkinPanel(frame, fillColor, borderColor, noHighlight)
    if not frame._nucFill then
        local fill = frame:CreateTexture(nil, "BACKGROUND")
        fill:SetTexture(M.flat)
        fill:SetAllPoints()
        frame._nucFill = fill

        local bc = borderColor or M.color.border
        local function line()
            local t = frame:CreateTexture(nil, "BORDER")
            t:SetTexture(M.flat)
            t:SetColorTexture(unpackColor(bc))
            return t
        end
        local top, bottom, left, right = line(), line(), line(), line()
        px_point(top, "TOPLEFT", frame, "TOPLEFT", 0, 0)
        px_point(top, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        px_height(top, 1)
        px_point(bottom, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        px_point(bottom, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        px_height(bottom, 1)
        px_point(left, "TOPLEFT", frame, "TOPLEFT", 0, 0)
        px_point(left, "BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        px_width(left, 1)
        px_point(right, "TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        px_point(right, "BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        px_width(right, 1)
        frame._nucBorder = { top, bottom, left, right }

        if not noHighlight then
            local hl = frame:CreateTexture(nil, "ARTWORK")
            hl:SetTexture(M.flat)
            hl:SetColorTexture(unpackColor(M.color.borderInner))
            hl:SetPoint("TOPLEFT", 1, -1)
            hl:SetPoint("TOPRIGHT", -1, -1)
            hl:SetHeight(1)
        end
    end
    frame._nucFill:SetColorTexture(unpackColor(fillColor or M.color.frameBg))
end

-- Rounded skin for the options UI. Same contract as SkinPanel (frame._nucFill, frame._nucBorder,
-- N.SetPanelBorder keep working), but fill and 1px rim are 9-sliced rounded-rect textures.
-- SetVertexColor tints them, so each texture gets a SetColorTexture shim that routes to it and
-- every existing fill:SetColorTexture(r,g,b,a) call stays untouched.
local function tintable(tex)
    tex.SetColorTexture = function(self, r, g, b, a) self:SetVertexColor(r, g, b, a or 1) end
    return tex
end

local function sliced(tex, path, margin)
    tex:SetTexture(path)
    if tex.SetTextureSliceMargins then
        tex:SetTextureSliceMargins(margin, margin, margin, margin)
    end
end

function N.SkinRound(frame, fillColor, borderColor, small)
    if not frame._nucFill then
        local path, margin = M.tex.round, 9
        if small then path, margin = M.tex.roundSm, 5 end

        local rim = tintable(frame:CreateTexture(nil, "BACKGROUND", nil, -2))
        sliced(rim, path, margin)
        rim:SetAllPoints()
        rim:SetColorTexture(unpackColor(borderColor or M.color.line))

        local fill = tintable(frame:CreateTexture(nil, "BACKGROUND", nil, -1))
        sliced(fill, path, margin)
        fill:SetPoint("TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMRIGHT", -1, 1)

        frame._nucFill = fill
        frame._nucBorder = { rim }
    end
    frame._nucFill:SetColorTexture(unpackColor(fillColor or M.color.card))
end

-- Soft drop shadow behind a frame: one 9-sliced texture that bleeds past the
-- frame edge (textures are not clipped to their frame). `spread` is how far it
-- reaches; the source texture keeps its solid core 14px in from its own edge.
function N.AddShadow(frame, spread, alpha, dy)
    spread = spread or 14
    local sh = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    sliced(sh, M.tex.shadow, 28)
    sh:SetVertexColor(0, 0, 0, alpha or 0.6)
    sh:SetPoint("TOPLEFT", frame, "TOPLEFT", -spread, spread + (dy or -4))
    sh:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", spread, -spread + (dy or -4))
    return sh
end

-- A crisp X built from two rotated bars (no glyph, so it centres exactly).
-- Returns a function that tints both bars.
function N.MakeCross(parent, size, thick)
    local bars = {}
    for i, rot in ipairs({ 45, -45 }) do
        local t = parent:CreateTexture(nil, "OVERLAY")
        t:SetTexture(M.flat)
        t:SetSize(size, thick or 2)
        t:SetPoint("CENTER")
        t:SetRotation(math.rad(rot))
        bars[i] = t
    end
    return function(r, g, b, a)
        for _, t in ipairs(bars) do t:SetVertexColor(r, g, b, a or 1) end
    end
end

-- Control button: rounded, raised fill that lifts on hover, accent hold when
-- marked active. Adds btn:SetActiveState(bool).
function N.SkinButton(btn, opts)
    opts = opts or {}
    local rest   = opts.rest   or M.color.base
    local hover  = opts.hover  or M.color.baseHover
    local active = opts.active or M.color.navActive
    N.SkinRound(btn, rest, M.color.line, true)

    local function paint()
        local c = btn._nucActive and active or (btn._nucHover and hover or rest)
        btn._nucFill:SetColorTexture(unpackColor(c))
    end
    btn:HookScript("OnEnter", function() btn._nucHover = true; paint() end)
    btn:HookScript("OnLeave", function() btn._nucHover = false; paint() end)
    btn.SetActiveState = function(_, on)
        btn._nucActive = on and true or false
        paint()
    end
    paint()
    N.OnRecolor(paint)
end

function N.SetPanelBorder(frame, color)
    if not frame._nucBorder then return end
    for _, t in ipairs(frame._nucBorder) do
        t:SetColorTexture(unpackColor(color))
    end
end

-- Turns a StatusBar into a flat bar with a dark loss region behind it and a 1px top highlight
-- across the full width, so the bar reads as one surface regardless of its value.
function N.SkinBar(bar)
    bar:SetStatusBarTexture(M.flat)
    if not bar._nucLoss then
        local loss = bar:CreateTexture(nil, "BACKGROUND")
        loss:SetTexture(M.flat)
        loss:SetColorTexture(unpackColor(M.color.healthLoss))
        loss:SetAllPoints()
        bar._nucLoss = loss
        bar:GetStatusBarTexture():SetDrawLayer("ARTWORK")

        local shine = bar:CreateTexture(nil, "ARTWORK", nil, 2)
        shine:SetTexture(M.flat)
        shine:SetColorTexture(1, 1, 1, 0.10)
        shine:SetPoint("TOPLEFT")
        shine:SetPoint("TOPRIGHT")
        shine:SetHeight(1)
        bar._nucShine = shine
    end
end

-- Swap a skinned bar's fill texture (Appearance > Color > Bar texture). Call
-- N.SkinBar first. The caller must re-apply SetStatusBarColor afterwards -
-- changing the texture resets the fill's tint to white.
function N.SetBarTexture(bar, key)
    bar:SetStatusBarTexture(M.barTextures[key] or M.flat)
    local tex = bar:GetStatusBarTexture()
    if tex then tex:SetDrawLayer("ARTWORK") end
end

function N.SetBarLossColor(bar, color)
    if bar._nucLoss then bar._nucLoss:SetColorTexture(unpackColor(color or M.color.healthLoss)) end
end

-- Fonts (General > Interface / Fonts): every text made here is remembered with its base size.
-- Texts inside the options window (a root frame flagged _nucUI) use the window font and the
-- font scale; texts under a root flagged _nucFace use the window font without scaling (dialogs).
-- Everything else is frame text: it only follows the frame font and keeps its own size.
local fontRegistry = setmetatable({}, { __mode = "k" })
local fontPending

local function uiKind(obj)
    if obj._nucForceUI then return "ui" end
    local p = obj:GetParent()
    while p do
        if p._nucFrameText then return nil end
        if p._nucUI then return "ui" end
        if p._nucFace then return "face" end
        p = p:GetParent()
    end
    return nil
end

function N.ApplyFontScale()
    local s = (N.db and N.db.fontScale) or 1
    for obj in pairs(fontRegistry) do
        local kind = uiKind(obj)
        local font = kind and M.fontUI or M.font
        local scale = (kind == "ui") and s or 1
        if obj._nucFont ~= font or (kind == "ui" and obj._nucScale ~= scale) then
            if kind then
                obj:SetFont(font, obj._nucBase * scale, obj._nucFlags)
            else
                -- frame text: keep the size the layout code gave it, only swap the face
                local _, size, flags = obj:GetFont()
                obj:SetFont(font, (size and size > 0) and size or obj._nucBase, flags or obj._nucFlags)
            end
            obj._nucFont, obj._nucScale = font, scale
        end
    end
end

local function scheduleFontScale()
    if fontPending then return end
    fontPending = true
    C_Timer.After(0, function()
        fontPending = false
        N.ApplyFontScale()
    end)
end

function N.RegisterFont(obj, size, flags)
    obj._nucBase = size
    obj._nucFlags = flags or ""
    fontRegistry[obj] = true
    scheduleFontScale()
end

function N.FontString(parent, size, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(uiKind(fs) and M.fontUI or M.font, size or 12, "OUTLINE")
    fs:SetTextColor(unpackColor(M.color.text))
    N.RegisterFont(fs, size or 12, "OUTLINE")
    return fs
end

