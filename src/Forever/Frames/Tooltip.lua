local _, ns = ...
local N = ns.N

-- GameTooltip on mouseover for unit frames. UnitFrame calls Tooltip.Attach per button, this module
-- decides when to show or hide.

local TT = {}
N.Tooltip = TT

local function shouldShow()
    if not N.db.tooltip.enabled then return false end
    if N.db.tooltip.hideInCombat and InCombatLockdown() then return false end
    return true
end

function TT.Attach(button)
    local target = button._secure or button -- the secure button gets the mouse
    target:HookScript("OnEnter", function()
        if not button.unit or not shouldShow() then return end
        GameTooltip:SetOwner(target, "ANCHOR_TOPLEFT")
        GameTooltip:SetUnit(button.unit)
        GameTooltip:Show()
    end)
    target:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:SetScript("OnEvent", function()
    if not (N.db and N.db.tooltip.hideInCombat) then return end
    local owner = GameTooltip:GetOwner()
    if owner and (owner._nucVisual or (N.UnitFrame and N.UnitFrame.VisualOf(owner))) then GameTooltip:Hide() end
end)
