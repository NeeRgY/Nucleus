local _, ns = ...
local N = ns.N
local M = N.Media
local L = N.L


N.anchors = {}

-- Handle on UIParent so a group that isn't shown (raid while solo) can still be moved.
local ANCHOR_TITLES = {
    party = "Party Frames", raid = "Raid Frames",
    ownPet = "Own Pet Frame", groupPets = "Group Pet Frames", npc = "NPC Companion Frames",
    spotlight = "Spotlight Frame",
}

function N.StyleMover(a, label, text, target)
    local scale = ((N.db and N.db.moverSize) or 100) / 100
    local bar = N.db and N.db.moverStyle == "bar"
    a._moverText = text .. ((N.db and N.db.moverMode == "alt") and " [ALT]" or "")
    a:ClearAllPoints()
    local ox, oy = (N.db and N.db.moverX) or 0, 2 + ((N.db and N.db.moverY) or 0)
    if bar then
        label:Hide()
        a:SetPoint("BOTTOM", target, "TOP", ox, oy)
        a:SetSize(math.max(10, (N.db and N.db.moverBarWidth) or 100), math.max(3, math.floor(6 * scale + 0.5)))
        if a._nucFill then a._nucFill:SetColorTexture(M.color.accent[1], M.color.accent[2], M.color.accent[3], 0.9) end
    else
        label:Show()
        label:SetFont(M.font, math.max(6, math.floor(10 * scale + 0.5)), "OUTLINE")
        label:SetText(a._moverText)
        a:SetPoint("BOTTOM", target, "TOP", ox, oy)
        a:SetSize(math.max(24, math.floor(label:GetStringWidth() + 14 * scale)), math.floor(15 * scale + 0.5))
        if a._nucFill then a._nucFill:SetColorTexture(0.10, 0.10, 0.10, 0.95) end
    end
end

function N.MoverWanted(key)
    if N.IsHosted and N.IsHosted(key) then return false end
    local mode = N.db and N.db.editMode or "party"
    if N.PET_KEYS[key] then return N.PET_KEYS[mode] == true end
    return key == mode
end

function N.MoverMayDrag()
    return not (N.db and N.db.moverMode == "alt") or IsAltKeyDown()
end

local function pointXY(f, point)
    local l, b, w, h = f:GetLeft(), f:GetBottom(), f:GetWidth(), f:GetHeight()
    local x = point:find("LEFT") and l or point:find("RIGHT") and l + w or l + w / 2
    local y = point:find("BOTTOM") and b or point:find("TOP") and b + h or b + h / 2
    return x, y
end

N.PointXY = pointXY

local function inTestMode()
    return N.TestMode and N.TestMode.IsActive and N.TestMode.IsActive() or false
end

local function makeAnchor(key)
    local header = N.headers[key]
    if not header or N.anchors[key] then return end

    local a = CreateFrame("Button", nil, UIParent)
    a:SetFrameStrata("HIGH")
    a:EnableMouse(true)
    a:Hide()
    N.SkinPanel(a, { 0.10, 0.10, 0.10, 0.95 }, M.color.accent)

    local label = N.FontString(a, 10)
    label:SetPoint("CENTER")
    label:SetTextColor(M.color.accentBright[1], M.color.accentBright[2], M.color.accentBright[3])
    local function restyle() N.StyleMover(a, label, L[ANCHOR_TITLES[key]], header) end
    a._restyle = restyle
    restyle()

    N.OnRecolor(function()
        N.SetPanelBorder(a, M.color.accent)
        label:SetTextColor(M.color.accentBright[1], M.color.accentBright[2], M.color.accentBright[3])
        restyle()
    end)

    -- Party/raid headers are protected: they hang on a plain frame that can move in combat.
    local function mover() return N.HeaderPosFrame and N.HeaderPosFrame(key) or header end

    a:RegisterForDrag("LeftButton")
    a:SetScript("OnDragStart", function()
        if not N.MoverMayDrag() then return end
        local m = mover()
        m:SetMovable(true)
        m:StartMoving()
        a._moving = m
    end)
    a:SetScript("OnDragStop", function()
        local m = a._moving
        if not m then return end
        a._moving = nil
        m:StopMovingOrSizing()
        local point = N.db[key].point
        local mx, my = pointXY(m, point)
        local ux, uy = pointXY(UIParent, point)
        local x, y = N.Round(mx - ux), N.Round(my - uy)
        N.db[key].x, N.db[key].y = x, y
        N:Fire("NUCLEUS_FRAME_MOVED", key)
        if m ~= header then
            m:ClearAllPoints()
            m:SetPoint(point, UIParent, point, x, y)
        else
            N.RunWhenSafe(function()
                header:ClearAllPoints()
                header:SetPoint(point, UIParent, point, x, y)
            end)
        end
    end)

    N.anchors[key] = a
    a:SetShown(not N.db.locked and not inTestMode() and N.MoverWanted(key))
end
N.Layout_MakeAnchor = makeAnchor

function N.RefreshLock()
    local unlocked = not N.db.locked and not inTestMode()
    for key, a in pairs(N.anchors) do
        a:SetShown(unlocked and N.MoverWanted(key))
        if a._restyle then a._restyle() end
    end
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
    if path == "locked" or path == "moverMode" or path == "moverSize" or path == "moverStyle"
        or path == "moverBarWidth" or path == "moverX" or path == "moverY" then
        N.RefreshLock()
    end
end)

N:On("NUCLEUS_EDIT_MODE", function() N.RefreshLock() end)
N:On("NUCLEUS_TEST_MODE", function() N.RefreshLock() end)
