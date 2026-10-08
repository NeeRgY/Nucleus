local _, ns = ...
local N = ns.N
local M = N.Media
local L = N.L

-- Copy settings between the Party and the Raid half of the active profile.
-- A popup lets the user pick the direction and exactly which parts to copy;
-- everything not ticked stays as it is.

local function uc(c) return c[1], c[2], c[3], c[4] or 1 end

-- Plain keys of a group that belong together.
local GROUP_KEYS = {
    size     = { "width", "height", "spacing", "columnSpacing" },
    layout   = { "orientation", "reverse", "groupBy", "sortMethod", "unitsPerColumn", "maxColumns",
                 "attachEnabled", "attachSide", "attachGap", "attachShift", "ordering" },
    position = { "point", "x", "y" },
}

local CATEGORIES = {
    { id = "size", label = "Size & spacing" },
    { id = "layout", label = "Arrangement (direction, order, columns)" },
    { id = "position", label = "Position on screen" },
    { id = "appearance", label = "Appearance (bars, colours, borders)" },
    { id = "custom", label = "Custom indicators (all of them)" },
}

local AURA_ROWS = {
    { id = "buffs", label = "Buffs" },
    { id = "debuffs", label = "Debuffs" },
    { id = "dispels", label = "Dispellable Debuffs" },
    { id = "defensives", label = "Defensive Cooldowns" },
    { id = "externals", label = "External Cooldowns" },
    { id = "offensives", label = "Offensive Cooldowns" },
    { id = "crowdControls", label = "Crowd Controls" },
}

local state = { from = "party", to = "raid", sel = {} }
local GROUPS = { "party", "raid", "ownPet", "groupPets", "npc" }
local popup, checks

local function setAll(on)
    for id in pairs(state.sel) do state.sel[id] = on end
    for _, cat in ipairs(CATEGORIES) do state.sel["cat:" .. cat.id] = on end
    for _, meta in ipairs(N.Indicators.builtins) do state.sel["ind:" .. meta.name] = on end
    for _, row in ipairs(AURA_ROWS) do state.sel["aura:" .. row.id] = on end
    for _, cb in ipairs(checks) do cb.Refresh() end
end

local function count()
    local n = 0
    for _, v in pairs(state.sel) do if v then n = n + 1 end end
    return n
end

local function directions()
    local from, to = state.from, state.to
    return from, to
end

local function doCopy()
    local from, to = directions()
    local src, dst = N.db[from], N.db[to]
    local function copyKey(tbl, key, srcTbl)
        if srcTbl[key] ~= nil then tbl[key] = N.DeepCopy(srcTbl[key]) end
    end
    for _, cat in ipairs(CATEGORIES) do
        if state.sel["cat:" .. cat.id] then
            if cat.id == "appearance" then
                copyKey(dst, "appearance", src)
            elseif cat.id == "custom" then
                copyKey(dst, "customIndicators", src)
            else
                for _, k in ipairs(GROUP_KEYS[cat.id]) do copyKey(dst, k, src) end
            end
        end
    end
    for _, meta in ipairs(N.Indicators.builtins) do
        if state.sel["ind:" .. meta.name] then copyKey(dst.indicators, meta.name, src.indicators) end
    end
    for _, row in ipairs(AURA_ROWS) do
        if state.sel["aura:" .. row.id] then copyKey(dst.auras, row.id, src.auras) end
    end

    -- Tell the frames to re-read the target half (same set a profile switch uses).
    N:Fire("NUCLEUS_SETTING_CHANGED", to, to .. ".enabled", dst.enabled)
    N:Fire("NUCLEUS_SETTING_CHANGED", to, to .. ".width", dst.width)
    N:Fire("NUCLEUS_SETTING_CHANGED", to, to .. ".indicators.name.enabled")
    N:Fire("NUCLEUS_SETTING_CHANGED", to, to .. ".auras.buffs.enabled")
    N:Fire("NUCLEUS_SETTING_CHANGED", to, to .. ".appearance.barTexture")
    -- Open option pages hold the old tables: have them rebuild.
    N:Fire("NUCLEUS_PROFILE_CHANGED", N.Profiles.Current())
    N:Print(L["COPY_DONE"]:format(L["MODE_" .. from], L["MODE_" .. to]))
end

local function build()
    local win, child = N.BuildPopupShell("NucleusCopyPopup", L["Copy settings"], 440, 600)
    checks = {}

    local function check(card, key, label)
        local cb = N.MakeCheckbox(card, label,
            function() return state.sel[key] end,
            function(v) state.sel[key] = v end)
        checks[#checks + 1] = cb
        card:AddRow(cb)
    end

    local dir = N.MakeCard(child, L["Direction"])
    local opts = {}
    for _, g in ipairs(GROUPS) do opts[#opts + 1] = { value = g, text = L["MODE_" .. g] } end
    local ddFrom, ddTo
    ddFrom = N.MakeDropdown(dir, L["Copy from"], opts, function() return state.from end, function(v)
        state.from = v
        if state.to == v then -- source and target must differ
            state.to = (v == "party") and "raid" or "party"
            if ddTo then ddTo.Refresh() end
        end
    end)
    ddTo = N.MakeDropdown(dir, L["Copy to"], opts, function() return state.to end, function(v)
        state.to = v
        if state.from == v then
            state.from = (v == "party") and "raid" or "party"
            if ddFrom then ddFrom.Refresh() end
        end
    end)
    dir:AddRow(ddFrom)
    dir:AddRow(ddTo)
    win.ddFrom, win.ddTo = ddFrom, ddTo
    child:AddCard(dir)

    local general = N.MakeCard(child, L["Frame"])
    for _, cat in ipairs(CATEGORIES) do check(general, "cat:" .. cat.id, L[cat.label]) end
    child:AddCard(general)

    local ind = N.MakeCard(child, L["Indicators"])
    for _, meta in ipairs(N.Indicators.builtins) do check(ind, "ind:" .. meta.name, L[meta.label]) end
    child:AddCard(ind)

    local auras = N.MakeCard(child, L["Auras"])
    for _, row in ipairs(AURA_ROWS) do check(auras, "aura:" .. row.id, L[row.label]) end
    child:AddCard(auras)

    local act = N.MakeCard(child, L["Copy"])
    local function btn(label, onClick)
        local b = CreateFrame("Button", nil, act)
        b._rowHeight = 28
        N.SkinButton(b)
        local fs = N.FontString(b, 12)
        fs:SetPoint("CENTER")
        fs:SetText(label)
        b:SetScript("OnClick", onClick)
        return b
    end
    act:AddRow(btn(L["Select all"], function() setAll(true) end))
    act:AddRow(btn(L["Select none"], function() setAll(false) end))
    act:AddRow(btn(L["Copy now"], function()
        if count() == 0 then return end
        local from, to = directions()
        N.Dialog.Confirm(
            L["COPY_CONFIRM"]:format(L["MODE_" .. from], L["MODE_" .. to]), doCopy)
    end))
    child:AddCard(act)

    return win
end

function N.ShowCopyPopup()
    if not popup then popup = build() end
    -- Default direction: from the group being edited to the "other" one.
    local mode = N:Mode()
    state.from = mode
    state.to = (mode == "party") and "raid" or (mode == "raid") and "party" or "party"
    if popup.ddFrom then popup.ddFrom.Refresh(); popup.ddTo.Refresh() end
    popup:SetShown(not popup:IsShown())
end
