local _, ns = ...
local N = ns.N
local M = N.Media

-- Aura engine (Retail 12.1+)
--
-- Since 12.1 addon code can't read a unit's auras in combat (every field is sealed), but it can
-- still display them: the game's own AuraContainer frame is told which auras to show (a filter
-- string like "HELPFUL|PLAYER" plus an optional list of spell IDs) and creates, fills and drives
-- the icon buttons itself. We create the container, say how its buttons look (initializeFrame),
-- where it sits and which unit it watches.
--
--   E.Supported()              -> bool (needs a non-combat first call)
--   E.Apply(button, id, spec)  -> build / retune one container; spec = nil removes it
--   E.Remove(button, id)
--
-- spec = {
--   groups = { { key, filter, candidate = {...}, max, token (dispel type), border = {r,g,b} }, ...
--     },
--   shape  = "icon" | "rect" | "bar" | "border" | "overlay" | "text" | "dispel",
--   size, spacing, point, x, y, growth, max,
--   cd = "spiral" | "vertical" | "none", stacks, time, timeSize, timeX, timeY, stackSize, stackX,
--     stackY,
--   timeColor = { seconds, color }, color = {r,g,b}, width, height, thickness, opacity, around,
--     text, fill,
--   dispel = { ... }  (shape "dispel": highlight, border, type-icon settings)
-- }
--
-- Containers can't be created in combat (the game errors), so structural changes wait for it to
-- end. Numeric things (size, spacing, position, font sizes) are applied live to the buttons the
-- container has handed out.

local E = {}
N.AuraEngine = E

local state = setmetatable({}, { __mode = "k" }) -- button -> { [id] = handle }
local supported

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- v UI units as whole physical pixels at the frame's scale. Plain 1-unit insets land on different
-- sub-pixels at opposite corners when the UI scale isn't 1, which made two edges of an icon look
-- thicker.
local function snap(frame, v)
    local PU = _G.PixelUtil
    if PU and PU.GetNearestPixelSize and frame and frame.GetEffectiveScale then
        local s = frame:GetEffectiveScale()
        if s and s > 0 then
            local r = PU.GetNearestPixelSize(math.abs(v), s, 1)
            return v < 0 and -r or r
        end
    end
    return v
end

local function loadModule()
    if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
end

function E.Supported()
    if supported ~= nil then return supported end
    local toc = select(4, GetBuildInfo())
    if type(toc) ~= "number" or toc < 120100 then supported = false return false end
    if InCombatLockdown() then return false end -- creating a container in combat is a hard error
    loadModule()
    local ok, f = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    supported = (ok and f and type(f.AddAuraGroup) == "function") and true or false
    if f then pcall(f.Hide, f) end
    return supported
end

--------------------------------------------------------------------------------
-- formatters
--------------------------------------------------------------------------------

-- The countdown text is a formatter over the remaining seconds: bands switch the number format
-- (whole seconds, or tenths below `decimals`) and the color (red below `seconds`). The game
-- evaluates it, so it works while the aura's timing is hidden.
local formatters = {}
local function hex(c)
    return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- A highlight tinting the health bar must sit BELOW the frame's texts and icons. The aura buttons
-- live in frames above them, so the tint gets its own frame, just above the health bar's
-- absorb/heal overlays and below the indicator overlay. It is a child of the button, so it shows
-- and hides with it.
local function lowLayer(button, owner)
    local host = owner.health or owner
    local f = CreateFrame("Frame", nil, button)
    f:SetAllPoints(host)
    f:SetFrameLevel(host:GetFrameLevel() + 3)
    return f
end
local function formatterFor(tc)
    local on = tc and tc.enabled
    local T = on and tonumber(tc.seconds) or 0
    local D = tonumber(tc and tc.decimals) or 0
    if T > 60 then T = 60 end
    if D > 60 then D = 60 end
    local col = (tc and tc.color) or { 1, 0.15, 0.15 }
    local key = ("%s|%s|%s,%s,%s"):format(T, D, col[1], col[2], col[3])
    if formatters[key] ~= nil then return formatters[key] or nil end
    formatters[key] = false
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Enum and Enum.NumericRuleFormatRounding) then
        return nil
    end
    local up, down = Enum.NumericRuleFormatRounding.Up, Enum.NumericRuleFormatRounding.Down
    local bounds, seen = {}, {}
    for _, b in ipairs({ 0, D, T }) do
        if (b == 0 or b > 0) and not seen[b] then seen[b] = true; bounds[#bounds + 1] = b end
    end
    table.sort(bounds)
    local points = {}
    for _, s in ipairs(bounds) do
        local dec, colored = D > 0 and s < D, T > 0 and s < T
        local f = dec and "%.1f" or "%d"
        if colored then f = hex(col) .. f .. "|r" end
        points[#points + 1] = { threshold = s, format = f, step = dec and 0.1 or 1, rounding = dec and down or up }
    end
    local last = bounds[#bounds]
    for _, u in ipairs({ { 60, "m" }, { 3600, "h" }, { 86400, "d" } }) do
        if u[1] > last then
            points[#points + 1] = { threshold = u[1], format = "%d" .. u[2], step = 1, rounding = down,
                components = { { div = u[1] } } }
        end
    end
    local f = C_StringUtil.CreateNumericRuleFormatter()
    if pcall(f.SetBreakpoints, f, points) then formatters[key] = f end
    return formatters[key] or nil
end
--------------------------------------------------------------------------------
-- button construction (initializeFrame)
--------------------------------------------------------------------------------

local function pulseGroup(region, duration)
    local ag = region:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.25)
    a:SetSmoothing("IN_OUT")
    a:SetDuration(duration or 0.5)
    ag:Play()
    return ag, a
end

-- Frame-wide glows (custom indicator "Glow", also the preview). Only what the game animates by
-- itself, no Lua per frame:
--   pulse  a ring (a mask hollows a white texture) fading in and out
--   halo   a soft glow fading in and out
--   pixel dashes marching round the edge: tiled strips that a translation animation slides by
--     exactly one period, clipped to the edge
--   E.NewGlow(parentFrame, anchorFrame) -> g; g:Show(style, r, g, b, offset, thickness, speed,
--     length); g:Hide()
local PROC_ATLAS = "UI-HUD-ActionBar-Proc-Loop-Flipbook"

local function loopingAlpha(region, duration)
    local ag = region:CreateAnimationGroup()
    ag:SetLooping("REPEAT")
    local out = ag:CreateAnimation("Alpha")
    out:SetOrder(1); out:SetFromAlpha(1); out:SetToAlpha(0.25); out:SetDuration(duration or 0.5)
    local back = ag:CreateAnimation("Alpha")
    back:SetOrder(2); back:SetFromAlpha(0.25); back:SetToAlpha(1); back:SetDuration(duration or 0.5)
    return ag, out, back
end

function E.NewGlow(parent, anchor)
    local g = {}
    local wrap = CreateFrame("Frame", nil, parent)
    wrap:EnableMouse(false)
    wrap:SetFrameLevel((anchor:GetFrameLevel() or 1) + 60)
    wrap:Hide()
    local ring, halo, strips

    local function pin(pad)
        wrap:ClearAllPoints()
        wrap:SetPoint("TOPLEFT", anchor, "TOPLEFT", -pad, pad)
        wrap:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", pad, -pad)
    end

    local function stopStrips()
        if not strips then return end
        for _, s in ipairs(strips) do s.ag:Stop(); s.clip:Hide() end
    end

    function g:Hide()
        if ring then ring.ag:Stop(); ring.tex:Hide() end
        if halo then halo.ag:Stop(); halo.tex:Hide() end
        stopStrips()
        wrap:Hide()
    end

    -- One side of a marching ring. side: "top" (moves right), "right" (down),
    -- "bottom" (left), "left" (up).
    local function makeStrip()
        local clip = CreateFrame("Frame", nil, wrap)
        clip:EnableMouse(false)
        clip:SetClipsChildren(true)
        local tex = clip:CreateTexture(nil, "OVERLAY")
        local ag = tex:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local move = ag:CreateAnimation("Translation")
        return { clip = clip, tex = tex, ag = ag, move = move }
    end

    local function layoutStrip(s, side, inset, th, period, seconds, W, H, texPath, r, gr, b, reverse)
        local clip, tex = s.clip, s.tex
        clip:ClearAllPoints()
        tex:ClearAllPoints()
        local horizontal = (side == "top" or side == "bottom")
        local len = horizontal and (W - 2 * inset) or (H - 2 * inset - 2 * th)
        if len < period then s.ag:Stop(); clip:Hide() return end
        if side == "top" then
            clip:SetPoint("TOPLEFT", wrap, "TOPLEFT", inset, -inset)
            clip:SetPoint("TOPRIGHT", wrap, "TOPRIGHT", -inset, -inset)
            clip:SetHeight(th)
        elseif side == "bottom" then
            clip:SetPoint("BOTTOMLEFT", wrap, "BOTTOMLEFT", inset, inset)
            clip:SetPoint("BOTTOMRIGHT", wrap, "BOTTOMRIGHT", -inset, inset)
            clip:SetHeight(th)
        elseif side == "right" then
            clip:SetPoint("TOPRIGHT", wrap, "TOPRIGHT", -inset, -inset - th)
            clip:SetPoint("BOTTOMRIGHT", wrap, "BOTTOMRIGHT", -inset, inset + th)
            clip:SetWidth(th)
        else
            clip:SetPoint("TOPLEFT", wrap, "TOPLEFT", inset, -inset - th)
            clip:SetPoint("BOTTOMLEFT", wrap, "BOTTOMLEFT", inset, inset + th)
            clip:SetWidth(th)
        end
        -- Going round clockwise: top moves right, right side down, bottom left, left side up.
        -- `reverse` goes the other way. The strip is one period longer than the clip, on the side
        -- it slides in from.
        if horizontal then
            if (side == "top") ~= (reverse == true) then
                tex:SetPoint("TOPLEFT", clip, "TOPLEFT", -period, 0)
                tex:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, 0)
                s.move:SetOffset(period, 0)
            else
                tex:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, 0)
                tex:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", period, 0)
                s.move:SetOffset(-period, 0)
            end
        else
            if (side == "right") ~= (reverse == true) then
                tex:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, period)
                tex:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, 0)
                s.move:SetOffset(0, -period)
            else
                tex:SetPoint("TOPLEFT", clip, "TOPLEFT", 0, 0)
                tex:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, -period)
                s.move:SetOffset(0, period)
            end
        end
        s.move:SetDuration(seconds)
        tex:SetTexture(texPath, "REPEAT", "REPEAT")
        local n = (len + period) / period
        if horizontal then tex:SetTexCoord(0, n, 0, 1)
        else tex:SetTexCoord(0, 0, n, 0, 0, 1, n, 1) end
        tex:SetVertexColor(r, gr, b, 1)
        clip:Show()
        s.ag:Play()
    end
    function g:Show(style, r, gr, b, off, th, speed, length)
        self:Hide()
        if style == "autocast" then style = "pixel" end -- the removed "Sparks" style
        if style == "proc" then style = "pulse" end     -- the removed "Proc border" style
        off, th = off or 0, math.max(1, th or 2)
        speed = math.max(0.05, speed or 0.3)
        local aw, ah = anchor:GetSize()
        if not aw or aw < 4 then aw = 66 end
        if not ah or ah < 4 then ah = 46 end
        wrap:Show()

        if style == "halo" then
            pin(0)
            if not halo then
                local tex = wrap:CreateTexture(nil, "BACKGROUND")
                tex:SetTexture(M.tex.shadow)
                if tex.SetTextureSliceMargins then tex:SetTextureSliceMargins(28, 28, 28, 28) end
                local ag, out, back = loopingAlpha(tex, 0.5)
                halo = { tex = tex, ag = ag, out = out, back = back }
            end
            local spread = 8 + off + th * 2
            halo.tex:ClearAllPoints()
            halo.tex:SetPoint("TOPLEFT", wrap, "TOPLEFT", -spread, spread)
            halo.tex:SetPoint("BOTTOMRIGHT", wrap, "BOTTOMRIGHT", spread, -spread)
            halo.tex:SetVertexColor(r, gr, b, 1)
            local d = math.max(0.2, 1 / math.max(0.1, speed * 3))
            halo.out:SetDuration(d); halo.back:SetDuration(d)
            halo.tex:Show(); halo.ag:Play()
        elseif style == "pixel" then
            pin(off + th)
            strips = strips or {}
            for i = 1, 4 do strips[i] = strips[i] or makeStrip() end
            local W, H = aw + 2 * (off + th), ah + 2 * (off + th)
            local period = math.max(6, 2 * (length or 8))
            local secs = math.max(0.05, period / (speed * 2 * (W + H)))
            for i, side in ipairs({ "top", "right", "bottom", "left" }) do
                layoutStrip(strips[i], side, 0, th, period, secs, W, H, M.tex.glowDash, r, gr, b)
            end        else
            pin(off + th)
            if not ring then
                local tex = wrap:CreateTexture(nil, "OVERLAY", nil, 7)
                tex:SetTexture(WHITE)
                tex:SetAllPoints(wrap)
                local mask = wrap:CreateMaskTexture()
                mask:SetTexture(M.tex.empty, "CLAMPTOWHITE", "CLAMPTOWHITE")
                tex:AddMaskTexture(mask)
                local ag, out, back = loopingAlpha(tex, 0.5)
                ring = { tex = tex, mask = mask, ag = ag, out = out, back = back }
            end
            ring.mask:ClearAllPoints()
            ring.mask:SetPoint("TOPLEFT", ring.tex, "TOPLEFT", th, -th)
            ring.mask:SetPoint("BOTTOMRIGHT", ring.tex, "BOTTOMRIGHT", -th, th)
            ring.tex:SetVertexColor(r, gr, b, 1)
            local d = math.max(0.2, 1 / math.max(0.1, speed * 3))
            ring.out:SetDuration(d); ring.back:SetDuration(d)
            ring.tex:Show(); ring.ag:Play()
        end
    end
    return g
end

local function edgeStrips(button, thickness, r, g, b, dispel)
    thickness = snap(button, thickness)
    local parts = {}
    local function strip()
        local t = button:CreateTexture(nil, "OVERLAY")
        t:SetColorTexture(r, g, b, 1)
        return t
    end
    local top = strip()
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(thickness)
    local bottom = strip()
    bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(thickness)
    local left = strip()
    left:SetPoint("TOPLEFT", 0, -thickness); left:SetPoint("BOTTOMLEFT", 0, thickness); left:SetWidth(thickness)
    local right = strip()
    right:SetPoint("TOPRIGHT", 0, -thickness); right:SetPoint("BOTTOMRIGHT", 0, thickness); right:SetWidth(thickness)
    parts = { top, bottom, left, right }
    if dispel then
        -- The game colours these by the aura's dispel type itself.
        local style = Enum and Enum.CustomAuraButtonDispelTypeTextureStyle
            and Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset
        local add = button.AddDispelTypeTexture or button.SetAuraBorder
        if style and add then
            for _, t in ipairs(parts) do
                t:Hide()
                pcall(add, button, t, { style = style, showWhenHarmful = true, showWhenHelpful = false })
            end
        end
    end
    return parts
end

local function animation(button, kind)
    if kind == "vertical" and type(button.SetDurationBar) == "function" then
        local bar = CreateFrame("StatusBar", nil, button)
        bar:SetAllPoints(button)
        bar:EnableMouse(false)
        bar:SetOrientation("VERTICAL")
        bar:SetReverseFill(true)
        bar:SetStatusBarTexture(WHITE)
        local tex = bar:GetStatusBarTexture()
        if tex then tex:SetVertexColor(0, 0, 0, 0.6) end
        local opts = {}
        if Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime then
            opts.direction = Enum.StatusBarTimerDirection.ElapsedTime
        end
        if Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate then
            opts.interpolation = Enum.StatusBarInterpolation.Immediate
        end
        pcall(button.SetDurationBar, button, bar, opts)
        return bar
    end
    local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cd:SetAllPoints(button)
    cd:EnableMouse(false)
    cd:SetDrawBling(false)
    cd:SetDrawEdge(false)
    cd:SetHideCountdownNumbers(true)
    if kind == "none" then
        cd:SetSwipeColor(0, 0, 0, 0)
    else
        cd:SetReverse(true)
        cd:SetSwipeTexture(WHITE)
        cd:SetSwipeColor(0, 0, 0, 0.6)
    end
    pcall(button.SetDurationCooldown, button, cd)
    return cd
end

-- Numbers (sizes, font sizes, positions) that can change without a rebuild.
local function restyle(button, spec)
    local sz = button._nuc
    if not sz then return end
    if spec.shape == "dispel" then
        local d = spec.dispel
        if d.showIcons then
            pcall(button.SetSize, button, spec.size, spec.size)
        elseif d.typeIcons then
            pcall(button.SetSize, button, d.typeIconSize, d.typeIconSize)
        else
            pcall(button.SetSize, button, 0.001, 0.001)
        end
        if sz.typeTex then pcall(sz.typeTex.SetShown, sz.typeTex, d.typeIcons and not d.showIcons) end
        return
    end
    if spec.shape == "rect" or spec.shape == "bar" then
        pcall(button.SetSize, button, spec.width or 12, spec.height or 12)
    elseif spec.shape == "border" or spec.shape == "overlay" or spec.shape == "glow" then
        pcall(button.SetSize, button, 0.001, 0.001)
    elseif spec.shape == "text" then
        pcall(button.SetSize, button, 0.001, 0.001)
    else
        pcall(button.SetSize, button, spec.size or 16, spec.size or 16)
    end
    if sz.count then
        pcall(function()
            sz.count:SetFont(M.font, spec.stackSize or 10, "OUTLINE")
            sz.count:ClearAllPoints()
            sz.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", spec.stackX or 1, spec.stackY or -1)
        end)
    end
    if sz.time then
        pcall(function()
            sz.time:SetFont(M.font, spec.timeSize or 10, "OUTLINE")
            sz.time:ClearAllPoints()
            sz.time:SetPoint("CENTER", button, "CENTER", spec.timeX or 0, spec.timeY or 0)
        end)
    end
    if sz.label then
        pcall(sz.label.SetFont, sz.label, M.font, spec.fontSize or 12, "OUTLINE")
    end
end

local function bindTime(button, fs, spec)
    pcall(button.SetDurationText, button, fs, { textFormatter = formatterFor(spec.timeColor) })
end

local function initButton(h, group)
    return function(button)
        local spec = h.spec
        h.buttons[button] = true
        pcall(button.SetMouseClickEnabled, button, false)
        pcall(button.SetMouseMotionEnabled, button, false)

        if not button._nuc then
            local sz = {}
            button._nuc = sz
            local shape = spec.shape
            local b = h.owner
            if shape ~= "icon" and shape ~= "dispel" then
                -- The engine wants an icon bound to every button it manages; these
                -- shapes show none of their own.
                local hidden = button:CreateTexture(nil, "ARTWORK")
                hidden:SetAllPoints(button)
                hidden:SetAlpha(0)
                pcall(button.SetIcon, button, hidden)
            end
            if shape == "dispel" then
                local d, token = spec.dispel, group.token
                local col = group.rgb or { 1, 1, 1 }
                local health = b.health
                if d.highlight and d.highlight ~= "none" and health then
                    local tex = lowLayer(button, b):CreateTexture(nil, "ARTWORK", nil, 3)
                    tex:SetTexture(WHITE)
                    local ht, op = d.highlight, (d.opacity or 50) / 100
                    if ht == "fill" then
                        tex:SetPoint("TOPLEFT", health, "TOPLEFT")
                        tex:SetPoint("BOTTOMRIGHT", health:GetStatusBarTexture() or health, "BOTTOMRIGHT")
                        tex:SetVertexColor(col[1], col[2], col[3], op)
                    elseif ht == "full" then
                        tex:SetAllPoints(b)
                        tex:SetVertexColor(col[1], col[2], col[3], math.max(op, 0.1))
                    else
                        if ht == "edge-top" then
                            tex:SetPoint("TOPLEFT", health, "TOPLEFT")
                            tex:SetPoint("BOTTOMRIGHT", health, "RIGHT")
                        else
                            tex:SetPoint("TOPLEFT", health, "LEFT")
                            tex:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT")
                        end
                        tex:SetVertexColor(1, 1, 1, 1)
                        local strong, none = CreateColor(col[1], col[2], col[3], 0.8), CreateColor(col[1], col[2], col[3], 0)
                        if ht == "edge-top" then pcall(tex.SetGradient, tex, "VERTICAL", none, strong)
                        else pcall(tex.SetGradient, tex, "VERTICAL", strong, none) end
                    end
                end
                if d.frameBorder and health then
                    local th = snap(button, d.frameBorderThickness or 2)
                    local function strip() local t = button:CreateTexture(nil, "ARTWORK", nil, 5); t:SetColorTexture(col[1], col[2], col[3], 1); return t end
                    local t1 = strip(); t1:SetPoint("TOPLEFT", health); t1:SetPoint("TOPRIGHT", health); t1:SetHeight(th)
                    local t2 = strip(); t2:SetPoint("BOTTOMLEFT", health); t2:SetPoint("BOTTOMRIGHT", health); t2:SetHeight(th)
                    local t3 = strip(); t3:SetPoint("TOPLEFT", health, "TOPLEFT", 0, -th); t3:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, th); t3:SetWidth(th)
                    local t4 = strip(); t4:SetPoint("TOPRIGHT", health, "TOPRIGHT", 0, -th); t4:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, th); t4:SetWidth(th)
                end
                if d.showIcons then
                    local icon = button:CreateTexture(nil, "ARTWORK", nil, 6)
                    icon:SetAllPoints(button)
                    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    pcall(button.SetIcon, button, icon)
                    animation(button, "none")
                else
                    local t = button:CreateTexture(nil, "OVERLAY", nil, 3)
                    t:SetAllPoints(button)
                    local atlas = group.atlas
                    if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
                        t:SetAtlas(atlas)
                    elseif token == "Bleed" then
                        t:SetTexture(132302)
                        t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    else
                        t:SetTexture(WHITE)
                        t:SetVertexColor(col[1], col[2], col[3], 1)
                    end
                    sz.typeTex = t
                end
            elseif shape == "border" then
                local anchor = (spec.around == "health" and b.health) or b
                local th = snap(button, spec.thickness or 2)
                local c = spec.color or { 1, 1, 1 }
                local function strip() local t = button:CreateTexture(nil, "OVERLAY", nil, 6); t:SetColorTexture(c[1], c[2], c[3], 1); return t end
                local t1 = strip(); t1:SetPoint("TOPLEFT", anchor); t1:SetPoint("TOPRIGHT", anchor); t1:SetHeight(th)
                local t2 = strip(); t2:SetPoint("BOTTOMLEFT", anchor); t2:SetPoint("BOTTOMRIGHT", anchor); t2:SetHeight(th)
                local t3 = strip(); t3:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -th); t3:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, th); t3:SetWidth(th)
                local t4 = strip(); t4:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, -th); t4:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, th); t4:SetWidth(th)
            elseif shape == "overlay" then
                local c = spec.color or { 1, 1, 1 }
                local t = lowLayer(button, b):CreateTexture(nil, "ARTWORK", nil, 4)
                t:SetTexture(WHITE)
                if spec.isColor then
                    local c2 = spec.color2 or c
                    local a, z = CreateColor(c[1], c[2], c[3], 1), CreateColor(c2[1], c2[2], c2[3], 1)
                    if N.CustomIndicators and N.CustomIndicators.AnchorArea then
                        N.CustomIndicators.AnchorArea(t, b, spec.colorArea)
                    end
                    if spec.colorMode == "gradient-v" then t:SetGradient("VERTICAL", z, a)
                    elseif spec.colorMode == "gradient-h" then t:SetGradient("HORIZONTAL", a, z)
                    else t:SetGradient("HORIZONTAL", a, a) end
                    t:SetAlpha(spec.opacity or 1)
                else
                    t:SetAllPoints(b.health or b)
                    t:SetVertexColor(c[1], c[2], c[3], spec.opacity or 0.35)
                end
            elseif shape == "rect" or shape == "bar" then
                local c = spec.color or { 1, 0.8, 0.2 }
                local back = button:CreateTexture(nil, "BACKGROUND")
                back:SetAllPoints(button)
                back:SetColorTexture(0, 0, 0, spec.isColor and 0 or 0.6)
                if shape == "bar" and type(button.SetDurationBar) == "function" then
                    local bar = CreateFrame("StatusBar", nil, button)
                    bar:SetPoint("TOPLEFT", snap(button, 1), snap(button, -1))
                    bar:SetPoint("BOTTOMRIGHT", snap(button, -1), snap(button, 1))
                    bar:EnableMouse(false)
                    bar:SetStatusBarTexture(WHITE)
                    local tex = bar:GetStatusBarTexture()
                    if tex then tex:SetVertexColor(c[1], c[2], c[3], 1) end
                    local fill = spec.fill or "left"
                    bar:SetOrientation((fill == "up" or fill == "down") and "VERTICAL" or "HORIZONTAL")
                    bar:SetReverseFill(fill == "right" or fill == "down")
                    local opts = {}
                    if Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime then
                        opts.direction = Enum.StatusBarTimerDirection.RemainingTime
                    end
                    if Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate then
                        opts.interpolation = Enum.StatusBarInterpolation.Immediate
                    end
                    pcall(button.SetDurationBar, button, bar, opts)
                else
                    local fillTex = button:CreateTexture(nil, "ARTWORK")
                    fillTex:SetPoint("TOPLEFT", snap(button, 1), snap(button, -1))
                    fillTex:SetPoint("BOTTOMRIGHT", snap(button, -1), snap(button, 1))
                    if spec.isColor then
                        local c2 = spec.color2 or c
                        local a, z = CreateColor(c[1], c[2], c[3], 1), CreateColor(c2[1], c2[2], c2[3], 1)
                        fillTex:SetTexture(WHITE)
                        if spec.colorMode == "gradient-v" then fillTex:SetGradient("VERTICAL", z, a)
                        elseif spec.colorMode == "gradient-h" then fillTex:SetGradient("HORIZONTAL", a, z)
                        else fillTex:SetGradient("HORIZONTAL", a, a) end
                        fillTex:SetAlpha(spec.opacity or 1)
                        fillTex:ClearAllPoints()
                        fillTex:SetAllPoints(button)
                    else
                        fillTex:SetColorTexture(c[1], c[2], c[3], 1)
                    end
                end
            elseif shape == "glow" then
                local c = spec.color or { 1, 1, 1 }
                local host = CreateFrame("Frame", nil, button)
                host:EnableMouse(false)
                sz.glow = E.NewGlow(host, b)
                sz.glow:Show(spec.glow or "pixel", c[1], c[2], c[3], spec.offset or 0, spec.thickness or 2, spec.speed or 0.3, spec.length or 8)
            elseif shape == "text" then
                local host = CreateFrame("Frame", nil, button)
                host:SetAllPoints(button)
                host:EnableMouse(false)
                local fs = host:CreateFontString(nil, "OVERLAY")
                fs:SetPoint("CENTER")
                fs:SetFont(M.font, spec.fontSize or 12, "OUTLINE")
                local c = spec.color or { 1, 1, 1 }
                fs:SetTextColor(c[1], c[2], c[3], 1)
                sz.label = fs
                local t = spec.text or ""
                if t:find("{stacks}", 1, true) then
                    pcall(button.SetApplicationCount, button, fs, {})
                elseif t:find("{time}", 1, true) then
                    bindTime(button, fs, spec)
                else
                    fs:SetText((t:gsub("{%w+}", "")))
                end
            else
                local back = button:CreateTexture(nil, "BACKGROUND")
                back:SetAllPoints(button)
                local fb = M.color.frameBg
                back:SetColorTexture(fb[1], fb[2], fb[3], fb[4] or 1)
                local icon = button:CreateTexture(nil, "ARTWORK")
                icon:SetPoint("TOPLEFT", snap(button, 1), snap(button, -1))
                icon:SetPoint("BOTTOMRIGHT", snap(button, -1), snap(button, 1))
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                pcall(button.SetIcon, button, icon)

                local anim = animation(button, spec.cd or "spiral")
                local host = CreateFrame("Frame", nil, button)
                host:SetAllPoints(button)
                host:EnableMouse(false)
                host:SetFrameLevel((anim.GetFrameLevel and anim:GetFrameLevel() or 1) + 4)

                local bc = group.border or M.color.border
                edgeStrips(host, 1, bc[1], bc[2], bc[3], spec.dispelBorder)

                if spec.stacks then
                    local fs = host:CreateFontString(nil, "OVERLAY")
                    fs:SetJustifyH("RIGHT")
                    fs:SetFont(M.font, spec.stackSize or 10, "OUTLINE")
                    fs:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", spec.stackX or 1, spec.stackY or -1)
                    pcall(button.SetApplicationCount, button, fs, {})
                    sz.count = fs
                end
                if spec.time then
                    local fs = host:CreateFontString(nil, "OVERLAY")
                    fs:SetFont(M.font, spec.timeSize or 10, "OUTLINE")
                    fs:SetPoint("CENTER", button, "CENTER", spec.timeX or 0, spec.timeY or 0)
                    bindTime(button, fs, spec)
                    sz.time = fs
                end
            end
        end
        restyle(button, spec)
    end
end

--------------------------------------------------------------------------------
-- containers
--------------------------------------------------------------------------------

local function sortOpts(opts)
    if AuraContainerSortMethod and AuraContainerSortMethod.Default then opts.sortMethod = AuraContainerSortMethod.Default end
    if AuraContainerSortDirection and AuraContainerSortDirection.Normal then opts.sortDirection = AuraContainerSortDirection.Normal end
end

local function layoutOf(spec)
    local w, h = spec.size or 16, spec.size or 16
    if spec.shape == "rect" or spec.shape == "bar" then w, h = spec.width or 12, spec.height or 12 end
    if spec.shape == "dispel" then
        local d = spec.dispel
        if d.showIcons then w, h = spec.size, spec.size
        elseif d.typeIcons then w, h = d.typeIconSize, d.typeIconSize
        else w, h = 0.001, 0.001 end
    end
    if spec.shape == "border" or spec.shape == "overlay" or spec.shape == "text" or spec.shape == "glow" then w, h = 0.001, 0.001 end
    local sp = spec.spacing or 1
    return { elementWidth = w, elementHeight = h, elementSpacing = sp, lineSpacing = sp }, w, h
end

local function groupOpts(h, group)
    local spec = h.spec
    local layout = layoutOf(spec)
    local o = {
        maxFrameCount = group.max or spec.max or 1,
        layout = layout,
        initializeFrame = initButton(h, group),
    }
    if group.candidate and next(group.candidate) then o.candidateFilters = group.candidate end
    sortOpts(o)
    return o
end

local function edgeSign(point)
    local ax = point:find("LEFT") and 1 or point:find("RIGHT") and -1 or 0
    local ay = point:find("BOTTOM") and 1 or point:find("TOP") and -1 or 0
    return ax, ay
end

local function anchor(h)
    local spec, c, b = h.spec, h.container, h.owner
    local point = spec.point or "CENTER"
    local ax, ay = 0, 0
    if spec.shape ~= "border" and spec.shape ~= "overlay" and spec.shape ~= "glow" then ax, ay = edgeSign(point) end
    -- The game's flow puts the first button's near edge at the container's anchor, so on a point
    -- with no left/right part (top, center, bottom) the row would start half an icon right of the
    -- middle. Pull it back so the first icon sits centered.
    local shape = spec.shape
    if (shape == "icon" or shape == "rect" or shape == "bar" or shape == "dispel")
        and not (point:find("LEFT") or point:find("RIGHT")) then
        local _, w0 = layoutOf(spec)
        ax = ax + ((spec.growth == "LEFT") and w0 / 2 or -w0 / 2)
    end
    if point:find("BOTTOM") and N.PowerInset and spec.shape ~= "border" and spec.shape ~= "overlay"
        and spec.shape ~= "glow" then
        ay = ay + N.PowerInset(b)
    end
    c:ClearAllPoints()
    c:SetPoint(point, b, point, ax + (spec.x or 0), ay + (spec.y or 0))
    c:SetSize(1, 1)

    local _, w, hgt = layoutOf(spec)
    local sp = spec.spacing or 1
    local FD = AnchorUtil and AnchorUtil.FlowDirection
    local growth = spec.growth or "RIGHT"
    if c.SetFlowLayoutAnchorPoint then pcall(c.SetFlowLayoutAnchorPoint, c, point) end
    if FD and c.SetFlowLayoutGrowthDirection then
        local hd, vd = FD.Right, FD.Down
        if growth == "LEFT" then hd = FD.Left elseif growth == "UP" then vd = FD.Up end
        pcall(c.SetFlowLayoutGrowthDirection, c, hd, vd)
    end
    if c.SetFlowLayoutMaximumLineSize then
        local n = spec.max or 1
        local line = n * w + math.max(n - 1, 0) * math.abs(sp) + 0.4
        if growth == "UP" or growth == "DOWN" then line = hgt + 0.4 end
        pcall(c.SetFlowLayoutMaximumLineSize, c, line)
    end
    local parent = h.parent
    c:SetFrameLevel((parent:GetFrameLevel() or 0) + (spec.level or 6))
end

local function tuneGroups(h)
    local c, spec = h.container, h.spec
    for _, g in ipairs(spec.groups) do
        if c.HasAuraGroup and c:HasAuraGroup(g.key) then
            local o = groupOpts(h, g)
            if c.SetAuraGroupMaxFrameCount then pcall(c.SetAuraGroupMaxFrameCount, c, g.key, o.maxFrameCount) end
            if o.candidateFilters and c.SetAuraGroupCandidateFilters then
                pcall(c.SetAuraGroupCandidateFilters, c, g.key, o.candidateFilters)
            end
            if c.SetAuraGroupLayout then pcall(c.SetAuraGroupLayout, c, g.key, o.layout) end
        end
    end
    for btn in pairs(h.buttons) do restyle(btn, spec) end
    anchor(h)
end

local function park(h)
    local c = h.container
    if not c then return end
    pcall(function()
        c:Hide()
        if c.SetUnit then c:SetUnit(nil) end
        c:ClearAllPoints()
        c:SetParent(UIParent)
        c:SetAlpha(0)
        c:SetSize(1, 1)
    end)
    h.container = nil
    h.boundUnit = nil
end

local function bindUnit(h)
    local unit = h.owner.unit
    if not unit or not h.container then return end
    if h.boundUnit ~= unit then
        pcall(h.container.SetUnit, h.container, unit)
        h.boundUnit = unit
        if h.container.UpdateAllAuras then pcall(h.container.UpdateAllAuras, h.container) end
    end
end

local function signature(spec)
    local parts = { spec.shape, spec.cd or "", tostring(spec.stacks), tostring(spec.time),
        tostring(spec.dispelBorder), spec.around or "", spec.text or "", spec.fill or "" }
    for _, g in ipairs(spec.groups) do
        parts[#parts + 1] = g.key .. ":" .. g.filter .. ":" .. tostring(g.border and g.border[1])
        if g.rgb then parts[#parts + 1] = ("%.3f,%.3f,%.3f"):format(g.rgb[1], g.rgb[2], g.rgb[3]) end
    end
    if spec.shape == "dispel" then
        local d = spec.dispel
        parts[#parts + 1] = ("%s|%s|%s|%s|%s|%s"):format(tostring(d.highlight), tostring(d.opacity),
            tostring(d.frameBorder), tostring(d.frameBorderThickness), tostring(d.showIcons), tostring(d.typeIcons))
    elseif spec.shape == "border" or spec.shape == "overlay" or spec.shape == "rect" or spec.shape == "bar" or spec.shape == "text" then
        local c = spec.color or {}
        parts[#parts + 1] = ("%s|%s|%s|%s|%s"):format(tostring(c[1]), tostring(c[2]), tostring(c[3]),
            tostring(spec.thickness), tostring(spec.opacity))
        local c2 = spec.color2 or {}
        parts[#parts + 1] = ("m%s|%s|%s|%s|%s"):format(tostring(spec.colorMode), tostring(spec.isColor) .. tostring(spec.colorArea), tostring(c2[1]), tostring(c2[2]), tostring(c2[3]))
    end

    if spec.shape == "glow" then
        local c = spec.color or {}
        parts[#parts + 1] = ("g%s|%s|%s|%s|%s|%s|%s|%s"):format(tostring(spec.glow), tostring(c[1]), tostring(c[2]),
            tostring(c[3]), tostring(spec.offset), tostring(spec.thickness), tostring(spec.speed), tostring(spec.length))
    end
    local tc = spec.timeColor
    if tc and tc.enabled then
        parts[#parts + 1] = ("tc%s|%s|%s|%s"):format(tostring(tc.seconds), tostring(tc.color and tc.color[1]),
            tostring(tc.color and tc.color[2]), tostring(tc.color and tc.color[3]))
    end
    if tc and tc.decimals then parts[#parts + 1] = "dec" .. tostring(tc.decimals) end
    return table.concat(parts, ";")
end

local function build(h)
    local spec = h.spec
    local sig = signature(spec)
    local c = h.parks and h.parks[sig]
    if c then
        h.parks[sig] = nil
        pcall(function() c:SetAlpha(1); c:SetParent(h.parent) end)
        h.container = c
        h.sig = sig
        for k in pairs(h.buttons) do h.buttons[k] = nil end
        tuneGroups(h)
        c:Show()
        bindUnit(h)
        return true
    end

    loadModule()
    local ok, created = pcall(CreateFrame, "AuraContainer", nil, h.parent, "CustomAuraContainerTemplate")
    if not ok or not created then return false end
    c = created
    h.container = c
    h.sig = sig
    anchor(h)
    if h.owner.unit and c.SetUnit then pcall(c.SetUnit, c, h.owner.unit); h.boundUnit = h.owner.unit end
    local added = 0
    for _, g in ipairs(spec.groups) do
        if pcall(c.AddAuraGroup, c, g.key, g.filter, groupOpts(h, g)) then added = added + 1 end
    end
    if added == 0 then
        park(h)
        return false
    end
    if c.SetEnabled then pcall(c.SetEnabled, c, true) end
    anchor(h)
    if c.UpdateAllAuras then pcall(c.UpdateAllAuras, c) end
    return true
end

local function handleOf(button, id)
    local map = state[button]
    if not map then map = {}; state[button] = map end
    local h = map[id]
    if not h then
        h = { owner = button, buttons = setmetatable({}, { __mode = "k" }), id = id }
        map[id] = h
    end
    return h
end

-- Takes a row's container out of play and keeps it for reuse (containers can't be destroyed). In
-- combat it is only hidden.
local function removeOne(button, id)
    local map = state[button]
    local h = map and map[id]
    if not (h and h.container) then return end
    if InCombatLockdown() then
        h.container:Hide()
        h.hidden = true
        return
    end
    local c, sig = h.container, h.sig
    park(h)
    h.parks = h.parks or {}
    h.parks[sig] = c
    h.sig = nil
end
local function applyOne(button, id, spec)
    if not spec then removeOne(button, id) return end
    local h = handleOf(button, id)
    h.spec = spec
    h.parent = button.overlay or button
    local sig = signature(spec)

    if h.container and h.sig == sig then
        if h.hidden then h.container:Show(); h.hidden = nil end
        tuneGroups(h)
        bindUnit(h)
        return
    end
    if InCombatLockdown() then
        -- Structural change: wait for the end of combat (a container cannot be made now).
        N.RunWhenSafe(function() E.Apply(button, id, h.spec) end, "auraengine-" .. tostring(button) .. id)
        if h.container then h.container:Show() end
        return
    end
    if h.container then
        local old, oldSig = h.container, h.sig
        park(h)
        h.parks = h.parks or {}
        h.parks[oldSig] = old
    end
    build(h)
end

function E.RemoveAll(button)
    local map = state[button]
    if not map then return end
    for id in pairs(map) do E.Remove(button, id) end
end
function E.Rebind(button)
    local map = state[button]
    if not map then return end
    for _, h in pairs(map) do bindUnit(h) end
end

local cf = CreateFrame("Frame")
cf:RegisterEvent("PLAYER_REGEN_ENABLED")
cf:SetScript("OnEvent", function()
    for button, map in pairs(state) do
        for _, h in pairs(map) do
            if h.hidden and h.container then h.container:Show(); h.hidden = nil end
        end
    end
end)

function E.Remove(button, id)
    removeOne(button, id)
end

function E.Apply(button, id, spec)
    applyOne(button, id, spec)
end
