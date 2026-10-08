local _, ns = ...
local N = ns.N
local M = N.Media
local L = N.L
local UF = N.UnitFrame

-- Inline per-indicator preview: a small mock unit frame sits right above each
-- indicator's own settings card (BuildIndicator/BuildAuras in OptionsFrame.lua
-- call N.Preview.Create and add it as the first card). Renders through the
-- EXACT visual layer the real frames use (UF.CreateVisual / UF.LayoutBars /
-- UF.ApplyMock), so it's pixel-identical - just masked down to the one
-- indicator being edited (button._previewOnly, honoured by UnitFrame.render /
-- Indicators / Auras) unless General > Preview Settings > "Show all enabled
-- indicators" turns that mask off.
--
-- The mock frame is a FIXED size, not the real configured party/raid frame
-- size - every indicator's preview lines up the same regardless of what width
-- and height the player has actually set.

local P = {}
N.Preview = P

local FIXED_W, FIXED_H = 180, 90
local PAD = 12
local TITLE_H = 20

local instances = {}

-- Previews that step through several states so one frame demonstrates them
-- all (the same trick as Status Text below): the mock fields for each step.
local ROTATING = {
    status = {
        { connected = false },
        { afk = true },
        { feignDeath = true },
        { ghost = true },
        { dead = true },
        { drinking = true },
        { summonStatus = "pending" },
        { summonStatus = "accepted" },
        { summonStatus = "declined" },
    },
    aggroBorder = {
        { threat = 1 },
        { threat = 2 },
        { threat = 3 },
    },
    readyCheck = {
        { readyCheck = "ready" },
        { readyCheck = "waiting" },
        { readyCheck = "notready" },
    },
    -- One dispel type per step (so every icon and colour shows), then all four.
    dispels = (function()
        local function aura(icon, kind, dur)
            return { icon = icon, dispelName = kind, applications = 3, duration = dur, expirationTime = GetTime() + dur * 0.6 }
        end
        local magic, curse = aura(136207, "Magic", 18), aura(136182, "Curse", 12)
        local disease, poison = aura(136128, "Disease", 20), aura(132090, "Poison", 24)
        local bleed = aura(132155, "Bleed", 10)
        return {
            { dispels = { magic } },
            { dispels = { curse } },
            { dispels = { disease } },
            { dispels = { poison } },
            { dispels = { bleed } },
            { dispels = { magic, curse, poison } },
        }
    end)(),
    statusIcon = {
        { otherParty = true },
        { statusRez = true },
        { statusRezDebuff = true },
        { statusSoulstone = true },
        { summonStatus = "pending" },
        { summonStatus = "accepted" },
        { summonStatus = "declined" },
        { phased = true },
        { bgFlag = "horde" },
        { bgFlag = "alliance" },
        { bgOrb = "blue" },
        { bgOrb = "purple" },
    },
}

-- Preview Settings > "cycle health": dead, then 25/50/75/100%, repeating.
-- Shared across every preview instance - one ticker drives them all.
local HEALTH_CYCLE = { 0, 25, 50, 75, 100 }
local healthCycleIdx = 1
local healthTicker

local function freshMock(filter, stateKey)
    local now = GetTime()
    local m = {
        name = (UnitName and UnitName("player")) or L["Preview"], class = "PRIEST",
        hpMax = 100, hp = 100, ppMax = 100, pp = 45, ppType = 0,
        connected = true, dead = false, aggro = false,
        role = "HEALER", isLeader = true, isTarget = false,
        incHeal = 12, absorb = 18, healAbsorb = 0,
        raidMarker = 8, targetedBy = 2, combat = true, phased = false, summon = false,
        readyCheck = "ready",
        buffs = {
            { icon = 135953, applications = 3, duration = 30, expirationTime = now + 21 },
            { icon = 136041, applications = 3, duration = 60, expirationTime = now + 44 },
        },
        debuffs = {
            { icon = 136207, dispelName = "Magic",  applications = 3, duration = 18, expirationTime = now + 12 },
            { icon = 132090, dispelName = "Poison", applications = 2, duration = 24, expirationTime = now + 15 },
        },
        dispels = {
            { icon = 136182, dispelName = "Curse", applications = 3, duration = 12, expirationTime = now + 8 },
            { icon = 136207, dispelName = "Magic", applications = 3, duration = 18, expirationTime = now + 12 },
            { icon = 132090, dispelName = "Poison", applications = 3, duration = 24, expirationTime = now + 15 },
        },
        defensives = {
            { icon = 135841, applications = 3, duration = 10, expirationTime = now + 7 },
            { icon = 132362, applications = 3, duration = 8,  expirationTime = now + 5 },
        },
        externals = {
            { icon = 135936, applications = 3, duration = 8,  expirationTime = now + 6, sourceUnit = "player" },
            { icon = 135939, applications = 3, duration = 20, expirationTime = now + 14 },
        },
        offensives = {
            { icon = 136048, applications = 3, duration = 20, expirationTime = now + 15 },
            { icon = 132316, applications = 3, duration = 12, expirationTime = now + 9 },
        },
        crowd = {
            { icon = 136071, dispelName = "Magic", applications = 3, duration = 8, expirationTime = now + 6 },
            { icon = 132298, applications = 3, duration = 4, expirationTime = now + 3 },
        },
    }
    local ps = N.db and N.db.previewSettings
    -- Static health % (default 100) whenever the cycle isn't running - applied
    -- before the demo overrides below, so e.g. Status's "show Dead" example
    -- still works at whatever % is configured.
    if ps and not ps.cycleHealth then m.hp = ps.healthPercent or 100 end

    local rot = ROTATING[filter]
    if rot then
        for k, v in pairs(rot[tonumber(stateKey) or 1] or rot[1]) do m[k] = v end
    end
    if filter == "dispels" then
        local fresh = {}
        for i, a in ipairs(m.dispels) do
            fresh[i] = { icon = a.icon, dispelName = a.dispelName, applications = a.applications,
                         duration = a.duration, expirationTime = now + a.duration * 0.6 }
        end
        m.dispels = fresh
    end

    -- Cycle Health overrides everything above - it's meant to sweep every
    -- indicator through the same health changes at once.
    if ps and ps.cycleHealth then
        local hp = HEALTH_CYCLE[healthCycleIdx] or 100
        m.hp = hp
        m.dead = (hp == 0)
    end
    return m
end

-- Builds a small fixed-size preview card, masked to `subId` (unless "show all
-- enabled" is on), and returns the host frame (already sized) so the caller
-- can just p:AddCard(host) it above the settings for that indicator.
function P.Create(parent, subId, customId)
    local host = CreateFrame("Frame", nil, parent)
    host:SetSize(FIXED_W + PAD * 4, TITLE_H + FIXED_H + PAD * 2)
    N.SkinPanel(host, M.color.frameBg)

    local titleFS = N.FontString(host, 12)
    titleFS:SetPoint("TOPLEFT", 8, -6)
    titleFS:SetText(L["Preview"])
    titleFS:SetTextColor(M.color.textDim[1], M.color.textDim[2], M.color.textDim[3])

    -- Settings button: a rounded button with our own cog icon, matching the
    -- options window. The cog is dim until hovered.
    local gear = CreateFrame("Button", nil, host)
    gear:SetSize(24, 24)
    gear:SetPoint("TOPRIGHT", -6, -4)
    N.SkinButton(gear)
    local gearTex = gear:CreateTexture(nil, "OVERLAY")
    gearTex:SetSize(14, 14)
    gearTex:SetPoint("CENTER")
    gearTex:SetTexture(M.tex.gear)
    gearTex:SetVertexColor(M.color.textDim[1], M.color.textDim[2], M.color.textDim[3], 1)
    gear:HookScript("OnEnter", function() gearTex:SetVertexColor(1, 1, 1, 1) end)
    gear:HookScript("OnLeave", function()
        gearTex:SetVertexColor(M.color.textDim[1], M.color.textDim[2], M.color.textDim[3], 1)
    end)
    gear:SetScript("OnClick", function()
        if N.ShowPreviewSettingsPopup then N.ShowPreviewSettingsPopup() end
    end)

    local button = CreateFrame("Button", nil, host)
    button:SetSize(FIXED_W, FIXED_H)
    button:SetPoint("TOP", 0, -(TITLE_H + PAD / 2))
    UF.CreateVisual(button, N:Mode())

    -- Private auras are drawn by Blizzard (not in a mock), so the preview shows
    -- placeholder slots laid out exactly as the real ones, each with the red
    -- border Blizzard draws around them.
    local privSlots = {}
    for s = 1, 5 do
        local f = CreateFrame("Frame", nil, button.overlay)
        f:SetFrameLevel(button.overlay:GetFrameLevel() + 6)
        f:Hide()
        f.tex = f:CreateTexture(nil, "ARTWORK")
        f.tex:SetAllPoints()
        f.tex:SetTexture(136096)
        f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.edges = {}
        for e = 1, 4 do
            local t = f:CreateTexture(nil, "OVERLAY")
            t:SetColorTexture(0.9, 0.1, 0.1, 1)
            f.edges[e] = t
        end
        privSlots[s] = f
    end

    local rotateIdx = 1
    local inst = { host = host, button = button, subId = subId }
    function inst.refresh()
        if not host:IsShown() then return end
        local key = N:Mode()
        local ps = N.db.previewSettings or {}
        button.groupKey = key
        button._previewOnly = (not ps.showAllEnabled) and subId or nil
        button._previewCustom = (not ps.showAllEnabled) and customId or nil
        UF.LayoutBars(button)

        local stateKey
        if ROTATING[subId] then stateKey = rotateIdx end
        UF.ApplyMock(button, freshMock(subId, stateKey))

        local pa = N.db[key].indicators.privateAura
        local showPriv = (subId == "privateAura" or ps.showAllEnabled) and (pa.enabled or subId == "privateAura")
        local num = 1 -- the preview shows a single sample slot
        local size = pa.size or 18
        local point = (pa.position or "top"):upper()
        local ax = point:find("LEFT") and 1 or point:find("RIGHT") and -1 or 0
        local ay = point:find("BOTTOM") and 1 or point:find("TOP") and -1 or 0
        for s = 1, 5 do
            local f = privSlots[s]
            if showPriv and s <= num then
                local off = (s - 1) * (size + (pa.spacing or 1))
                local dx, dy = 0, 0
                if pa.growth == "LEFT" then dx = -off
                elseif pa.growth == "UP" then dy = off
                elseif pa.growth == "DOWN" then dy = -off
                else dx = off end
                f:SetSize(size, size)
                f:ClearAllPoints()
                f:SetPoint(point, button, point, ax + dx + (pa.x or 0), ay + dy + (pa.y or 0))
                -- the red border, sized like Blizzard's (scales with the icon)
                local bw = math.max(1, math.floor(size / 16 * (pa.borderScale or 1) + 0.5))
                local e = f.edges
                e[1]:ClearAllPoints(); e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(bw)
                e[2]:ClearAllPoints(); e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(bw)
                e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(bw)
                e[4]:ClearAllPoints(); e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(bw)
                f:Show()
            else
                f:Hide()
            end
        end
    end
    instances[#instances + 1] = inst
    host:SetScript("OnShow", inst.refresh)
    inst.refresh()

    -- Cycle through every possible Status Text state so the one preview
    -- frame demonstrates all of them over time, not just the first.
    if ROTATING[subId] then
        local ticker
        host:SetScript("OnShow", function()
            inst.refresh()
            if not ticker then
                ticker = C_Timer.NewTicker(1.5, function()
                    if not host:IsShown() then return end
                    rotateIdx = (rotateIdx % #ROTATING[subId]) + 1
                    inst.refresh()
                end)
            end
        end)
        host:SetScript("OnHide", function()
            if ticker then ticker:Cancel(); ticker = nil end
        end)
    end

    return host
end

-- The Actions preview frames that are on screen (for the Test button).
function P.EachActionsPreview(fn)
    for _, inst in ipairs(instances) do
        if inst.subId == "actions" and inst.host:IsVisible() then fn(inst.button) end
    end
end

local function refreshAll()
    for _, inst in ipairs(instances) do inst.refresh() end
end
P.RefreshAll = refreshAll

-- One shared ticker for the health-cycle setting, started/stopped as it's
-- toggled - drives every open preview instance at once via refreshAll.
local function syncHealthTicker()
    local want = N.db and N.db.previewSettings and N.db.previewSettings.cycleHealth
    if want and not healthTicker then
        healthTicker = C_Timer.NewTicker(2, function()
            healthCycleIdx = (healthCycleIdx % #HEALTH_CYCLE) + 1
            refreshAll()
        end)
    elseif not want and healthTicker then
        healthTicker:Cancel()
        healthTicker = nil
    end
end

N:On("NUCLEUS_SETTING_CHANGED", function(_, _, path)
    if path == "previewSettings.cycleHealth" then syncHealthTicker() end
    refreshAll()
end)
N:On("NUCLEUS_EDIT_MODE", refreshAll)
N:On("NUCLEUS_DB_READY", syncHealthTicker)
