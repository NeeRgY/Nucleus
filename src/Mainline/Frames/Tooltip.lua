local _, ns = ...
local N = ns.N


local TT = {}
N.Tooltip = TT

local function shouldShow()
    if not N.db.tooltip.enabled then return false end
    if N.db.tooltip.hideInCombat and N.InCombat() then return false end
    return true
end

-- Appends the played class's click-casting bindings under the unit tooltip.
local function addBindings()
    local CC = N.ClickCasting
    local list = N.db.clickCasting and N.db.clickCasting.bindings
    if not (CC and CC.ActionText and list) then return end
    local skipBasic = N.db.tooltip.bindingsSkipBasic
    local first = true
    for _, binding in ipairs(list) do
        local plain = binding.kind == "general" or binding.kind == "target" or binding.kind == "focus"
            or binding.kind == "menu" or binding.kind == "assist"
        local action = not (skipBasic and plain) and CC.ActionText(binding) or nil
        if action then
            if first then
                first = false
                GameTooltip:AddLine(" ")
                local accent = N.Media.color.accent
                GameTooltip:AddLine(N.L["Click-Casting"] .. " Nucleus", accent[1], accent[2], accent[3])
            end
            GameTooltip:AddDoubleLine(CC.BindingText(binding), action, 0.70, 0.74, 0.82, 1, 1, 1)
        end
    end
end

function TT.Attach(button)
    local target = button._secure or button -- the secure button gets the mouse
    target:HookScript("OnEnter", function()
        if not button.unit or not shouldShow() then return end
        local where = N.db.tooltip.anchor
        if where == "default" and _G.GameTooltip_SetDefaultAnchor then
            GameTooltip_SetDefaultAnchor(GameTooltip, target)
        elseif where == "cursor" then
            GameTooltip:SetOwner(target, "ANCHOR_CURSOR")
        else
            GameTooltip:SetOwner(target, "ANCHOR_TOPLEFT")
        end
        GameTooltip:SetUnit(button.unit)
        if N.db.tooltip.bindings then addBindings() end
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
