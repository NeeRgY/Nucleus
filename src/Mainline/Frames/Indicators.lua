local _, ns = ...
local N = ns.N
local M = N.Media
local L = N.L
local IsSecret = N.IsSecret

local Abbrev = _G.AbbreviateNumbers or function(v)
    if v >= 1e6 then return string.format("%.1fM", v / 1e6) end
    if v >= 1e3 then return string.format("%.0fK", v / 1e3) end
    return tostring(v)
end

-- Indicator framework. Each indicator is a small module with create/update hooks and a list of
-- events that trigger an update. New indicators register here without touching UnitFrame or
-- HeaderGroup.

local registry = {}
local byEvent = {}

local Indicators = {}
N.Indicators = Indicators

-- def = { create(button) -> obj, update(button, obj), events = { ... },
--         enabled(button) -> bool (optional) }
function Indicators.Register(name, def)
    def.name = name
    registry[#registry + 1] = def
    for _, ev in ipairs(def.events or {}) do
        byEvent[ev] = byEvent[ev] or {}
        byEvent[ev][#byEvent[ev] + 1] = def
    end
end

function Indicators.Build(button)
    button.indicators = {}
    for _, def in ipairs(registry) do
        button.indicators[def.name] = def.create(button)
    end
end

local function hideObj(o)
    if not o then return end
    if o.Hide then o:Hide() end
    if o.SetText then o:SetText("") end
end

local function styleIcon(obj, def, o)
    if not (obj and obj.SetSize and def.anchor) then return end
    local s = o.size or 12
    obj:SetSize(s, s)
    obj:ClearAllPoints()
    -- The player's chosen spot (one of the nine, lower-case) wins over the indicator's default
    -- anchor.
    local anchor = o.position and o.position:upper() or def.anchor
    local dx, dy = 0, 0
    if anchor ~= "CENTER" then
        dx = anchor:find("LEFT") and 1 or anchor:find("RIGHT") and -1 or 0
        dy = anchor:find("TOP") and -1 or anchor:find("BOTTOM") and 1 or 0
    end
    obj:SetPoint(anchor, obj:GetParent(), anchor, dx + (o.x or 0), dy + (o.y or 0))
end

-- Default anchor of a registered icon indicator, lower-case ("topleft"), for the Position dropdown
-- before the player has picked one.
function Indicators.DefaultPosition(name)
    for _, def in ipairs(registry) do
        if def.name == name and def.anchor then return def.anchor:lower() end
    end
    return "center"
end

local function runUpdate(button, def)
    if not button._mock and (not button.unit or not UnitExists(button.unit)) then return end
    local obj = button.indicators[def.name]
    if button._previewOnly and button._previewOnly ~= def.name then
        hideObj(obj)
        return
    end
    local o = N.db[button.groupKey].indicators[def.name]
    if not o or not (o.enabled or button._previewOnly == def.name) or (def.enabled and not def.enabled(button)) then
        hideObj(obj)
        return
    end
    styleIcon(obj, def, o)
    def.update(button, obj)
end

function Indicators.UpdateOne(button, name)
    if not button.indicators then return end
    for _, def in ipairs(registry) do
        if def.name == name then runUpdate(button, def) return end
    end
end

function Indicators.UpdateAll(button)
    if not button.indicators then return end
    for _, def in ipairs(registry) do
        runUpdate(button, def)
    end
end

local function dispatch(event, unit)
    for _, header in pairs(N.headers) do
        local i, child = 1, _G[header:GetName() .. "UnitButton1"]
        while child do
            local b = N.UnitFrame.ButtonOf(child)
            if b and b:IsShown() then
                if not unit or b.unit == unit then
                    for _, def in ipairs(byEvent[event] or {}) do
                        runUpdate(b, def)
                    end
                end
            end
            i = i + 1
            child = _G[header:GetName() .. "UnitButton" .. i]
        end
    end
end

-- Events whose fan-out must reach every button, not just arg1's unit (e.g. a
-- retarget changes the target counter on two other frames).
local BROADCAST = {
    UNIT_TARGET = true, PLAYER_TARGET_CHANGED = true, RAID_TARGET_UPDATE = true,
    PLAYER_REGEN_ENABLED = true, PLAYER_REGEN_DISABLED = true,
    INCOMING_SUMMON_CHANGED = true,
}

local evFrame = CreateFrame("Frame")
evFrame:SetScript("OnEvent", function(_, event, arg1)
    local unit
    if not BROADCAST[event] and type(arg1) == "string" and arg1:match("^[a-z]+%d*$") then
        unit = arg1
    end
    dispatch(event, unit)
end)

N:On("NUCLEUS_DB_READY", function()
    local events = {}
    for ev in pairs(byEvent) do events[#events + 1] = ev end
    for _, ev in ipairs(events) do
        evFrame:RegisterEvent(ev)
    end
end)

N:On("NUCLEUS_SETTING_CHANGED", function(_, _, path)
    if not (path and path:find("%.indicators%.")) then return end
    if N.RefreshAllButtons then N.RefreshAllButtons() end
end)

--------------------------------------------------------------------------------
-- Built-in indicators
--------------------------------------------------------------------------------

-- Ordered metadata: one options sub-tab per entry. `format` = has a format dropdown. name /
-- healthText / powerBar / status are rendered by UnitFrame, the rest are icon modules registered
-- below.
Indicators.builtins = {
    { name = "name", label = "Name", text = true, positioned = true },
    { name = "healthText", label = "Health Text", text = true, format = true, positioned = true },
    { name = "powerBar", label = "Power Bar", bar = true },
    { name = "levelText", label = "Level Text", text = true, levelFormat = true },
    { name = "status", label = "Status", status = true },
    { name = "statusIcon", label = "Status Icon", icon = true, iconPosition = true },
    { name = "role", label = "Role Icon", icon = true, iconPosition = true },
    { name = "classSpec", label = "Class / Spec Icon", icon = true, iconPosition = true, classSpec = true },
    { name = "leader", label = "Leader Icon", icon = true, iconPosition = true },
    { name = "readyCheck", label = "Ready Check", icon = true, iconPosition = true },
    { name = "raidMarker", label = "Raid Marker", icon = true, iconPosition = true },
    { name = "combatIcon", label = "Combat Icon", icon = true, iconPosition = true },
    { name = "missingBuffs", label = "Missing Buffs", missing = true },
    { name = "targetCounter", label = "Target Counter", text = true },
    { name = "absorbText", label = "Absorb Text", text = true, positioned = true, absorbFormat = true },
    { name = "shieldBar", label = "Shield Bar", shield = true },
    { name = "healthThresholds", label = "Health Thresholds", thresholds = true },
    { name = "aggroBorder", label = "Aggro Border", aggro = true },
    { name = "privateAura", label = "Private Aura", private = true },
}

local function corner(button, point, size)
    local t = (button.overlay or button):CreateTexture(nil, "OVERLAY")
    t:SetSize(size, size)
    t:SetPoint(point, button, point, point:find("LEFT") and 1 or -1, point:find("TOP") and -1 or 1)
    t:Hide()
    return t
end

-- Role icon art (hardcoded so it survives Blizzard removing its helpers).
-- "square" is our own set, Media/Textures/NucleusRoles.tga (tools/gen_textures.ps1), a 128x64
-- sheet of 32px tiles: tank shield, healer cross, damage sword. Row 1 ("square"): bright rounded
-- squares in the role colors. Row 2 ("square2"): flat dark tiles with a role-colored rim and a
-- tilted sword.
-- "circle" is Blizzard's round role sheet, Interface/LFGFrame/UI-LFG-ICON-ROLES (256x256, 67px
-- cells, same as GetTexCoordsForRole).
local ROLE_TC_SQUARE = {
    TANK    = { 0,    0.25, 0, 0.5 },
    HEALER  = { 0.25, 0.50, 0, 0.5 },
    DAMAGER = { 0.50, 0.75, 0, 0.5 },
}
local ROLE_TC_SQUARE2 = {
    TANK    = { 0,    0.25, 0.5, 1 },
    HEALER  = { 0.25, 0.50, 0.5, 1 },
    DAMAGER = { 0.50, 0.75, 0.5, 1 },
}
local ROLE_TC_CIRCLE = {
    TANK    = { 0,         67 / 256,  67 / 256, 134 / 256 },
    HEALER  = { 67 / 256, 134 / 256,   0,        67 / 256 },
    DAMAGER = { 67 / 256, 134 / 256,  67 / 256, 134 / 256 },
}

-- "Solo" for the role icon: no group, or a party made only of NPC companions (Brann in
-- Delves, follower dungeons) - the game counts those as a group.
local function playingSolo()
    if not IsInGroup() then return true end
    if IsInRaid() then return false end
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) and not (UnitInPartyIsAI and UnitInPartyIsAI(u)) then return false end
    end
    return true
end

Indicators.Register("role", {
    anchor = "TOPLEFT",
    events = {
        "PLAYER_ROLES_ASSIGNED", "GROUP_ROSTER_UPDATE",
        "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    },
    create = function(b) return corner(b, "TOPLEFT", 11) end,
    update = function(b, icon)
        local o = N.db[b.groupKey].indicators.role
        local role
        if b._mock then role = b._mock.role else role = UnitGroupRolesAssigned(b.unit) end
        if N.IsSecret(role) then icon:Hide(); return end

        -- Solo (your own frame, no group): the "Show when solo" switch decides. The game
        -- assigns no role then, so the one of your own specialization is used.
        if not b._mock and b.unit and playingSolo() then
            local me = UnitIsUnit(b.unit, "player")
            if me ~= nil and not N.IsSecret(me) and me then
                if o.showSolo == false then icon:Hide(); return end
                if role == nil or role == "NONE" then
                    local _, specRole = N.Profiles.GetSpec()
                    if specRole then role = specRole end
                end
            end
        end

        -- Which roles get an icon at all, and optionally none while in combat.
        if (role == "TANK" and o.showTank == false)
            or (role == "HEALER" and o.showHealer == false)
            or (role == "DAMAGER" and o.showDamager == false) then
            icon:Hide(); return
        end
        if o.hideInCombat and not b._mock and InCombatLockdown() then icon:Hide(); return end

        local round = (o.shape == "circle")
        local set = round and ROLE_TC_CIRCLE or (o.shape == "square2" and ROLE_TC_SQUARE2 or ROLE_TC_SQUARE)
        local tc = set[role]
        if not tc then icon:Hide(); return end
        icon:SetTexture(round and "Interface\\LFGFrame\\UI-LFG-ICON-ROLES" or M.tex.roles)
        icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        icon:Show()
    end,
})

-- Class / specialization icon (next to the role icon): all icons live on one sheet,
-- Media/Textures/NucleusClassSpec.tga (8 columns of 64px cells; M.classSpecCells). One small frame
-- holds the class and spec icon side by side; "spec" falls back to the class icon while a member's
-- spec is unknown.
local function sheetCoords(cell)
    local cw = 1 / 8
    local x0, y0 = (cell % 8) * cw, math.floor(cell / 8) * cw
    local pad = cw * 0.06
    return x0 + pad, x0 + cw - pad, y0 + pad, y0 + cw - pad
end

Indicators.Register("classSpec", {
    anchor = "TOPLEFT",
    events = { "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" },
    create = function(b)
        local f = CreateFrame("Frame", nil, b.overlay or b)
        f:SetSize(12, 12)
        f.class = f:CreateTexture(nil, "OVERLAY")
        f.spec = f:CreateTexture(nil, "OVERLAY")
        f.class:SetTexture(M.tex.classSpec)
        f.spec:SetTexture(M.tex.classSpec)
        f:Hide()
        return f
    end,
    update = function(b, f)
        local o = N.db[b.groupKey].indicators.classSpec
        local class, spec
        if b._mock then
            class = b._mock.class
            spec = b._mock.specID or (N.GroupSpec and N.GroupSpec.MockSpec(class, b._mock.role))
        else
            class = b.class
            spec = N.GroupSpec and b.unit and N.GroupSpec.Get(b.unit) or nil
        end
        if type(class) ~= "string" or N.IsSecret(class) then f:Hide(); return end

        local cells = M.classSpecCells
        local classCell = cells.class[class]
        local specCell = spec and cells.spec[spec]
        local mode = o.mode or "spec"
        local showClass = (mode == "class" or mode == "both") and classCell
        local showSpec = (mode == "spec" or mode == "both") and specCell
        if mode == "spec" and not specCell then showClass = classCell end
        local n = (showClass and 1 or 0) + (showSpec and 1 or 0)
        if n == 0 then f:Hide(); return end

        local s, gap, x = o.size or 12, 1, 0
        f:SetSize(s * n + gap * (n - 1), s)
        for _, part in ipairs({ { f.class, showClass }, { f.spec, showSpec } }) do
            local tex, cell = part[1], part[2]
            if cell then
                tex:SetSize(s, s)
                tex:ClearAllPoints()
                tex:SetPoint("LEFT", f, "LEFT", x, 0)
                tex:SetTexCoord(sheetCoords(cell))
                tex:Show()
                x = x + s + gap
            else
                tex:Hide()
            end
        end
        f:Show()
    end,
})

Indicators.Register("leader", {
    anchor = "TOPRIGHT",
    events = { "PARTY_LEADER_CHANGED", "GROUP_ROSTER_UPDATE" },
    create = function(b) return corner(b, "TOPRIGHT", 10) end,
    update = function(b, icon)
        local lead
        if b._mock then lead = b._mock.isLeader else lead = UnitIsGroupLeader(b.unit) end
        if not N.IsSecret(lead) and lead then
            icon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
            icon:SetTexCoord(0, 1, 0, 1)
            icon:Show()
        else
            icon:Hide()
        end
    end,
})

-- Blizzard's ready-check marks are atlases on current clients (the old
-- Interface/RaidFrame/ReadyCheck-* files and the globals pointing at them no longer give a visible
-- icon). The atlas is used when the client knows it, the old file path is the fallback.
local READY_ATLAS = {
    ready    = "UI-LFG-ReadyMark-Raid",
    notready = "UI-LFG-DeclineMark-Raid",
    waiting  = "UI-LFG-PendingMark-Raid",
}
local READY_TEX = {
    ready    = "Interface\\RaidFrame\\ReadyCheck-Ready",
    notready = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    waiting  = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}

local function setReadyIcon(icon, key)
    key = READY_ATLAS[key] and key or "waiting"
    local atlas = READY_ATLAS[key]
    if _G.C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        icon:SetAtlas(atlas)
    else
        icon:SetTexture(READY_TEX[key])
        icon:SetTexCoord(0, 1, 0, 1)
    end
    icon:SetVertexColor(1, 1, 1)
    icon:Show()
end

-- The marks stay up while the check runs and a few seconds after it ends, then disappear on their
-- own.
local READY_LINGER = 8
local readyActive, readyUntil = false, nil
local readyFrame = CreateFrame("Frame")
readyFrame:RegisterEvent("READY_CHECK")
readyFrame:RegisterEvent("READY_CHECK_FINISHED")
readyFrame:SetScript("OnEvent", function(_, event)
    if event == "READY_CHECK" then
        readyActive, readyUntil = true, nil
    else
        readyActive, readyUntil = false, GetTime() + READY_LINGER
        C_Timer.After(READY_LINGER + 0.2, function()
            if N.UnitFrame then
                N.UnitFrame.ForEachButton(function(child) Indicators.UpdateAll(child) end)
            end
        end)
    end
    -- Re-run once this state is set, whichever frame saw the event first.
    C_Timer.After(0, function()
        if N.UnitFrame then
            N.UnitFrame.ForEachButton(function(child) Indicators.UpdateAll(child) end)
        end
    end)
end)

Indicators.Register("readyCheck", {
    anchor = "CENTER",
    events = { "READY_CHECK", "READY_CHECK_CONFIRM", "READY_CHECK_FINISHED" },
    create = function(b)
        local t = (b.topOverlay or b.overlay or b):CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetSize(16, 16)
        t:SetPoint("CENTER")
        t:Hide()
        return t
    end,
    update = function(b, icon)
        if b._mock then
            if b._mock.readyCheck then setReadyIcon(icon, b._mock.readyCheck) else icon:Hide() end
            return
        end
        local running = readyActive or (readyUntil and GetTime() < readyUntil)
        local status = running and GetReadyCheckStatus(b.unit)
        if not status then
            icon:Hide()
            return
        end
        setReadyIcon(icon, status)
    end,
})

--------------------------------------------------------------------------------
-- Raid target marker
--------------------------------------------------------------------------------

Indicators.Register("raidMarker", {
    anchor = "TOP",
    events = { "RAID_TARGET_UPDATE" },
    create = function(b)
        local t = (b.overlay or b):CreateTexture(nil, "OVERLAY", nil, 3)
        t:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        t:Hide()
        return t
    end,
    update = function(b, icon)
        local idx
        if b._mock then idx = b._mock.raidMarker else idx = b.unit and GetRaidTargetIndex(b.unit) end
        if type(idx) == "number" and idx >= 1 and idx <= 8 then
            SetRaidTargetIconTexture(icon, idx)
            icon:Show()
        else
            icon:Hide()
        end
    end,
})

-- Status Icon: cross-group, incoming summon, phase. Combat Icon is a separate indicator.

-- Accepted / declined summons show for a few seconds and then drop off. `since` is stamped the
-- first time a state is seen.
local SUMMON_FADE = 6
local function summonStillShown(b, key)
    local seen = b._summonSeen
    if not seen or seen.key ~= key then
        seen = { key = key, t = GetTime() }
        b._summonSeen = seen
        C_Timer.After(SUMMON_FADE + 0.1, function() Indicators.UpdateAll(b) end)
    end
    return GetTime() - seen.t < SUMMON_FADE
end

local OTHER_PARTY_TEX = "Interface\\LFGFrame\\LFG-Eye"
local OTHER_PARTY_TC = { 0.14, 0.235, 0.28, 0.47 } -- the eye is a small part of the sheet
local PHASE_TEX  = "Interface\\TargetingFrame\\UI-PhasingIcon"
local REZ_TEX    = "Interface\\RaidFrame\\Raid-Icon-Rez"
local SUMMON_TEX = {
    pending  = "Interface\\RaidFrame\\Raid-Icon-SummonPending",
    accepted = "Interface\\RaidFrame\\Raid-Icon-SummonAccepted",
    declined = "Interface\\RaidFrame\\Raid-Icon-SummonDeclined",
}
local COMBAT_TEX = "Interface\\CharacterFrame\\UI-StateIcon"

-- Everything the Status Icon can show, in priority order (first match wins). `show` in the
-- settings switches each key; the options page lists them from here.
Indicators.statusIconKinds = {
    { key = "otherParty",  label = "In another group",
      icons = { { tex = OTHER_PARTY_TEX, coord = OTHER_PARTY_TC } } },
    { key = "incomingRez", label = "Incoming resurrection",
      icons = { { tex = REZ_TEX } } },
    { key = "rezDebuff",   label = "Resurrection pending",
      icons = { { tex = REZ_TEX, color = { 0.6, 1, 0.6 } } } },
    { key = "soulstone",   label = "Soulstone",
      icons = { { tex = REZ_TEX, color = { 1, 0.4, 1 } } } },
    { key = "summon",      label = "Summon",
      icons = { { tex = SUMMON_TEX.pending }, { tex = SUMMON_TEX.accepted }, { tex = SUMMON_TEX.declined } } },
    { key = "phase",       label = "Phased",
      icons = { { tex = PHASE_TEX, coord = { 0.1, 0.9, 0.1, 0.9 } } } },
    { key = "bgFlag",      label = "Flag carrier",
      icons = { { atlas = "nameplates-icon-flag-horde" }, { atlas = "nameplates-icon-flag-alliance" } } },
    { key = "bgOrb",       label = "Orb carrier",
      icons = { { atlas = "nameplates-icon-orb-blue" }, { atlas = "nameplates-icon-orb-green" },
                { atlas = "nameplates-icon-orb-orange" }, { atlas = "nameplates-icon-orb-purple" } } },
}

local function setStatusTex(icon, tex, l, r, t, bt, color)
    icon:SetTexture(tex)
    icon:SetTexCoord(l or 0, r or 1, t or 0, bt or 1)
    if color then icon:SetVertexColor(color[1], color[2], color[3]) else icon:SetVertexColor(1, 1, 1) end
    icon:Show()
end

local function setStatusAtlas(icon, atlas)
    icon:SetAtlas(atlas)
    icon:SetVertexColor(1, 1, 1)
    icon:Show()
end

-- UnitPhaseReason: 0 = plain phasing, 1 = sharding, 2 = war mode, 3 = Chromie Time. Tinted so the
-- reason is visible at a glance.
local PHASE_COLOR = {
    [0] = { 1.00, 1.00, 1.00 },
    [1] = { 0.50, 1.00, 0.50 },
    [2] = { 1.00, 0.60, 0.60 },
    [3] = { 1.00, 1.00, 0.00 },
}

-- Aura IDs: flag carrier buffs, orb carrier debuffs, rez debuffs, soulstone. Looked up by ID
-- inside pcall: the aura API is restricted for other units at times, and "unknown" must mean
-- "don't show", never an error.
local BG_FLAGS = { [156621] = "nameplates-icon-flag-alliance", [156618] = "nameplates-icon-flag-horde" }
local BG_ORBS = {
    [121164] = "nameplates-icon-orb-blue", [121175] = "nameplates-icon-orb-purple",
    [121176] = "nameplates-icon-orb-green", [121177] = "nameplates-icon-orb-orange",
}
local REZ_DEBUFFS = { 255234, 225080 }
local SOULSTONE = 20707

local function hasAura(unit, spellID)
    local fn = _G.C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID
    if not fn then return false end
    local ok, aura = pcall(fn, unit, spellID)
    return ok and type(aura) == "table"
end

local function inBattleground()
    if not _G.IsInInstance then return false end
    local _, kind = IsInInstance()
    return kind == "pvp"
end

local function isShown(o, key)
    return not (o.show and o.show[key] == false)
end

-- Aura-based kinds (rez pending, soulstone, flag / orb carrier) are looked up in a deferred timer
-- and cached on the button as b._auraKind. update() runs inside the secure header's own update,
-- and reading auras there taints it (Blizzard then blocks the header's SetPoint calls and the
-- whole layout breaks), so update() only reads the cache.
local function refreshAuraKind(b, wantDead)
    if b._auraPending then return end
    b._auraPending = true
    C_Timer.After(0, function()
        b._auraPending = nil
        local u = b.unit
        local kind
        if u and UnitExists(u) then
            local o = N.db[b.groupKey].indicators.statusIcon
            local dead = UnitIsDeadOrGhost(u)
            if not IsSecret(dead) and dead then
                if isShown(o, "rezDebuff") then
                    for _, id in ipairs(REZ_DEBUFFS) do
                        if hasAura(u, id) then kind = { key = "rezDebuff" }; break end
                    end
                end
                if not kind and isShown(o, "soulstone") and hasAura(u, SOULSTONE) then
                    kind = { key = "soulstone" }
                end
            end
            if not kind and inBattleground() then
                if isShown(o, "bgFlag") then
                    for id, atlas in pairs(BG_FLAGS) do
                        if hasAura(u, id) then kind = { key = "bgFlag", atlas = atlas }; break end
                    end
                end
                if not kind and isShown(o, "bgOrb") then
                    for id, atlas in pairs(BG_ORBS) do
                        if hasAura(u, id) then kind = { key = "bgOrb", atlas = atlas }; break end
                    end
                end
            end
        end
        local old = b._auraKind
        if (old and old.key) ~= (kind and kind.key) or (old and old.atlas) ~= (kind and kind.atlas) then
            b._auraKind = kind
            Indicators.UpdateAll(b)
        end
    end)
end

Indicators.Register("statusIcon", {
    anchor = "CENTER",
    events = {
        "UNIT_PHASE", "UNIT_FLAGS", "PARTY_MEMBER_ENABLE", "PARTY_MEMBER_DISABLE",
        "INCOMING_SUMMON_CHANGED", "INCOMING_RESURRECT_CHANGED", "GROUP_ROSTER_UPDATE",
        "UNIT_AURA", "UNIT_HEALTH",
    },
    create = function(b)
        local t = (b.overlay or b):CreateTexture(nil, "OVERLAY", nil, 3)
        t:Hide()
        return t
    end,
    update = function(b, icon)
        local o = N.db[b.groupKey].indicators.statusIcon

        if b._mock then
            local m = b._mock
            if m.otherParty and isShown(o, "otherParty") then
                setStatusTex(icon, OTHER_PARTY_TEX, OTHER_PARTY_TC[1], OTHER_PARTY_TC[2], OTHER_PARTY_TC[3], OTHER_PARTY_TC[4])
            elseif m.statusRez and isShown(o, "incomingRez") then
                setStatusTex(icon, REZ_TEX)
            elseif m.statusRezDebuff and isShown(o, "rezDebuff") then
                setStatusTex(icon, REZ_TEX, nil, nil, nil, nil, { 0.6, 1, 0.6 })
            elseif m.statusSoulstone and isShown(o, "soulstone") then
                setStatusTex(icon, REZ_TEX, nil, nil, nil, nil, { 1, 0.4, 1 })
            elseif (m.summonStatus or m.summon) and isShown(o, "summon") then
                setStatusTex(icon, SUMMON_TEX[m.summonStatus or "pending"] or SUMMON_TEX.pending)
            elseif m.phased and isShown(o, "phase") then
                setStatusTex(icon, PHASE_TEX, 0.1, 0.9, 0.1, 0.9)
            elseif m.bgFlag and isShown(o, "bgFlag") then
                setStatusAtlas(icon, "nameplates-icon-flag-" .. m.bgFlag)
            elseif m.bgOrb and isShown(o, "bgOrb") then
                setStatusAtlas(icon, "nameplates-icon-orb-" .. m.bgOrb)
            else
                icon:Hide()
            end
            return
        end

        local u = b.unit
        if not u then icon:Hide(); return end

        if isShown(o, "otherParty") then
            local otherParty = _G.UnitInOtherParty and UnitInOtherParty(u)
            if not IsSecret(otherParty) and otherParty then
                setStatusTex(icon, OTHER_PARTY_TEX, OTHER_PARTY_TC[1], OTHER_PARTY_TC[2],
                    OTHER_PARTY_TC[3], OTHER_PARTY_TC[4])
                return
            end
        end

        if isShown(o, "incomingRez") then
            local rez = _G.UnitHasIncomingResurrection and UnitHasIncomingResurrection(u)
            if not IsSecret(rez) and rez then setStatusTex(icon, REZ_TEX); return end
        end

        -- Aura lookups happen in a timer (see refreshAuraKind); only the cache is read here.
        local dead = UnitIsDeadOrGhost(u)
        local isDead = not IsSecret(dead) and dead
        if isDead or inBattleground() then refreshAuraKind(b) else b._auraKind = nil end
        local ak = b._auraKind

        if isDead and ak and ak.key == "rezDebuff" then
            setStatusTex(icon, REZ_TEX, nil, nil, nil, nil, { 0.6, 1, 0.6 }); return
        end
        if isDead and ak and ak.key == "soulstone" then
            setStatusTex(icon, REZ_TEX, nil, nil, nil, nil, { 1, 0.4, 1 }); return
        end

        if isShown(o, "summon") then
            local cs = _G.C_IncomingSummon
            local E = Enum and Enum.SummonStatus
            if cs and cs.IncomingSummonStatus and E then
                local ok, status = pcall(cs.IncomingSummonStatus, u)
                if ok and status and not IsSecret(status) and status ~= E.None then
                    if status == E.Accepted then
                        if summonStillShown(b, "accepted") then
                            setStatusTex(icon, SUMMON_TEX.accepted); return
                        end
                    elseif status == E.Declined then
                        if summonStillShown(b, "declined") then
                            setStatusTex(icon, SUMMON_TEX.declined); return
                        end
                    else
                        b._summonSeen = nil
                        setStatusTex(icon, SUMMON_TEX.pending); return
                    end
                end
            elseif cs and cs.HasIncomingSummon and cs.HasIncomingSummon(u) then
                setStatusTex(icon, SUMMON_TEX.pending); return
            end
        end

        if isShown(o, "phase") then
            local reason = _G.UnitPhaseReason and UnitPhaseReason(u)
            if not IsSecret(reason) and reason then
                local c = PHASE_COLOR[reason] or PHASE_COLOR[0]
                setStatusTex(icon, PHASE_TEX, 0.1, 0.9, 0.1, 0.9, c)
                return
            end
        end

        if ak and (ak.key == "bgFlag" or ak.key == "bgOrb") and ak.atlas then
            setStatusAtlas(icon, ak.atlas); return
        end

        icon:Hide()
    end,
})

-- Combat Icon: split from the Status Icon so it has its own placement.

Indicators.Register("combatIcon", {
    anchor = "BOTTOMRIGHT",
    events = { "UNIT_COMBAT", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED" },
    create = function(b)
        local t = (b.overlay or b):CreateTexture(nil, "OVERLAY", nil, 3)
        t:SetTexture(COMBAT_TEX)
        t:SetTexCoord(0.5, 1.0, 0.0, 0.484375)
        t:Hide()
        return t
    end,
    update = function(b, icon)
        if b._mock then icon:SetShown(b._mock.combat and true or false); return end
        local u = b.unit
        if not u then icon:Hide(); return end
        local combat = _G.UnitAffectingCombat and UnitAffectingCombat(u)
        icon:SetShown(not IsSecret(combat) and combat and true or false)
    end,
})

--------------------------------------------------------------------------------
-- Target counter: how many group members are targeting this unit
--------------------------------------------------------------------------------

local function countTargeting(b)
    if b._mock then return b._mock.targetedBy or 0 end
    local u = b.unit
    if not u then return 0 end
    local n = 0
    local prefix, cnt
    if IsInRaid() then prefix, cnt = "raid", 40 else prefix, cnt = "party", 4 end
    for i = 1, cnt do
        local tgt = prefix .. i .. "target"
        if UnitExists(tgt) then
            local same = UnitIsUnit(tgt, u)
            if not IsSecret(same) and same then n = n + 1 end
        end
    end
    if not IsInRaid() and UnitExists("playertarget") then
        local same = UnitIsUnit("playertarget", u)
        if not IsSecret(same) and same then n = n + 1 end
    end
    return n
end

Indicators.Register("targetCounter", {
    events = { "UNIT_TARGET", "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE" },
    create = function(b)
        local fs = N.FontString(b.overlay or b, 11)
        fs:SetJustifyH("CENTER")
        fs:Hide()
        return fs
    end,
    update = function(b, fs)
        local o = N.db[b.groupKey].indicators.targetCounter
        fs:SetFont(M.font, o.size or 11, "OUTLINE")
        local c = o.color or { 1, 0.85, 0.3 }
        fs:SetTextColor(c[1], c[2], c[3])
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", b, "CENTER", o.x or 0, o.y or 0)
        local n = countTargeting(b)
        if n and n > 0 then fs:SetText(n); fs:Show() else fs:SetText(""); fs:Hide() end
    end,
})

-- Absorb text: the unit's total absorb shield as a number. Formats: "short" (12K), "full" (12,345)
-- or "percent" of max health. Nine positions and a class-color option like the other texts.

local function setAbsorbText(b, fs, v, mode)
    if v == nil then fs:SetText(""); fs:Hide(); return end

    if IsSecret(v) then
        -- Zero can't be compared, but TruncateWhenZero (a secret-safe sink) blanks it; the amount
        -- itself only goes into a FontString.
        local trunc = _G.C_StringUtil and C_StringUtil.TruncateWhenZero
        if trunc then
            fs:SetText(trunc(v))
            local t = fs:GetText()
            if not t or (not IsSecret(t) and t == "") then fs:Hide(); return end
        end
        if mode == "full" then
            fs:SetFormattedText("%d", v)
        else
            local ok, s = pcall(Abbrev, v)
            if ok then fs:SetText(s) else fs:SetFormattedText("%d", v) end
        end
        fs:Show()
        return
    end

    if type(v) ~= "number" or v <= 0 then fs:SetText(""); fs:Hide(); return end
    local hpMax = b.hpMax
    if mode == "percent" and type(hpMax) == "number" and not IsSecret(hpMax) and hpMax > 0 then
        fs:SetFormattedText("%d%%", v / hpMax * 100)
    elseif mode == "full" then
        fs:SetText(_G.BreakUpLargeNumbers and BreakUpLargeNumbers(v) or tostring(v))
    else
        fs:SetText(Abbrev(v))
    end
    fs:Show()
end

Indicators.Register("absorbText", {
    events = { "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_MAXHEALTH" },
    create = function(b)
        local fs = N.FontString(b.overlay or b, 10)
        fs:SetJustifyH("CENTER")
        fs:Hide()
        return fs
    end,
    update = function(b, fs)
        local o = N.db[b.groupKey].indicators.absorbText
        fs:SetFont(M.font, o.size or 10, "OUTLINE")
        local r, g, bl
        if o.colorMode == "class" then
            r, g, bl = N.ClassRGB(b.class)
        else
            local c = o.color or { 0.75, 0.9, 1 }
            r, g, bl = c[1], c[2], c[3]
        end
        fs:SetTextColor(r, g, bl)
        N.UnitFrame.PlaceText(fs, b.health or b, o)

        local v
        if b._mock then v = b._mock.absorb
        elseif _G.UnitGetTotalAbsorbs and b.unit then v = UnitGetTotalAbsorbs(b.unit) end
        setAbsorbText(b, fs, v, o.format)
    end,
})

-- Status: a small rounded pill naming the unit's state (Offline, AFK, Feign Death, Ghost, Dead,
-- the three summon states) in a per-state color, with an optional running timer for Offline / AFK.
-- Position (top / center / bottom of the health bar, y offset, left / center / right) is a setting
-- and each state can be switched off. It sits on top of the name / health text instead of
-- replacing them.

-- Priority order (first match wins), shared with the options UI (one color row per state) and the
-- preview.
Indicators.statusStates = {
    { key = "offline",        label = "Offline" },
    { key = "afk",            label = "AFK" },
    { key = "feignDeath",     label = "Feign Death" },
    { key = "ghost",          label = "Ghost" },
    { key = "dead",           label = "Dead" },
    { key = "drinking",       label = "Drinking" },
    { key = "summonPending",  label = "Summon Pending" },
    { key = "summonAccepted", label = "Summon Accepted" },
    { key = "summonDeclined", label = "Summon Declined" },
}

-- Drink / food spells (spell IDs); matched by ID and by name, as the auras of
-- other players read differently across the game's versions.
local DRINK_IDS = { 170906, 167152, 430, 43182, 172786, 308433, 369162, 456574, 461063 }
local drinkNames
local function drinkSet()
    if drinkNames then return drinkNames end
    drinkNames = { ids = {}, names = {} }
    for _, id in ipairs(DRINK_IDS) do
        drinkNames.ids[id] = true
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
        if name then drinkNames.names[name] = true end
    end
    return drinkNames
end

-- Only out of combat: in combat the game seals other units' auras (and nobody
-- drinks in combat).
local function isDrinking(b)
    if InCombatLockdown() or not (N.AuraCache and N.AuraCache.Each) then return false end
    -- The status updates on every health change: look at the auras once a second at most.
    local now = GetTime()
    if b._drinkAt and now - b._drinkAt < 1 then return b._drinking end
    b._drinkAt = now
    b._drinking = false
    local set = drinkSet()
    for _, d in ipairs(N.AuraCache.Each(b.unit, "HELPFUL")) do
        local id, name = d.spellId, d.name
        if (id ~= nil and not IsSecret(id) and set.ids[id])
            or (name ~= nil and not IsSecret(name) and set.names[name]) then
            b._drinking = true
            break
        end
    end
    return b._drinking
end

local function statusState(b)
    if b._mock then
        local m = b._mock
        if m.connected == false then return "offline" end
        if m.afk then return "afk" end
        if m.feignDeath then return "feignDeath" end
        if m.ghost then return "ghost" end
        if m.dead then return "dead" end
        if m.drinking then return "drinking" end
        if m.summonStatus == "pending" then return "summonPending" end
        if m.summonStatus == "accepted" then return "summonAccepted" end
        if m.summonStatus == "declined" then return "summonDeclined" end
        return nil
    end
    local u = b.unit
    if not u then return nil end
    local connected = UnitIsConnected(u)
    if not IsSecret(connected) and connected == false then return "offline" end
    local afk = _G.UnitIsAFK and UnitIsAFK(u)
    if not IsSecret(afk) and afk then return "afk" end
    local feign = _G.UnitIsFeignDeath and UnitIsFeignDeath(u)
    if not IsSecret(feign) and feign then return "feignDeath" end
    local ghost = _G.UnitIsGhost and UnitIsGhost(u)
    if not IsSecret(ghost) and ghost then return "ghost" end
    local dead = UnitIsDeadOrGhost(u)
    if not IsSecret(dead) and dead then return "dead" end
    if isDrinking(b) then return "drinking" end
    local cs = _G.C_IncomingSummon
    if cs and cs.IncomingSummonStatus and Enum and Enum.SummonStatus then
        local ok, status = pcall(cs.IncomingSummonStatus, u)
        if ok and status and not IsSecret(status) then
            if status == Enum.SummonStatus.Pending then
                b._summonSeen = nil
                return "summonPending"
            elseif status == Enum.SummonStatus.Accepted then
                if summonStillShown(b, "accepted") then return "summonAccepted" end
                return nil
            elseif status == Enum.SummonStatus.Declined then
                if summonStillShown(b, "declined") then return "summonDeclined" end
                return nil
            end
        end
    end
    b._summonSeen = nil
    return nil
end

-- A unit's auras changed (the aura cache calls this): look for the drink again now.
N:On("NUCLEUS_DB_READY", function()
    if not (N.AuraCache and N.AuraCache.OnChange) then return end
    N.AuraCache.OnChange(function(unit)
        if not N.UnitFrame then return end
        N.UnitFrame.ForEachButton(function(child)
            if child.unit == unit and child._drinkAt then
                child._drinkAt = nil
                Indicators.UpdateOne(child, "status")
            end
        end)
    end)
end)

-- "3:07" / "1:02:09"
local function formatElapsed(sec)
    sec = math.max(0, math.floor(sec))
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    if h > 0 then return string.format("%d:%02d:%02d", h, m, sec % 60) end
    return string.format("%d:%02d", m, sec % 60)
end

local TIMED = { offline = true, afk = true }

local PILL_PAD = 6

local function layoutPill(f, o)
    local pill = f.pill
    local size = o.size or 11
    local w = f.text:GetStringWidth()
    if f.timer:IsShown() then w = w + 5 + f.timer:GetStringWidth() end
    pill:SetSize(math.max(w + PILL_PAD * 2, 16), size + 6)
end

Indicators.Register("status", {
    events = {
        "UNIT_CONNECTION", "UNIT_HEALTH", "UNIT_FLAGS", "PLAYER_FLAGS_CHANGED",
        "INCOMING_SUMMON_CHANGED", "GROUP_ROSTER_UPDATE",
    },
    create = function(b)
        local f = CreateFrame("Frame", nil, b.topOverlay or b.overlay or b)
        f:Hide()
        local pill = CreateFrame("Frame", nil, f)
        N.SkinRound(pill, { 0.04, 0.045, 0.055, 0.86 }, { 1, 1, 1, 0.5 }, true)
        f.pill = pill
        f.text = N.FontString(pill, 11)
        f.text:SetWordWrap(false)
        f.timer = N.FontString(pill, 11)
        f.timer:SetWordWrap(false)
        return f
    end,
    update = function(b, f)
        local o = N.db[b.groupKey].indicators.status
        local state = statusState(b)
        if state and o.show and o.show[state] == false then state = nil end
        if not state then
            f:Hide()
            f:SetScript("OnUpdate", nil)
            b._statusState = nil
            return
        end

        if b._statusState ~= state then
            b._statusState = state
            b._statusSince = GetTime() - (b._mock and 125 or 0)
        end

        local size = o.size or 11
        local c = (o.stateColors and o.stateColors[state]) or { 1, 1, 1 }
        f.text:SetFont(M.font, size, "OUTLINE")
        f.timer:SetFont(M.font, size, "OUTLINE")
        local label
        for _, s in ipairs(Indicators.statusStates) do
            if s.key == state then label = s.label; break end
        end
        f.text:SetText(L[label] or label or "")
        f.text:SetTextColor(c[1], c[2], c[3])
        f.timer:SetTextColor(c[1], c[2], c[3], 0.8)

        local host = b.health or b
        local point = (o.anchor == "top" and "TOP") or (o.anchor == "center" and "CENTER") or "BOTTOM"
        f:ClearAllPoints()
        f:SetPoint("LEFT", host, "LEFT", 0, 0)
        f:SetPoint("RIGHT", host, "RIGHT", 0, 0)
        f:SetPoint(point, host, point, 0, o.y or 0)
        f:SetHeight(size + 6)

        local pill = f.pill
        pill:ClearAllPoints()
        if o.align == "left" then pill:SetPoint("LEFT", f, "LEFT", 3, 0)
        elseif o.align == "right" then pill:SetPoint("RIGHT", f, "RIGHT", -3, 0)
        else pill:SetPoint("CENTER", f, "CENTER", 0, 0) end
        local bg = o.showBackground
        pill._nucFill:SetShown(bg)
        pill._nucBorder[1]:SetShown(bg)
        if bg then N.SetPanelBorder(pill, { c[1], c[2], c[3], 0.75 }) end

        f.text:ClearAllPoints()
        f.text:SetPoint("LEFT", pill, "LEFT", PILL_PAD, 0)
        f.timer:ClearAllPoints()
        f.timer:SetPoint("LEFT", f.text, "RIGHT", 5, 0)

        if o.showTimer and TIMED[state] then
            f.timer:Show()
            f.timer:SetText(formatElapsed(GetTime() - b._statusSince))
            f._acc = 0
            f:SetScript("OnUpdate", function(self, elapsed)
                self._acc = (self._acc or 0) + elapsed
                if self._acc < 0.5 then return end
                self._acc = 0
                self.timer:SetText(formatElapsed(GetTime() - (b._statusSince or GetTime())))
                layoutPill(self, N.db[b.groupKey].indicators.status)
            end)
        else
            f.timer:SetText("")
            f.timer:Hide()
            f:SetScript("OnUpdate", nil)
        end
        layoutPill(f, o)
        f:Show()
    end,
})

-- Shield Bar: a thin bar along the bottom or top edge of the health bar, its length the absorb
-- shield as a fraction of max health. Separate from the shield overlay on the health bar
-- (Appearance > Shield). Optionally shown only when the shield overflows the missing health
-- ("overshield").
--
-- Secret-safe: the fill is driven by StatusBar:SetMinMaxValues / SetValue, which accept secret
-- numbers, and the overshield flag (possibly a secret boolean) goes straight into
-- SetAlphaFromBoolean, never into a Lua test.

Indicators.Register("shieldBar", {
    create = function(b)
        local bar = CreateFrame("StatusBar", nil, b.overlay or b)
        bar:SetStatusBarTexture(M.flat)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar:EnableMouse(false)
        bar:Hide()
        return bar
    end,
    update = function(b, bar)
        local o = N.db[b.groupKey].indicators.shieldBar
        local host = b.health or b
        local atTop = (o.position == "top")

        local ox, oy = o.x or 0, o.y or 0
        bar:ClearAllPoints()
        if atTop then
            bar:SetPoint("TOPLEFT", host, "TOPLEFT", ox, oy)
            bar:SetPoint("TOPRIGHT", host, "TOPRIGHT", ox, oy)
        else
            bar:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", ox, oy)
            bar:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", ox, oy)
        end
        bar:SetHeight(o.height or 4)
        if bar.SetReverseFill then bar:SetReverseFill(o.growFrom == "right") end

        local c = o.color or { 1, 1, 1 }
        bar:SetStatusBarColor(c[1], c[2], c[3], o.alpha or 0.8)
        bar:SetMinMaxValues(0, b.hpMax or 1)
        bar:SetValue(b.absorbAmt or 0)

        -- "Only show overshields": the flag may be a secret boolean, so it goes to a native sink
        -- instead of being branched on.
        if o.onlyOvershield then
            local ov = b._overshield
            if ov ~= nil and bar.SetAlphaFromBoolean then
                bar:SetAlphaFromBoolean(ov, 1, 0)
            elseif ov ~= nil and not IsSecret(ov) and ov then
                bar:SetAlpha(1)
            else
                bar:SetAlpha(0)
            end
        else
            bar:SetAlpha(1)
        end
        bar:Show()
    end,
})

-- Health Thresholds: a thin line across the health bar once health has fallen below one of the
-- chosen percentages. It shows the lowest percentage the unit is still under, so 90 / 50 / 25 show
-- one line at a time (the next one it is about to cross). Lines are placed from the bar's width.
--
-- Secret-safe: with readable health the numbers decide. When health is hidden, the game's health
-- calculator evaluates a color curve (alpha 1 inside the window between the previous percentage
-- and this one, 0 elsewhere) and the resulting alpha goes straight into SetAlpha.

Indicators.THRESHOLD_MAX = 8

local thresholdCurves = {}
local function curvesFor(fracs)
    local key = table.concat(fracs, ",")
    local c = thresholdCurves[key]
    if c ~= nil then return c or nil end
    thresholdCurves[key] = false
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local opaque, invisible = CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 0)
    -- Band i is "on" from the previous threshold up to this one: a curve that jumps
    -- to opaque at the lower edge and back to invisible at the upper edge. Each jump
    -- is a pair of points a hair apart, so the curve stays valid (x strictly rising).
    local EDGE = 1e-4
    local function band(lo, hi)
        local curve = C_CurveUtil.CreateColorCurve()
        local pts = {}
        if lo > 0 then
            pts[#pts + 1] = { 0, invisible }
            pts[#pts + 1] = { lo - EDGE, invisible }
        end
        pts[#pts + 1] = { lo, opaque }
        pts[#pts + 1] = { math.max(hi - EDGE, lo), opaque }
        pts[#pts + 1] = { hi, invisible }
        pts[#pts + 1] = { 1, invisible }
        for _, p in ipairs(pts) do curve:AddPoint(p[1], p[2]) end
        return curve
    end
    local list = {}
    for i, hi in ipairs(fracs) do
        list[i] = band(i > 1 and fracs[i - 1] or 0, hi)
    end
    thresholdCurves[key] = list
    return list
end

Indicators.Register("healthThresholds", {
    create = function(b)
        local obj = { lines = {}, button = b }
        function obj:Hide()
            for _, t in ipairs(self.lines) do t:Hide() end
        end
        return obj
    end,
    update = function(b, obj)
        local o = N.db[b.groupKey].indicators.healthThresholds
        local host = b.health or b
        -- The lines are placed from the bar's width: place them again whenever it changes.
        if not obj.hooked and host.HookScript then
            obj.hooked = true
            host:HookScript("OnSizeChanged", function()
                if Indicators.UpdateOne then Indicators.UpdateOne(b, "healthThresholds") end
            end)
        end
        local w = host:GetWidth() or 0
        local th = N.Snap(b, math.max(1, o.thickness or 1))

        local sorted = {}
        for i, e in ipairs(o.thresholds or {}) do
            if i <= Indicators.THRESHOLD_MAX then sorted[#sorted + 1] = e end
        end
        table.sort(sorted, function(a, c) return (a.pct or 0) < (c.pct or 0) end)
        local fracs = {}
        for i, e in ipairs(sorted) do fracs[i] = math.max(0, math.min(100, e.pct or 0)) / 100 end

        -- Which line(s) show, and how strongly: alphas[i] = 0..1, or a hidden-health
        -- evaluation (alpha from the curve) when the numbers are not readable.
        local alphas, evaluate
        if b._previewOnly == "healthThresholds" then
            alphas = {}
            for i = 1, #sorted do alphas[i] = 1 end
        else
            local frac
            if b._mock then
                if b.hpMax and b.hpMax > 0 and b.hp then frac = b.hp / b.hpMax end
            elseif b.unit then
                frac = N.HealthFraction(b.unit)
            end
            if frac ~= nil then
                alphas = {}
                for i = 1, #sorted do
                    local prev = (i > 1) and fracs[i - 1] or 0
                    alphas[i] = (frac < fracs[i] and frac >= prev) and 1 or 0
                end
            elseif b.unit and _G.CreateUnitHealPredictionCalculator and _G.UnitGetDetailedHealPrediction then
                obj.calc = obj.calc or CreateUnitHealPredictionCalculator()
                pcall(UnitGetDetailedHealPrediction, b.unit, nil, obj.calc)
                local curves = curvesFor(fracs)
                if curves and obj.calc.EvaluateCurrentHealthPercent then
                    evaluate = function(i)
                        local ok, color = pcall(obj.calc.EvaluateCurrentHealthPercent, obj.calc, curves[i])
                        if ok and color then return select(4, color:GetRGBA()) end
                    end
                end
            end
        end

        for i = 1, math.max(#obj.lines, #sorted) do
            local t = obj.lines[i]
            local e = sorted[i]
            if e and w > 0 and (alphas or evaluate) then
                if not t then
                    t = (b.overlay or b):CreateTexture(nil, "OVERLAY", nil, 2)
                    t:SetTexture(M.flat)
                    obj.lines[i] = t
                end
                local c = e.color or { 1, 0, 0 }
                t:SetVertexColor(c[1], c[2], c[3], 1)
                local x = math.floor(w * fracs[i] - th / 2 + 0.5)
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", host, "TOPLEFT", x, 0)
                t:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", x, 0)
                t:SetWidth(th)
                if evaluate then
                    local a = evaluate(i)
                    if a ~= nil then t:SetAlpha(a); t:Show() else t:Hide() end
                else
                    if alphas[i] > 0 then t:SetAlpha(1); t:Show() else t:Hide() end
                end
            elseif t then
                t:Hide()
            end
        end
    end,
})
-- Aggro Border: a border inside the frame while an enemy is about to switch to the unit (orange,
-- "almost aggro") or attacks it (red, "aggro"). Blizzard's yellow "building threat" level is not
-- shown. Both colors are settings, defaulting to Blizzard's threat colors. The edges fade toward
-- the inside or can be solid. Replaces the old fixed red edge.

Indicators.Register("aggroBorder", {
    events = {
        "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE",
        "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    },
    -- The four edges are plain textures on the button's overlay (not a child frame), so the target
    -- / mouseover outline keeps drawing above them.
    create = function(b)
        local host = b.overlay or b
        local edges = {}
        for _, side in ipairs({ "top", "bottom", "left", "right" }) do
            local t = host:CreateTexture(nil, "OVERLAY")
            t:SetTexture(M.flat)
            t:Hide()
            edges[side] = t
        end
        local p1, m1 = N.Snap(b, 1), N.Snap(b, -1)
        edges.top:SetPoint("TOPLEFT", b, "TOPLEFT", p1, m1)
        edges.top:SetPoint("TOPRIGHT", b, "TOPRIGHT", m1, m1)
        edges.bottom:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", p1, p1)
        edges.bottom:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", m1, p1)
        edges.left:SetPoint("TOPLEFT", b, "TOPLEFT", p1, m1)
        edges.left:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", p1, p1)
        edges.right:SetPoint("TOPRIGHT", b, "TOPRIGHT", m1, m1)
        edges.right:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", m1, p1)

        local obj = { edges = edges }
        function obj:Hide()
            for _, t in pairs(edges) do t:Hide() end
        end
        function obj:Paint(r, g, bl, thickness, fade)
            thickness = N.Snap(b, thickness)
            edges.top:SetHeight(thickness); edges.bottom:SetHeight(thickness)
            edges.left:SetWidth(thickness); edges.right:SetWidth(thickness)
            if fade then
                local lo = 0.2
                edges.top:SetGradient("VERTICAL", CreateColor(r, g, bl, lo), CreateColor(r, g, bl, 1))
                edges.bottom:SetGradient("VERTICAL", CreateColor(r, g, bl, 1), CreateColor(r, g, bl, lo))
                edges.left:SetGradient("HORIZONTAL", CreateColor(r, g, bl, 1), CreateColor(r, g, bl, lo))
                edges.right:SetGradient("HORIZONTAL", CreateColor(r, g, bl, lo), CreateColor(r, g, bl, 1))
            else
                for _, t in pairs(edges) do
                    t:SetGradient("VERTICAL", CreateColor(r, g, bl, 1), CreateColor(r, g, bl, 1))
                end
            end
            for _, t in pairs(edges) do t:Show() end
        end
        return obj
    end,
    update = function(b, obj)
        local o = N.db[b.groupKey].indicators.aggroBorder
        local status
        if b._mock then
            status = b._mock.threat or (b._mock.aggro and 3 or 0)
        elseif b.unit then
            status = UnitThreatSituation(b.unit)
        end
        -- Unknown or hidden (secret) threat shows nothing rather than guessing;
        -- level 1 (yellow in Blizzard's scheme) is not shown either.
        if type(status) ~= "number" or IsSecret(status) or status < 2 then
            obj:Hide()
            return
        end
        local c = (status >= 3) and (o.tankColor or { 1, 0, 0 }) or (o.warnColor or { 1, 0.6, 0 })
        obj:Paint(c[1], c[2], c[3], o.thickness or 2, o.gradient ~= false)
    end,
})

-- Level text: the unit's level as "Level 80", "Lvl 80" or just "80".

Indicators.Register("levelText", {
    events = { "UNIT_LEVEL", "PLAYER_LEVEL_UP", "GROUP_ROSTER_UPDATE" },
    create = function(b)
        local fs = N.FontString(b.overlay or b, 10)
        fs:SetJustifyH("CENTER")
        fs:Hide()
        return fs
    end,
    update = function(b, fs)
        local o = N.db[b.groupKey].indicators.levelText
        fs:SetFont(M.font, o.size or 10, "OUTLINE")
        local c = o.color or { 0.85, 0.85, 0.87 }
        fs:SetTextColor(c[1], c[2], c[3])
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", b, "CENTER", o.x or 0, o.y or 0)

        local level
        if b._mock then
            level = b._mock.level or 80
        elseif b.unit then
            level = UnitEffectiveLevel and UnitEffectiveLevel(b.unit) or UnitLevel(b.unit)
        end
        if level == nil then
            fs:SetText("")
            fs:Hide()
            return
        end

        -- A unit's level can come back as a secret number. It can't be compared against 0 for the
        -- "??" case, but SetFormattedText is a secret-safe sink, so it goes straight through. The
        -- format choice is our own setting, never derived from the secret value.
        local fmt = o.format
        local word = (fmt == "short") and L["Lvl"] or L["Level"]
        if IsSecret(level) then
            if fmt == "number" then
                fs:SetFormattedText("%d", level)
            else
                fs:SetFormattedText(word .. " %d", level)
            end
        else
            local str = (level > 0) and level or "??"
            if fmt == "number" then
                fs:SetText(str)
            else
                fs:SetFormattedText(word .. " %s", str)
            end
        end
        fs:Show()
    end,
})
