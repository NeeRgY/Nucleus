local _, ns = ...
local N = ns.N

-- GameTooltip for unit frames on mouseover. UnitFrame calls Tooltip.Attach on
-- each button; this module owns the show/hide rules.

local TT = {}
N.Tooltip = TT

local function shouldShow()
    if not N.db.tooltip.enabled then return false end
    if N.db.tooltip.hideInCombat and InCombatLockdown() then return false end
    return true
end

function TT.Attach(button)
    button:HookScript("OnEnter", function(self)
        if not self.unit or not shouldShow() then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:SetUnit(self.unit)
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-- Drop a tooltip we own the moment combat starts if the setting says so.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:SetScript("OnEvent", function()
    if not (N.db and N.db.tooltip.hideInCombat) then return end
    local owner = GameTooltip:GetOwner()
    if owner and owner._nucVisual then GameTooltip:Hide() end
end)
