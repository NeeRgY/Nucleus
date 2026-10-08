local _, ns = ...
local N = ns.N

-- Loads last. Brings the modules up in dependency order once SavedVariables
-- and the world are both ready.

local started = false

local function step(label, fn)
    local ok, err = pcall(fn)
    if not ok then
        N:Print("|cffff5555error in " .. label .. ":|r " .. tostring(err))
    end
end

local function start()
    if started then return end
    started = true

    step("HeaderGroup.Init", N.HeaderGroup.Init)
    step("ClickCasting.Init", N.ClickCasting.Init)
    step("Layout_Init", N.Layout_Init)
    step("HideBlizzard.Init", N.HideBlizzard.Init)
    step("Minimap.Init", N.Minimap.Init)
    step("TestMode.Init", N.TestMode.Init)
    step("Ping.Init", N.Ping.Init)
    step("TargetedSpellBars.Init", N.TargetedSpellBars.Init)

    -- Roster-wide refresh: header handles unit assignment, we just repaint.
    N:On("GROUP_ROSTER_UPDATE", function()
        N.UnitFrame.ForEachButton(function(child)
            if child:IsShown() then N.UnitFrame.FullUpdate(child) end
        end)
    end)

    SLASH_NUCLEUSANCHOR1 = "/nucanchor"
    SlashCmdList.NUCLEUSANCHOR = function() N.ToggleAnchors() end

    SLASH_NUCLEUSTEST1 = "/nuctest"
    SlashCmdList.NUCLEUSTEST = function() N.TestMode.Toggle() end

    SLASH_NUCLEUSDEBUG1 = "/nucdebug"
    SlashCmdList.NUCLEUSDEBUG = function()
        N.ClickCasting.DebugDump()
        N:Print("SecureGroupHeader_Update:", SecureGroupHeader_Update ~= nil,
            "| IsInGroup:", IsInGroup(), "| combat:", InCombatLockdown())
        for key, h in pairs(N.headers) do
            N:Print(("[%s] shown=%s alpha=%.1f size=%dx%d attr(showSolo=%s showPlayer=%s)")
                :format(key, tostring(h:IsShown()), h:GetAlpha() or -1,
                    h:GetWidth() or 0, h:GetHeight() or 0,
                    tostring(h:GetAttribute("showSolo")), tostring(h:GetAttribute("showPlayer"))))
            local c = _G[h:GetName() .. "UnitButton1"]
            if c then
                N:Print(("  child1: shown=%s unit=%s bound=%s size=%dx%d styled=%s")
                    :format(tostring(c:IsShown()), tostring(c:GetAttribute("unit")),
                        tostring(c.unit), c:GetWidth() or 0, c:GetHeight() or 0,
                        tostring(c._nucStyled)))
                if c.unit and UnitExists(c.unit) then
                    local _, classToken = UnitClass(c.unit)
                    local r, g, b = N.ClassRGB(classToken)
                    N:Print(("  child1 class: token=%s secret=%s -> rgb=%.2f/%.2f/%.2f | health color=%.2f/%.2f/%.2f")
                        :format(tostring(classToken), tostring(N.IsSecret(classToken)), r, g, b,
                            c.health:GetStatusBarColor()))
                end
            else
                N:Print("  child1: (none)")
            end
        end
    end

    if N.db.welcomeMessage ~= false then
        N:Print(N.L["WELCOME_MSG"]:format(ns.VERSION or "?"))
    end
end

-- NUCLEUS_DB_READY fires from ADDON_LOADED; PLAYER_LOGIN guarantees the UI and
-- group APIs are available. Whichever is second wins.
local dbReady = false
N:On("NUCLEUS_DB_READY", function()
    dbReady = true
    if IsLoggedIn() then start() end
end)
N:On("PLAYER_LOGIN", function()
    if dbReady then start() end
end)
