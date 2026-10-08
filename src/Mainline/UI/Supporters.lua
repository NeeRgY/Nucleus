local _, ns = ...
local N = ns.N
local M = N.Media
local L = N.L

local function uc(c) return c[1], c[2], c[3], c[4] or 1 end

-- Supporters: a pane that slides out to the right of the options window (About tab)
-- and lists the people who support Nucleus, grouped by tier. The names live in
-- N.About.supporters (Core/About.lua); with none listed the pane says so.

local S = {}
N.Supporters = S

local PANEL_W, PAD, SLIDE, SLIDE_TIME = 240, 16, 26, 0.22

local pane
local anim = { t = SLIDE_TIME + 1, dir = 0 } -- dir: 1 opening, -1 closing

local function windowFrame() return _G.NucleusOptionsFrame end

-- A tier: a coloured heading and the names under it.
local function addTier(child, y, tier)
    local c = tier.color or M.color.accent
    local head = N.FontString(child, 12)
    head:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
    head:SetTextColor(c[1], c[2], c[3])
    head:SetText(tier.name)
    y = y + 20
    local line = child:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(c[1], c[2], c[3], 0.35)
    line:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -y)
    line:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, -y)
    line:SetHeight(1)
    y = y + 8
    for _, name in ipairs(tier.names) do
        local fs = N.FontString(child, 12)
        fs:SetPoint("TOPLEFT", child, "TOPLEFT", 6, -y)
        fs:SetWidth(PANEL_W - 2 * PAD - 12)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        fs:SetTextColor(uc(M.color.text))
        fs:SetText(name)
        y = y + 18
    end
    return y + 12
end

local function fill()
    local child = pane.child
    for _, r in ipairs({ child:GetRegions() }) do r:Hide() end
    for _, f in ipairs({ child:GetChildren() }) do f:Hide() end
    local y = 0
    local any = false
    for _, tier in ipairs((N.About and N.About.supporters) or {}) do
        if tier.names and #tier.names > 0 then
            y = addTier(child, y, tier)
            any = true
        end
    end
    if not any then
        local fs = N.FontString(child, 12)
        fs:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
        fs:SetWidth(PANEL_W - 2 * PAD)
        fs:SetJustifyH("LEFT")
        fs:SetTextColor(uc(M.color.textDim))
        fs:SetText(L["SUPPORTERS_EMPTY"])
        y = fs:GetStringHeight() + 8
    end
    child:SetHeight(math.max(y, 10))
end

local function place(progress)
    -- Eases out: quick at the start, soft at the end.
    local e = 1 - (1 - progress) * (1 - progress)
    pane:SetAlpha(e)
    pane:ClearAllPoints()
    pane:SetPoint("TOPLEFT", windowFrame(), "TOPRIGHT", 6 - SLIDE * (1 - e), 0)
    pane:SetPoint("BOTTOMLEFT", windowFrame(), "BOTTOMRIGHT", 6 - SLIDE * (1 - e), 0)
end

local function build()
    local win = windowFrame()
    pane = CreateFrame("Frame", "NucleusSupportersPane", win)
    pane:SetWidth(PANEL_W)
    pane:SetFrameStrata(win:GetFrameStrata())
    pane:SetFrameLevel(win:GetFrameLevel() + 2)
    pane:EnableMouse(true)
    pane._nucUI = true
    pane:Hide()
    N.SkinRound(pane, M.color.windowBg, M.color.line)
    N.AddShadow(pane, 14, 0.7, -5)

    local bar = pane:CreateTexture(nil, "ARTWORK")
    bar:SetSize(3, 14)
    bar:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -PAD)
    bar:SetColorTexture(uc(M.color.accent))
    N.OnRecolor(function() bar:SetColorTexture(uc(M.color.accent)) end)

    local title = N.FontString(pane, 14)
    title:SetPoint("LEFT", bar, "RIGHT", 8, 0)
    title:SetTextColor(uc(M.color.text))
    title:SetText(L["Supporters"])

    local intro = N.FontString(pane, 11)
    intro:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -(PAD + 26))
    intro:SetWidth(PANEL_W - 2 * PAD)
    intro:SetJustifyH("LEFT")
    intro:SetTextColor(uc(M.color.textDim))
    intro:SetText(L["SUPPORTERS_INTRO"])
    pane.intro = intro

    local scroll, child = N.MakeScroll(pane, -3)
    scroll:SetPoint("TOPLEFT", pane, "TOPLEFT", PAD, -(PAD + 26 + 52))
    scroll:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -(PAD + 6), PAD + 36)
    child:SetWidth(PANEL_W - 2 * PAD - 6)
    pane.child = child

    -- Support link at the foot of the pane.
    local url = N.About and N.About.supportUrl
    if url then
        local btn = CreateFrame("Button", nil, pane)
        btn:SetSize(PANEL_W - 2 * PAD, 26)
        btn:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", PAD, PAD)
        N.SkinButton(btn)
        N.SetPanelBorder(btn, M.color.accent)
        local fs = N.FontString(btn, 12)
        fs:SetPoint("CENTER")
        fs:SetText(L["Support Nucleus"])
        btn:SetScript("OnClick", function() N.ShowLinkPopup(L["Support Nucleus"], url) end)
    end

    pane:SetScript("OnUpdate", function(self, dt)
        if anim.dir == 0 then return end
        anim.t = anim.t + dt
        local p = math.min(1, anim.t / SLIDE_TIME)
        if anim.dir == 1 then
            place(p)
        else
            place(1 - p)
            if p >= 1 then self:Hide() end
        end
        if p >= 1 then anim.dir = 0 end
    end)
    fill()
end

function S.IsShown() return pane and pane:IsShown() and anim.dir ~= -1 end

function S.Show()
    if not windowFrame() then return end
    if not pane then build() end
    anim.t, anim.dir = 0, 1
    place(0)
    pane:Show()
end

function S.Hide()
    if not (pane and pane:IsShown()) then return end
    anim.t, anim.dir = 0, -1
end

function S.Toggle()
    if S.IsShown() then S.Hide() else S.Show() end
end

-- The button in the About page: a soft accent glow behind the label that breathes
-- while the pane is closed, and a small arrow that turns when it is open.
function S.MakeButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b._rowHeight = 36
    N.SkinButton(b)

    local glow = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    glow:SetAllPoints()
    glow:SetColorTexture(uc(M.color.accent))
    glow:SetAlpha(0.10)
    local ag = glow:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(0.06)
    a:SetToAlpha(0.20)
    a:SetDuration(1.4)
    a:SetSmoothing("IN_OUT")
    ag:Play()
    N.OnRecolor(function() glow:SetColorTexture(uc(M.color.accent)) end)

    local fs = N.FontString(b, 13)
    fs:SetPoint("CENTER", -8, 0)
    fs:SetTextColor(uc(M.color.accentBright))
    fs:SetText(L["Supporters"])

    local arrow = N.FontString(b, 13)
    arrow:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    arrow:SetTextColor(uc(M.color.accentBright))
    local function paint() arrow:SetText(S.IsShown() and "<" or ">") end
    paint()

    b:SetScript("OnClick", function() S.Toggle(); paint() end)
    b:HookScript("OnShow", paint)
    return b
end
