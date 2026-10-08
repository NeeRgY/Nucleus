-- Forever (Camelot) entry point. Sets up the namespace and a small event dispatcher, no external
-- libraries needed. Starts as a copy of the Retail code, which runs on the same API there.

local addonName, ns = ...

ns.CLIENT = "Forever"
ns.ADDON = addonName
ns.VERSION = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or "1.0.0"

local N = {}
ns.N = N
_G.Nucleus = N

-- event name -> list of handlers
local handlers = {}

local dispatcher = CreateFrame("Frame")
dispatcher:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        list[i](event, ...)
    end
end)

-- Registers a handler for a game event or an internal message (see N:Fire).
function N:On(event, fn)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
        if not event:find("^NUCLEUS_") then
            dispatcher:RegisterEvent(event)
        end
    end
    list[#list + 1] = fn
end

-- Internal messages are prefixed NUCLEUS_.
function N:Fire(message, ...)
    local list = handlers[message]
    if not list then return end
    for i = 1, #list do
        list[i](message, ...)
    end
end

local PREFIX = "|cff3399ffNucleus|r "

function N:Print(...)
    print(PREFIX .. strjoin(" ", tostringall(...)))
end
