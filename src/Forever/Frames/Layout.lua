local _, ns = ...
local N = ns.N
local M = N.Media
local L = N.L

-- Drag overlays for moving the headers. Header positioning itself is in HeaderGroup; this only
-- moves the anchor and saves it.

N.anchors = {}

-- Handle bar above each header, parented to it so a hidden group has no floating handle.
local ANCHOR_TITLES = {
    party = "Party Frames", raid = "Raid Frames",
    ownPet = "Own Pet Frame", groupPets = "Group Pet Frames", npc = "NPC Companion Frames",
    spotlight = "Spotlight Frame",
}

local function makeAnchor(key)
    local header = N.headers[key]
    if not header or N.anchors[key] then return end

    local a = CreateFrame("Button", nil, header)
    a:SetPoint("BOTTOM", header, "TOP", 0, 2)
    a:SetSize(150, 20)
    a:SetFrameStrata("HIGH")
    a:EnableMouse(true)
    a:Hide()
    N.SkinPanel(a, { 0.10, 0.10, 0.10, 0.95 }, M.color.accent)

    local label = N.FontString(a, 11)
    label:SetPoint("CENTER")
    label:SetTextColor(M.color.accentBright[1], M.color.accentBright[2], M.color.accentBright[3])
    label:SetText(L[ANCHOR_TITLES[key]])

    N.OnRecolor(function()
        N.SetPanelBorder(a, M.color.accent)
        label:SetTextColor(M.color.accentBright[1], M.color.accentBright[2], M.color.accentBright[3])
    end)

    a:RegisterForDrag("LeftButton")
    a:SetScript("OnDragStart", function()
        header:SetMovable(true)
        header:StartMoving()
    end)
    a:SetScript("OnDragStop", function()
        header:StopMovingOrSizing()
        local point = N.db[key].point
        local x = N.Round(header:GetLeft())
        local y = N.Round(header:GetTop() - UIParent:GetHeight())
        N.db[key].x, N.db[key].y = x, y
        N.RunWhenSafe(function()
            header:ClearAllPoints()
            header:SetPoint(point, UIParent, point, x, y)
        end)
    end)

    N.anchors[key] = a
    a:SetShown(not N.db.locked)
end
N.Layout_MakeAnchor = makeAnchor

function N.RefreshLock()
    local unlocked = not N.db.locked
    for _, a in pairs(N.anchors) do a:SetShown(unlocked) end
end

function N.ToggleAnchors()
    N.db.locked = not N.db.locked
    N.RefreshLock()
    N:Print(N.db.locked and "frames locked" or "frames unlocked - drag to move")
end

function N.Layout_Init()
    for _, key in ipairs({ "party", "raid", "ownPet", "groupPets", "npc", "spotlight" }) do
        makeAnchor(key)
    end
    N.RefreshLock()
end

N:On("NUCLEUS_SETTING_CHANGED", function(_, _, path)
    if path == "locked" then N.RefreshLock() end
end)
