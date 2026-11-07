local _, ns = ...
local N = ns.N
local M = N.Media

-- Frame-wide glow used by the custom indicator "Glow" and its preview.
local WHITE = "Interface/Buttons/WHITE8X8"

-- Frame-wide glows (pulse, halo, pixel) from game animations: E.NewGlow(parent, anchor) -> g.
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

function N.NewGlow(parent, anchor)
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

    -- One side of a marching ring: "top" moves right, "right" down, "bottom" left, "left" up.
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
        -- Clockwise: top moves right, right down, bottom left, left up; `reverse` flips it.
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
