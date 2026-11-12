
local addonName, ns = ...

ns.CLIENT = "Forever"
ns.ADDON = addonName
ns.VERSION = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or "1.1.0"

local N = {}
ns.N = N
_G.Nucleus = N

local handlers = {}

local dispatcher = CreateFrame("Frame")
dispatcher:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        list[i](event, ...)
    end
end)

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

function N:Fire(message, ...)
    local list = handlers[message]
    if not list then return end
    -- One failing handler is reported but does not stop the others (or the code that fired the message).
    for i = 1, #list do
        local ok, err = pcall(list[i], message, ...)
        if not ok then geterrorhandler()(err) end
    end
end

local PREFIX = "|cff3399ffNucleus|r "

function N:Print(...)
    print(PREFIX .. strjoin(" ", tostringall(...)))
end
