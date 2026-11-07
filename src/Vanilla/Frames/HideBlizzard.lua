local _, ns = ...
local N = ns.N

-- Hides Blizzard's party / raid frames without taint: alpha 0, mouse off, post-hooks, stripped events.

local HB = {}
N.HideBlizzard = HB

local hooked = false

local function try(fn) pcall(fn) end

local function conceal(frame, hide)
    if not frame then return end
    try(function() frame:SetAlpha(hide and 0 or 1) end)
    if not frame.EnableMouse then return end
    -- EnableMouse on a protected frame (the raid container) is blocked in combat: wait.
    if InCombatLockdown() and frame:IsProtected() then
        N.RunWhenSafe(function() try(function() frame:EnableMouse(not hide) end) end, "hb-mouse-" .. tostring(frame))
    else
        try(function() frame:EnableMouse(not hide) end)
    end
end

-- Edit Mode draws a preview whatever the alpha: scale the containers down (out of combat), never the members.
local origScale = setmetatable({}, { __mode = "k" })
local function shrink(frame, hide)
    if not frame then return end
    if InCombatLockdown() then
        N.RunWhenSafe(function() shrink(frame, hide) end, "hb-scale-" .. tostring(frame))
        return
    end
    if hide then
        if not origScale[frame] then
            local ok, sc = pcall(frame.GetScale, frame)
            if ok and type(sc) == "number" and sc > 0.01 then origScale[frame] = sc end
        end
        if origScale[frame] then try(function() frame:SetScale(0.001) end) end
    elseif origScale[frame] then
        local sc = origScale[frame]
        origScale[frame] = nil
        try(function() frame:SetScale(sc) end)
    end
end

-- Alpha only, for frames moved out of their container; Blizzard resets member alpha, so it is restored in a timer.
local alphaHidden = setmetatable({}, { __mode = "k" })
local alphaHooked = setmetatable({}, { __mode = "k" })
local alphaQueue, alphaQueued = {}, false
local function flushAlpha()
    alphaQueued = false
    for frame in pairs(alphaQueue) do
        alphaQueue[frame] = nil
        if alphaHidden[frame] then try(function() frame:SetAlpha(0) end) end
    end
end
local function fade(frame, hide)
    if not frame then return end
    if hide then
        alphaHidden[frame] = true
        try(function() frame:SetAlpha(0) end)
        if not alphaHooked[frame] and frame.SetAlpha then
            alphaHooked[frame] = true
            hooksecurefunc(frame, "SetAlpha", function(self, a)
                -- a secret alpha can't be compared: it counts as "raised"
                if alphaHidden[self] and (N.IsSecret(a) or (type(a) == "number" and a > 0)) then
                    alphaQueue[self] = true
                    if not alphaQueued then
                        alphaQueued = true
                        C_Timer.After(0, flushAlpha)
                    end
                end
            end)
        end
    elseif alphaHidden[frame] then
        alphaHidden[frame] = nil
        try(function() frame:SetAlpha(1) end)
    end
end

-- Compact frames draw a selection / threat outline: keep it at alpha 0 (pcall: protected).
local function muteHighlights(frame)
    if not frame then return end
    for _, r in ipairs({ frame.selectionHighlight, frame.aggroHighlight }) do
        if r and r.SetAlpha then try(function() r:SetAlpha(0) end) end
    end
end

local function stripEvents(frame)
    if frame and frame.UnregisterAllEvents then
        try(function() frame:UnregisterAllEvents() end)
    end
end

local function wantRaid() return N.db and N.db.raid.hideBlizzard end
local function wantParty() return N.db and N.db.party.hideBlizzard end

-- Frames that ignore the hidden container's alpha are hidden one by one; `muted` keeps their alpha.
local muted = setmetatable({}, { __mode = "k" })
-- Whether a frame is really on screen; a secret answer counts as "not" and the frame is left alone.
local function onScreen(f)
    local okV, vis = pcall(f.IsVisible, f)
    if not okV or N.IsSecret(vis) or not vis then return false end
    local okA, eff = pcall(f.GetEffectiveAlpha, f)
    if not okA or N.IsSecret(eff) or type(eff) ~= "number" then return false end
    return eff > 0.01, eff
end
local function nameOf(f)
    local ok, n = pcall(f.GetName, f)
    return (ok and n) or "(unnamed)"
end
local function sweep(frame, hide, depth, path)
    if not frame or depth > 6 then return end
    local ok, kids = pcall(function() return { frame:GetChildren() } end)
    if not ok then return end
    for _, k in ipairs(kids) do
        local here = path .. "." .. nameOf(k)
        if hide then
            if not muted[k] and onScreen(k) then
                local okA, a = pcall(k.GetAlpha, k)
                if not okA or N.IsSecret(a) or type(a) ~= "number" then a = 1 end
                muted[k] = { alpha = a, path = here }
                try(function() k:SetAlpha(0) end)
            end
        elseif muted[k] then
            local a = muted[k].alpha
            muted[k] = nil
            try(function() k:SetAlpha(a) end)
        end
        sweep(k, hide, depth + 1, here)
    end
end

local function apply()
    local hr, hp = wantRaid(), wantParty()

    conceal(_G.CompactRaidFrameManager, hr or hp)
    conceal(_G.CompactRaidFrameContainer, hr)
    conceal(_G.CompactPartyFrame, hp)
    conceal(_G.PartyFrame, hp)

    for i = 1, 4 do
        local f = _G["PartyMemberFrame" .. i]
        conceal(f, hp)
        if hp then stripEvents(f) end
    end
    for i = 1, 5 do
        if hp then stripEvents(_G["CompactPartyFrameMember" .. i]) end
        if hp then muteHighlights(_G["CompactPartyFrameMember" .. i]) end
    end
    for i = 1, 40 do
        if hr then stripEvents(_G["CompactRaidFrame" .. i]) end
        if hr then muteHighlights(_G["CompactRaidFrame" .. i]) end
    end
    for g = 1, 8 do
        for m = 1, 5 do
            if hr then stripEvents(_G["CompactRaidGroup" .. g .. "Member" .. m]) end
        end
    end
    for i = 1, 5 do
        fade(_G["CompactPartyFrameMember" .. i], hp)
        fade(_G["CompactPartyFramePet" .. i], hp)
    end
    for i = 1, 40 do fade(_G["CompactRaidFrame" .. i], hr) end
    for g = 1, 8 do
        local group = "CompactRaidGroup" .. g
        fade(_G[group], hr)
        fade(_G[group .. "BorderFrame"], hr)
        for m = 1, 5 do fade(_G[group .. "Member" .. m], hr) end
    end
    shrink(_G.CompactRaidFrameContainer, hr)
    shrink(_G.CompactPartyFrame, hp)
    shrink(_G.PartyFrame, hp)
    sweep(_G.CompactRaidFrameManager, hr or hp, 1, "CompactRaidFrameManager")
    sweep(_G.CompactRaidFrameContainer, hr, 1, "CompactRaidFrameContainer")
    sweep(_G.CompactPartyFrame, hp, 1, "CompactPartyFrame")
    sweep(_G.PartyFrame, hp, 1, "PartyFrame")
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
    -- Something (Edit Mode, another addon) raising a hidden container's alpha again: put it back.
    for _, name in ipairs({ "CompactRaidFrameManager", "CompactRaidFrameContainer", "CompactPartyFrame", "PartyFrame" }) do
        local f = _G[name]
        if f and f.SetAlpha then
            hooksecurefunc(f, "SetAlpha", function(self, a)
                if not N.IsSecret(a) and (type(a) ~= "number" or a <= 0) then return end
                local hide = (self == _G.CompactRaidFrameContainer and wantRaid())
                    or ((self == _G.CompactPartyFrame or self == _G.PartyFrame) and wantParty())
                    or (self == _G.CompactRaidFrameManager and (wantRaid() or wantParty()))
                if hide then deferApply() end
            end)
            hooksecurefunc(f, "SetScale", function(self, sc)
                if not N.IsSecret(sc) and (type(sc) ~= "number" or sc <= 0.01) then return end
                local hide = (self == _G.CompactRaidFrameContainer and wantRaid())
                    or ((self == _G.CompactPartyFrame or self == _G.PartyFrame) and wantParty())
                if hide then deferApply() end
            end)
        end
    end
    -- Edit Mode shows the raid / party preview frames: hide them again once it has built them.
    if _G.EventRegistry and EventRegistry.RegisterCallback then
        local owner = {}
        local function editModeChanged()
            deferApply()
            C_Timer.After(0.3, apply)
            C_Timer.After(1, apply)
        end
        EventRegistry:RegisterCallback("EditMode.Enter", editModeChanged, owner)
        EventRegistry:RegisterCallback("EditMode.Exit", editModeChanged, owner)
    end
    if _G.CompactRaidFrameManager_UpdateShown then
        hooksecurefunc("CompactRaidFrameManager_UpdateShown", deferApply)
    end
    for _, fn in ipairs({ "CompactUnitFrame_UpdateSelectionHighlight", "CompactUnitFrame_UpdateAggroHighlight" }) do
        if _G[fn] then
            hooksecurefunc(fn, function(frame)
                local unit = frame and frame.unit
                if type(unit) ~= "string" then return end
                local isRaid = unit:find("^raid") ~= nil
                local isParty = (unit:find("^party") ~= nil) or unit == "player"
                if (isRaid and wantRaid()) or (isParty and wantParty()) then muteHighlights(frame) end
            end)
        end
    end
    if _G.CompactUnitFrame_UpdateUnitEvents then
        hooksecurefunc("CompactUnitFrame_UpdateUnitEvents", function(frame)
            try(function()
                local unit = frame and frame.unit
                if type(unit) ~= "string" then return end
                local isRaid = unit:find("^raid") ~= nil
                local isParty = (unit:find("^party") ~= nil) or unit == "player"
                if (isRaid and wantRaid()) or (isParty and wantParty()) then
                    stripEvents(frame)
                end
            end)
        end)
    end
end

-- /nucblizz: what is still visible below the hidden Blizzard frames (for bug reports).
SLASH_NUCLEUSBLIZZ1 = "/nucblizz"
SlashCmdList.NUCLEUSBLIZZ = function()
    local function shown(v)
        local ok, r = pcall(tostring, v)
        return ok and r or "?"
    end
    local any = false
    local function walk(f, path, depth)
        if depth > 5 then return end
        local ok, kids = pcall(function() return { f:GetChildren() } end)
        if not ok then return end
        for _, k in ipairs(kids) do
            local p = path .. "." .. nameOf(k)
            local visible, eff = onScreen(k)
            if visible then
                N:Print(p, "| alpha", shown(k:GetAlpha()), "| effective", shown(eff),
                    "| size", shown(k:GetWidth()) .. "x" .. shown(k:GetHeight()),
                    "| ignores parent alpha", shown(k.IsIgnoringParentAlpha and k:IsIgnoringParentAlpha()))
                any = true
            end
            walk(k, p, depth + 1)
        end
    end
    for _, n in ipairs({ "CompactRaidFrameManager", "CompactRaidFrameContainer", "CompactPartyFrame", "PartyFrame" }) do
        local f = _G[n]
        if f then
            local parent = f:GetParent()
            N:Print(n, "| shown", shown(f:IsShown()), "| alpha", shown(f:GetAlpha()),
                "| scale", shown(f:GetScale()), "| parent", shown(parent and nameOf(parent)))
            walk(f, n, 1)
        end
    end
    local strays = { "CompactPartyFrameMember", "CompactPartyFramePet", "CompactRaidFrame", "CompactRaidGroup" }
    for _, base in ipairs(strays) do
        for i = 1, 40 do
            local f = _G[base .. i]
            if f then
                local visible, eff = onScreen(f)
                if visible then
                    local parent = f:GetParent()
                    N:Print(base .. i, "is still visible | effective alpha", shown(eff),
                        "| parent", shown(parent and nameOf(parent)),
                        "| size", shown(f:GetWidth()) .. "x" .. shown(f:GetHeight()))
                    any = true
                end
            end
        end
    end
    local count = 0
    for k, info in pairs(muted) do
        count = count + 1
        N:Print("muted by Nucleus:", info.path, "|", shown(k.GetObjectType and k:GetObjectType()),
            "| size", shown(k:GetWidth()) .. "x" .. shown(k:GetHeight()),
            "| regions", shown(k.GetNumRegions and k:GetNumRegions()))
    end
    if not any and count == 0 then N:Print("nothing is visible below the hidden frames") end
end

function HB.Init()
    installHooks()
    apply()

    local watcher = CreateFrame("Frame")
    for _, e in ipairs({
        "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED",
        "RAID_ROSTER_UPDATE", "PARTY_MEMBER_ENABLE", "PARTY_MEMBER_DISABLE",
    }) do
        N.SafeRegister(watcher, e)
    end
    watcher:SetScript("OnEvent", apply)

    N:On("NUCLEUS_SETTING_CHANGED", function(_, _, path)
        if path == "party.hideBlizzard" or path == "raid.hideBlizzard" then
            apply()
        end
    end)
end
