local _, ns = ...
local N = ns.N
local M = N.Media
local L = N.L
local IsSecret = N.IsSecret


local GL = {}
N.GroupLabels = GL

local function settings()
    return N.db and N.db.raid and N.db.raid.groupNames
end

local function labelOf(b)
    local fs = b._groupLabel
    if not fs then
        fs = (b.overlay or b):CreateFontString(nil, "OVERLAY")
        fs:SetFont(M.font, 11, "OUTLINE")
        b._groupLabel = fs
    end
    return fs
end

local function style(fs, b, o, group)
    fs:SetFont(M.font, o.size or 11, "OUTLINE")
    local c = o.color or { 1, 1, 1 }
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetText(L["Group %d"]:format(group))
    fs:ClearAllPoints()
    if o.position == "inside" then
        fs:SetPoint("TOPLEFT", b, "TOPLEFT", 2 + (o.x or 0), -2 + (o.y or 0))
    else
        fs:SetPoint("BOTTOMLEFT", b, "TOPLEFT", (o.x or 0), 1 + (o.y or 0))
    end
    fs:Show()
end

-- entries: { { button = b, group = n | nil }, ... } in frame order; the first of each group gets the label.
local function apply(entries)
    local o = settings()
    local on = o and o.enabled and N.db.raid.groupBy == "GROUP"
    local seen = {}
    for _, e in ipairs(entries) do
        local b, g = e.button, e.group
        if on and g and not seen[g] and b:IsShown() then
            seen[g] = true
            style(labelOf(b), b, o, g)
        elseif b._groupLabel then
            b._groupLabel:Hide()
        end
    end
end

function GL.Update()
    local headers = N.RaidHeaders and N.RaidHeaders() or {}
    if #headers == 0 then return end
    local entries = {}
    for _, header in ipairs(headers) do
        local i, child = 1, _G[header:GetName() .. "UnitButton1"]
        while child do
            local group
            local unit = child:GetAttribute("unit")
            local idx = type(unit) == "string" and tonumber(unit:match("^raid(%d+)$"))
            if idx and IsInRaid() then
                local g = select(3, GetRaidRosterInfo(idx))
                if g ~= nil and not IsSecret(g) then group = g end
            end
            entries[#entries + 1] = { button = N.UnitFrame.ButtonOf(child) or child, group = group }
            i = i + 1
            child = _G[header:GetName() .. "UnitButton" .. i]
        end
    end
    apply(entries)
end

function GL.UpdateMock(pool, n)
    local groups = {}
    for g = 1, 8 do
        if not N.RaidGroupAllowed or N.RaidGroupAllowed(g) then groups[#groups + 1] = g end
    end
    local entries = {}
    for i = 1, n do
        local group = groups[math.floor((i - 1) / 5) + 1] or (math.floor((i - 1) / 5) + 1)
        entries[#entries + 1] = { button = pool[i], group = group }
    end
    apply(entries)
end

local function soon()
    C_Timer.After(0.3, GL.Update)
    C_Timer.After(1.5, GL.Update) -- the header assigns its units a moment later
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", soon)

N:On("NUCLEUS_SETTING_CHANGED", function(_, section)
    if section == "raid" then soon() end
end)
