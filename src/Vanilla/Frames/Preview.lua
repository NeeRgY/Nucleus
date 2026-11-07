local _, ns = ...
local N = ns.N
local M = N.Media
local L = N.L
local UF = N.UnitFrame


local P = {}
N.Preview = P

local MIN_W = 150
local PAD = 12
local TITLE_H = 20

local instances = {}

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
    threatIcon = {
        { threat = 1 },
        { threat = 2 },
        { threat = 3 },
    },
    readyCheck = {
        { readyCheck = "ready" },
        { readyCheck = "waiting" },
        { readyCheck = "notready" },
    },
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

-- Preview "cycle health": dead, then 25/50/75/100%, repeating; one ticker drives all previews.
local HEALTH_CYCLE = { 0, 25, 50, 75, 100 }
local healthCycleIdx = 1
local healthTicker

local function freshMock(filter, stateKey)
    local now = GetTime()
    local m = {
        name = (UnitName and (UnitName("player"))) or L["Preview"],
        class = (select(2, UnitClass("player"))) or "PRIEST",
        hpMax = 100, hp = 100, ppMax = 100, pp = 45, ppType = 0,
        connected = true, dead = false, aggro = false,
        role = "HEALER", isLeader = true, raidRole = "CYCLE", isTarget = false,
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
        defext = {
            { icon = 135841, applications = 3, duration = 10, expirationTime = now + 7 },
            { icon = 135936, applications = 3, duration = 8,  expirationTime = now + 6, sourceUnit = "player" },
            { icon = 132362, applications = 3, duration = 8,  expirationTime = now + 5 },
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

    if ps and ps.cycleHealth then
        local hp = HEALTH_CYCLE[healthCycleIdx] or 100
        m.hp = hp
        m.dead = (hp == 0)
    end
    return m
end

local function frameSize()
    local cfg = N.db and N.db[N:Mode()]
    return (cfg and cfg.width) or 120, (cfg and cfg.height) or 50
end

function P.Create(parent, subId, customId)
    local fw, fh = frameSize()
    local host = CreateFrame("Frame", nil, parent)
    host:SetSize(math.max(fw, MIN_W) + PAD * 4, TITLE_H + fh + PAD * 2)
    N.SkinPanel(host, M.color.frameBg)
    host._nucFrameText = true -- the mock frames inside show the frame font, not the window font

    local titleFS = N.FontString(host, 12)
    titleFS:SetPoint("TOPLEFT", 8, -6)
    titleFS._nucForceUI = true
    titleFS:SetText(L["Preview"])
    titleFS:SetTextColor(M.color.textDim[1], M.color.textDim[2], M.color.textDim[3])

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
    button:SetSize(fw, fh)
    button:SetPoint("TOP", 0, -(TITLE_H + PAD / 2))
    UF.CreateVisual(button, N:Mode())

    local rotateIdx = 1
    local inst = { host = host, button = button, subId = subId }
    function inst.refresh()
        if not host:IsShown() then return end
        local key = N:Mode()
        local ps = N.db.previewSettings or {}
        button.groupKey = key
        local w, h = frameSize()
        if button:GetWidth() ~= w or button:GetHeight() ~= h then
            button:SetSize(w, h)
            host:SetHeight(TITLE_H + h + PAD * 2)
        end
        button._previewOnly = (not ps.showAllEnabled) and subId or nil
        button._previewCustom = (not ps.showAllEnabled) and customId or nil
        UF.LayoutBars(button)

        local stateKey
        if ROTATING[subId] then stateKey = rotateIdx end
        UF.ApplyMock(button, freshMock(subId, stateKey))

    end
    instances[#instances + 1] = inst
    host:SetScript("OnShow", inst.refresh)
    inst.refresh()

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

function P.EachActionsPreview(fn)
    for _, inst in ipairs(instances) do
        if inst.subId == "actions" and inst.host:IsVisible() then fn(inst.button) end
    end
end

local function refreshAll()
    for _, inst in ipairs(instances) do inst.refresh() end
end
P.RefreshAll = refreshAll

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
