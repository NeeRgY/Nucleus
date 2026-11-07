local _, ns = ...
local N = ns.N

-- Pulses a frame on a groupmate's ping. The ping events are protected, so the ping icon (.pingIconFrame) is mirrored via hooks.

local Ping = {}
N.Ping = Ping

local SAFETY_EXPIRE = 20 -- seconds; covers a missed ClearPing if a frame is recycled

local activePings = {}   -- guid -> texture kit
local expireTokens = {}  -- guid -> generation, to invalidate a stale safety timer


-- Ping art by atlas name; "kit" is the ping type Blizzard hands back (Attack, Warning, OnMyWay, ...).
local iconPool = {}

-- Forever has no Ping_Frame_* atlases: own icons (Media/Ping/*.tga), atlas kits still win.
local GetAtlasInfo = C_Texture and C_Texture.GetAtlasInfo
local PING_ICON_FOLDER = "Interface\\AddOns\\Nucleus\\Media\\Ping\\"
local KIT_IMAGE = {
    nonthreat = "Default", default = "Default", standard = "Default",
    attack = "Attack", assist = "Assist", help = "Assist",
    warning = "Warning", danger = "Warning", alert = "Warning",
    onmyway = "OnMyWay", coming = "OnMyWay",
}

local function setKit(icon, kit)
    local bgAtlas, glyphAtlas = "Ping_Frame_BG_" .. kit, "Ping_Frame_" .. kit
    if GetAtlasInfo and GetAtlasInfo(bgAtlas) ~= nil then
        pcall(icon.bg.SetAtlas, icon.bg, bgAtlas, true)
    else
        icon.bg:SetTexture(nil)
    end
    if GetAtlasInfo and GetAtlasInfo(glyphAtlas) ~= nil then
        pcall(icon.glyph.SetAtlas, icon.glyph, glyphAtlas, true)
        icon.glyph:SetVertexColor(1, 1, 1, 1)
        return
    end
    local norm = tostring(kit):lower():gsub("[%s_%-]", "")
    -- An unknown kit (a resource or spell ping, say) falls back to the standard icon.
    icon.glyph:SetTexture(PING_ICON_FOLDER .. (KIT_IMAGE[norm] or "Default"))
    icon.glyph:SetVertexColor(1, 1, 1, 1)
end

local function iconFor(button)
    local icon = iconPool[button]
    if icon then return icon end
    icon = CreateFrame("Frame", nil, button.overlay)
    icon:SetFrameLevel(button.overlay:GetFrameLevel() + 6)
    icon:Hide()
    icon.bg = icon:CreateTexture(nil, "OVERLAY", nil, 6)
    icon.bg:SetAllPoints()
    icon.glyph = icon:CreateTexture(nil, "OVERLAY", nil, 7)
    icon.glyph:SetAllPoints()
    iconPool[button] = icon
    return icon
end

-- persist = true skips the auto-hide timer (the Ping Settings preview controls visibility itself).
local function pulse(button, kit, persist)
    local icon = iconFor(button)
    local p = N.db.ping
    local base = math.max(14, math.min(button:GetWidth(), button:GetHeight()) * 0.7)
    local size = base * (p.scale or 1.0)
    icon:SetSize(size, size)
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", button, "CENTER", p.x or 0, p.y or 0)

    setKit(icon, kit)

    icon:Show()
    if icon._timer then
        icon._timer:Cancel()
        icon._timer = nil
    end
    if not persist then
        icon._timer = C_Timer.NewTimer(N.db.ping.duration or 4, function() icon:Hide() end)
    end
end

local function clearPulse(button)
    local icon = iconPool[button]
    if icon then
        if icon._timer then icon._timer:Cancel() end
        icon:Hide()
    end
end

local function findButtonForUnit(unit)
    if not unit or not N.UnitFrame or not UnitExists(unit) then return nil end
    local match
    N.UnitFrame.ForEachButton(function(child)
        if match or not child.unit then return end
        local same = UnitIsUnit(child.unit, unit)
        if not N.IsSecret(same) and same then match = child end
    end)
    return match
end


local PREVIEW_KIT = "NonThreat"
local previewActive = false

function Ping.PreviewOn()
    previewActive = true
    local button = findButtonForUnit("player")
    if button then pulse(button, PREVIEW_KIT, true) end
end

function Ping.PreviewOff()
    previewActive = false
    local button = findButtonForUnit("player")
    if button then clearPulse(button) end
end

N:On("NUCLEUS_SETTING_CHANGED", function(_, _, path)
    if previewActive and path and path:find("^ping%.") then
        local button = findButtonForUnit("player")
        if button then pulse(button, PREVIEW_KIT, true) end
    end
end)


local function safeGUID(unit)
    if not unit then return nil end
    local guid = UnitGUID(unit)
    if guid == nil or N.IsSecret(guid) then return nil end
    return guid
end


local DEBUG = false

local function onBlizzardShowPing(icon, kit)
    if DEBUG then N:Print("|cff61aef7[ping]|r ShowPing fired, kit=" .. tostring(kit)) end
    if not (N.db and N.db.ping and N.db.ping.enabled) then return end
    if type(kit) ~= "string" then
        if DEBUG then N:Print("|cff61aef7[ping]|r  kit is not a string, stopping") end
        return
    end
    local owner = icon:GetParent()
    local unit = owner and owner.unit
    if DEBUG then N:Print("|cff61aef7[ping]|r  owner=" .. tostring(owner and owner:GetName()) .. " unit=" .. tostring(unit)) end
    local guid = safeGUID(unit)
    if not guid then
        if DEBUG then N:Print("|cff61aef7[ping]|r  no safe GUID for unit, stopping") end
        return
    end

    activePings[guid] = kit
    local token = (expireTokens[guid] or 0) + 1
    expireTokens[guid] = token
    C_Timer.After(SAFETY_EXPIRE, function()
        if expireTokens[guid] == token then activePings[guid] = nil end
    end)

    local button = findButtonForUnit(unit)
    if DEBUG then N:Print("|cff61aef7[ping]|r  guid=" .. guid .. " button found=" .. tostring(button ~= nil)) end
    if button then pulse(button, kit) end
end

local function onBlizzardClearPing(icon)
    local owner = icon:GetParent()
    local unit = owner and owner.unit
    local guid = unit and safeGUID(unit)
    if guid then activePings[guid] = nil end
    local button = unit and findButtonForUnit(unit)
    if button then clearPulse(button) end
end

local function hookIcon(icon)
    if not icon or icon.nucPingHooked then return end
    local ok, forbidden = pcall(icon.IsForbidden, icon)
    if not ok or forbidden then return end
    icon.nucPingHooked = true
    hooksecurefunc(icon, "ShowPing", onBlizzardShowPing)
    hooksecurefunc(icon, "ClearPing", onBlizzardClearPing)
end

local function hookOwner(frame)
    if frame and frame.pingIconFrame then hookIcon(frame.pingIconFrame) end
end

local function sweepBlizzardFrames()
    for i = 1, 5 do hookOwner(_G["CompactPartyFrameMember" .. i]) end
    for i = 1, 40 do hookOwner(_G["CompactRaidFrame" .. i]) end
    for g = 1, 8 do
        for m = 1, 5 do hookOwner(_G["CompactRaidGroup" .. g .. "Member" .. m]) end
    end
    -- Self / target / focus pings land on Blizzard's own frames, which carry a .pingIconFrame.
    hookOwner(_G.PlayerFrame)
    hookOwner(_G.TargetFrame)
    hookOwner(_G.FocusFrame)
end

local setupHooked = false
local function installSetupHooks()
    if setupHooked then return end
    setupHooked = true
    if type(_G.DefaultCompactUnitFrameSetup) == "function" then
        hooksecurefunc("DefaultCompactUnitFrameSetup", hookOwner)
    end
    if type(_G.DefaultCompactMiniFrameSetup) == "function" then
        hooksecurefunc("DefaultCompactMiniFrameSetup", hookOwner)
    end
end

local PING_CVAR = "showPingsOnRaidFrames"
local function ensurePingCVar()
    if GetCVarBool and not GetCVarBool(PING_CVAR) then
        SetCVar(PING_CVAR, "1")
    end
end

-- The hooks stay installed; onBlizzardShowPing checks N.db.ping.enabled first.
function Ping.Init()
    installSetupHooks()
    sweepBlizzardFrames()
    if N.db and N.db.ping and N.db.ping.enabled then ensurePingCVar() end

    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
    watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    watcher:SetScript("OnEvent", sweepBlizzardFrames)

    N:On("NUCLEUS_SETTING_CHANGED", function(_, _, path)
        if path == "ping.enabled" and N.db.ping.enabled then ensurePingCVar() end
    end)

    SLASH_NUCLEUSPING1 = "/nucping"
    SlashCmdList.NUCLEUSPING = function()
        N:Print(("enabled=%s cvar(%s)=%s"):format(tostring(N.db.ping and N.db.ping.enabled),
            PING_CVAR, tostring(GetCVarBool and GetCVarBool(PING_CVAR))))
        for _, name in ipairs({ "PlayerFrame", "TargetFrame", "FocusFrame", "CompactPartyFrameMember1" }) do
            local f = _G[name]
            local icon = f and f.pingIconFrame
            N:Print(("  %s: exists=%s unit=%s pingIconFrame=%s hooked=%s")
                :format(name, tostring(f ~= nil), tostring(f and f.unit),
                    tostring(icon ~= nil), tostring(icon and icon.nucPingHooked)))
        end
    end
end
