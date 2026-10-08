local _, ns = ...
local N = ns.N

-- Retail-only: pulses a Nucleus frame when a groupmate pings that unit.
--
-- MIRROR, NOT LISTENER. The events behind Blizzard's own ping icon (UNIT_PING_PIN_ADDED /
-- UNIT_PING_PIN_REMOVED) are protected: RegisterEvent on them from an addon is
-- ADDON_ACTION_FORBIDDEN, and the icon's template/mixin live in a forbidden scope, so we can
-- neither listen for the ping nor build Blizzard's icon ourselves.
--
-- What is reachable: Blizzard builds a ping-icon child frame (`.pingIconFrame`) into every compact
-- unit frame, and its ShowPing/ClearPing methods are ordinary functions: hooksecurefunc on them
-- fires with the ping's texture kit. Blizzard resolves the protected event to a unit internally;
-- we read the icon owner's `.unit` (a plain field) and mirror onto whichever Nucleus button shows
-- that unit.
--
-- Depends on two things:
--   * Blizzard's hidden compact frames must keep receiving events, so HideBlizzard.lua skips its
--     event stripping while Ping is on (hiding via alpha/mouse still applies). Turning Ping on
--     after events were stripped needs a /reload.
--   * The "showPingsOnRaidFrames" CVar must be on, otherwise Blizzard's handler returns before
--     ShowPing runs. EnsurePingCVar turns it on.

local Ping = {}
N.Ping = Ping

local SAFETY_EXPIRE = 20 -- seconds; covers a missed ClearPing if a frame is recycled

local activePings = {}   -- guid -> texture kit
local expireTokens = {}  -- guid -> generation, to invalidate a stale safety timer

--------------------------------------------------------------------------------
-- The real Blizzard ping icon on a Nucleus button
--------------------------------------------------------------------------------

-- Blizzard's own ping art, referenced by atlas name (built into the client). "kit" is the ping
-- type Blizzard hands back: Attack, Warning, OnMyWay, ...
local iconPool = {}

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

-- persist=true skips the auto-hide timer (used by the Ping Settings popup's
-- live preview, which controls the icon's visibility itself).
local function pulse(button, kit, persist)
    local icon = iconFor(button)
    local p = N.db.ping
    local base = math.max(14, math.min(button:GetWidth(), button:GetHeight()) * 0.7)
    local size = base * (p.scale or 1.0)
    icon:SetSize(size, size)
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", button, "CENTER", p.x or 0, p.y or 0)

    local okBg = pcall(icon.bg.SetAtlas, icon.bg, "Ping_Frame_BG_" .. kit, true)
    local okGlyph = pcall(icon.glyph.SetAtlas, icon.glyph, "Ping_Frame_" .. kit, true)
    if not (okBg or okGlyph) then
        -- Unknown kit name (Blizzard adds ping types now and then): fall back to a plain accent
        -- dot instead of nothing.
        icon.bg:SetTexture(nil)
        icon.glyph:SetTexture(N.Media.flat)
        local c = N.Media.color.accentBright
        icon.glyph:SetColorTexture(c[1], c[2], c[3], 1)
    end

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
        if not match and child.unit and UnitIsUnit(child.unit, unit) then match = child end
    end)
    return match
end

-- Live preview for the Ping Settings popup: a persistent icon on the player's own frame so
-- size/position can be tuned without pinging anyone.

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

--------------------------------------------------------------------------------
-- GUID plumbing
--------------------------------------------------------------------------------

local function safeGUID(unit)
    if not unit then return nil end
    local guid = UnitGUID(unit)
    if guid == nil or N.IsSecret(guid) then return nil end
    return guid
end

--------------------------------------------------------------------------------
-- Hooking Blizzard's own (hidden) ping icons
--------------------------------------------------------------------------------

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

-- Every compact frame Blizzard may already have built. Cheap and guarded per
-- icon, safe to re-run on every roster change.
local function sweepBlizzardFrames()
    for i = 1, 5 do hookOwner(_G["CompactPartyFrameMember" .. i]) end
    for i = 1, 40 do hookOwner(_G["CompactRaidFrame" .. i]) end
    for g = 1, 8 do
        for m = 1, 5 do hookOwner(_G["CompactRaidGroup" .. g .. "Member" .. m]) end
    end
    -- Self/target/focus pings don't go through the compact-frame system (a solo player has no
    -- CompactPartyFrameMember with a unit); they land on Blizzard's classic PlayerFrame /
    -- TargetFrame / FocusFrame, which carry their own .pingIconFrame.
    hookOwner(_G.PlayerFrame)
    hookOwner(_G.TargetFrame)
    hookOwner(_G.FocusFrame)
end

local setupHooked = false
local function installSetupHooks()
    if setupHooked then return end
    setupHooked = true
    -- Blizzard runs these on every compact frame it configures, catching new
    -- raid frames as they're created without waiting for the next sweep.
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

-- The hooks are cheap and harmless to leave installed regardless of the toggle (onBlizzardShowPing
-- checks N.db.ping.enabled first), so enabling the setting later needs no lazy init.
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
