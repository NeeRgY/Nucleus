-- Retail (Mainline) entry point.
-- Establishes the addon namespace and a lightweight event dispatcher so no
-- external library (Ace3, CallbackHandler, ...) is required.

local addonName, ns = ...

ns.CLIENT = "Mainline"
ns.ADDON = addonName
ns.VERSION = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or "1.0.0"

-- Public API table. Modules attach their entry points here.
local N = {}
ns.N = N
_G.Nucleus = N

-- Internal callback registry: event name -> ordered list of handlers.
local handlers = {}

-- Frame that receives every Blizzard event we subscribe to and fans it out.
local dispatcher = CreateFrame("Frame")
dispatcher:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        list[i](event, ...)
    end
end)

-- Register a handler for a Blizzard event. Also used for internal messages
-- (fired via N:Fire), which are never passed to RegisterEvent.
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

-- Fire an internal message. Convention: names are prefixed NUCLEUS_.
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
