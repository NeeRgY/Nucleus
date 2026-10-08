local _, ns = ...
local N = ns.N

-- Standalone minimap button (no LibDBIcon).

local MB = {}
N.Minimap = MB

local button

-- Degrees from a delta vector: WoW's Atan2 (degrees) or a Lua fallback.
local function angleOf(dy, dx)
    if _G.Atan2 then return _G.Atan2(dy, dx) end
    return math.deg(math.atan2(dy, dx))
end

local function updatePosition()
    if not button then return end
    local angle = math.rad(N.db.minimap.angle or 205)
    -- Sits on the minimap edge: half its width plus a few pixels (the minimap isn't always 140
    -- wide).
    local half = (Minimap:GetWidth() or 140) / 2
    local r = half + 5
    local x, y = r * math.cos(angle), r * math.sin(angle)
    local shape = _G.GetMinimapShape and _G.GetMinimapShape() or "ROUND"
    if shape == "SQUARE" then
        x = math.max(-r, math.min(r, x * 1.4143))
        y = math.max(-r, math.min(r, y * 1.4143))
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function create()
    button = CreateFrame("Button", "NucleusMinimapButton", Minimap)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetSize(31, 31)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    -- The logo is already a round badge, so it needs no Blizzard border.
    button:SetSize(32, 32)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(N.Media.tex.logo)

    local hl = button:CreateTexture(nil, "HIGHLIGHT")
    hl:SetSize(46, 46)
    hl:SetPoint("CENTER")
    hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    hl:SetBlendMode("ADD")

    button:SetScript("OnClick", function() N.ToggleOptions() end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Nucleus")
        GameTooltip:AddLine("|cffbbbbbbClick:|r Options", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local function cursorAngle()
        local cx, cy = Minimap:GetCenter()
        local curX, curY = GetCursorPosition()
        local s = Minimap:GetEffectiveScale()
        return angleOf(curY / s - cy, curX / s - cx) % 360
    end

    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            N.db.minimap.angle = cursorAngle()
            updatePosition()
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    updatePosition()
end

function MB.Refresh()
    if not button then return end
    button:SetShown(not N.db.minimap.hide)
    updatePosition()
end

function MB.Init()
    create()
    MB.Refresh()
    N:On("NUCLEUS_SETTING_CHANGED", function(_, _, path)
        if path == "minimap.hide" then MB.Refresh() end
    end)
end
