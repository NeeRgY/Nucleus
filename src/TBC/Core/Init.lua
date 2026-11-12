
local addonName, ns = ...

ns.CLIENT = "TBC"
ns.ADDON = addonName
local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
ns.VERSION = getMeta and getMeta(addonName, "Version") or "1.1.1"

local N = {}
ns.N = N
_G.Nucleus = N

-- Unknown events make RegisterEvent error: register what exists, skip the rest.
function N.SafeRegister(frame, event)
    return pcall(frame.RegisterEvent, frame, event)
end
function N.SafeRegisterUnit(frame, event, unit)
    return pcall(frame.RegisterUnitEvent, frame, event, unit)
end

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
            N.SafeRegister(dispatcher, event)
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
