local _, ns = ...
local N = ns.N


local MB = {}
N.Minimap = MB

local button

local function angleOf(dy, dx)
    if _G.Atan2 then return _G.Atan2(dy, dx) end
    return math.deg(math.atan2(dy, dx))
end

local function updatePosition()
    if not button then return end
    local angle = math.rad(N.db.minimap.angle or 205)
    -- On the minimap edge: half its width plus a few pixels (the minimap isn't always 140 wide).
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

local DBI_NAME = "Nucleus"
local useLib

local function createLib()
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    local DBI = LibStub and LibStub("LibDBIcon-1.0", true)
    if not (LDB and DBI) then return false end
    local db = N.db.minimap
    if not db.minimapPos then db.minimapPos = db.angle or 205 end
    local obj = LDB:GetDataObjectByName(DBI_NAME) or LDB:NewDataObject(DBI_NAME, {
        type = "launcher",
        text = "Nucleus",
        icon = N.Media.tex.logo,
        OnClick = function() N.ToggleOptions() end,
        OnTooltipShow = function(tt)
            tt:AddLine("Nucleus")
            tt:AddLine("|cffbbbbbbClick:|r Options", 1, 1, 1)
        end,
    })
    if not DBI:IsRegistered(DBI_NAME) then DBI:Register(DBI_NAME, obj, db) end
    return true
end

function MB.Refresh()
    if useLib then
        local DBI = LibStub("LibDBIcon-1.0", true)
        if N.db.minimap.hide then DBI:Hide(DBI_NAME) else DBI:Show(DBI_NAME) end
        return
    end
    if not button then return end
    button:SetShown(not N.db.minimap.hide)
    updatePosition()
end

function MB.Init()
    useLib = createLib()
    if not useLib then create() end
    MB.Refresh()
    N:On("NUCLEUS_SETTING_CHANGED", function(_, _, path)
        if path == "minimap.hide" then MB.Refresh() end
    end)
end
