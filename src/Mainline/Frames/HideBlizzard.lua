local _, ns = ...
local N = ns.N

-- Suppress Blizzard's party / raid frames. More thorough than a plain :Hide():
--   * alpha 0 + mouse off on the containers (no taint, survives Blizzard re-show)
--   * secure post-hooks that re-apply whenever Blizzard shows them again
--   * event stripping on the hidden CompactUnitFrames so they stop costing CPU
-- Party and raid are independent (db.party.hideBlizzard / db.raid.hideBlizzard).

local HB = {}
N.HideBlizzard = HB

local hooked = false

local function try(fn) pcall(fn) end

local function conceal(frame, hide)
    if not frame then return end
    try(function()
        frame:SetAlpha(hide and 0 or 1)
        if frame.EnableMouse then frame:EnableMouse(not hide) end
    end)
end

local function stripEvents(frame)
    if frame and frame.UnregisterAllEvents then
        try(function() frame:UnregisterAllEvents() end)
    end
end

local function wantRaid() return N.db and N.db.raid.hideBlizzard end
local function wantParty() return N.db and N.db.party.hideBlizzard end

-- Ping display (Integrations/Ping.lua) hooks the ping icon Blizzard already
-- builds into its own (hidden) compact frames, which only keeps working while
-- those frames keep receiving events. Stripping events is a CPU optimization,
-- not a correctness requirement, so it's the one that gives way. Toggling
-- Ping back on after events were already stripped needs a /reload - there is
-- no clean way to restore only the events Blizzard originally registered.
local function pingWantsEvents() return N.db and N.db.ping and N.db.ping.enabled end

local function apply()
    local hr, hp = wantRaid(), wantParty()

    conceal(_G.CompactRaidFrameManager, hr or hp) -- the left-edge toggle tab
    conceal(_G.CompactRaidFrameContainer, hr)
    conceal(_G.CompactPartyFrame, hp)
    conceal(_G.PartyFrame, hp)

    local keepEvents = pingWantsEvents()
    for i = 1, 4 do
        local f = _G["PartyMemberFrame" .. i]
        conceal(f, hp)
        if hp and not keepEvents then stripEvents(f) end
    end
    for i = 1, 5 do
        if hp and not keepEvents then stripEvents(_G["CompactPartyFrameMember" .. i]) end
    end
    for i = 1, 40 do
        if hr and not keepEvents then stripEvents(_G["CompactRaidFrame" .. i]) end
    end
    for g = 1, 8 do
        for m = 1, 5 do
            if hr and not keepEvents then stripEvents(_G["CompactRaidGroup" .. g .. "Member" .. m]) end
        end
    end
end
HB.Apply = apply

local function deferApply()
    C_Timer.After(0, apply)
end

local function installHooks()
    if hooked then return end
    hooked = true

    for _, name in ipairs({ "CompactRaidFrameManager", "CompactRaidFrameContainer", "CompactPartyFrame" }) do
        local f = _G[name]
        if f and f.Show then hooksecurefunc(f, "Show", deferApply) end
    end
    if _G.CompactRaidFrameManager_UpdateShown then
        hooksecurefunc("CompactRaidFrameManager_UpdateShown", deferApply)
    end
    -- New CompactUnitFrames register their events here; strip them on creation.
    if _G.CompactUnitFrame_UpdateUnitEvents then
        hooksecurefunc("CompactUnitFrame_UpdateUnitEvents", function(frame)
            try(function()
                local unit = frame and frame.unit
                if type(unit) ~= "string" then return end
                local isRaid = unit:find("^raid") ~= nil
                local isParty = (unit:find("^party") ~= nil) or unit == "player"
                if not pingWantsEvents() and ((isRaid and wantRaid()) or (isParty and wantParty())) then
                    stripEvents(frame)
                end
            end)
        end)
    end
end

function HB.Init()
    installHooks()
    apply()

    local watcher = CreateFrame("Frame")
    for _, e in ipairs({
        "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
        "RAID_ROSTER_UPDATE", "PARTY_MEMBER_ENABLE", "PARTY_MEMBER_DISABLE",
    }) do
        watcher:RegisterEvent(e)
    end
    watcher:SetScript("OnEvent", apply)

    N:On("NUCLEUS_SETTING_CHANGED", function(_, _, path)
        if path == "party.hideBlizzard" or path == "raid.hideBlizzard" or path == "ping.enabled" then
            apply()
        end
    end)
end
