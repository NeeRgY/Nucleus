local _, ns = ...
local N = ns.N

-- Modifier+click -> spell/item/macro straight from a unit frame. Secure attributes only, written
-- out of combat via N.RunWhenSafe.
--
-- The header's initialConfigFunction sets the wildcards *type1 ("target") and *type2
-- ("togglemenu"). Click-casting sets the modifier-prefixed ones (shift-type1, ...), which only
-- override the combos that have a binding; every other click keeps the default.

local CC = {}
N.ClickCasting = CC

local BUTTON_INDEX = { LeftButton = 1, RightButton = 2, MiddleButton = 3, Button4 = 4, Button5 = 5 }

-- Modifier combos are stored in Blizzard's attribute order, "alt-", then "ctrl-", then "shift-",
-- because SecureButton_GetModifierPrefix builds the prefix in exactly that order; a binding
-- written "shift-ctrl-" would never match. Older saves used other orders, so everything goes
-- through NormalizeModifier first.
local ALL_MODS = {
    "none", "alt", "ctrl", "shift", "alt-ctrl", "alt-shift", "ctrl-shift", "alt-ctrl-shift",
}

function CC.NormalizeModifier(mod)
    if not mod or mod == "none" or mod == "" then return "none" end
    local has = {}
    for part in tostring(mod):gmatch("[^-]+") do has[part] = true end
    local out = {}
    for _, key in ipairs({ "alt", "ctrl", "shift" }) do
        if has[key] then out[#out + 1] = key end
    end
    return #out > 0 and table.concat(out, "-") or "none"
end

local function modPrefix(mod)
    mod = CC.NormalizeModifier(mod)
    return mod == "none" and "" or (mod .. "-")
end

function CC.CurrentModifier()
    local out = {}
    if IsAltKeyDown() then out[#out + 1] = "alt" end
    if IsControlKeyDown() then out[#out + 1] = "ctrl" end
    if IsShiftKeyDown() then out[#out + 1] = "shift" end
    return #out > 0 and table.concat(out, "-") or "none"
end

function CC.BindingText(binding)
    local L = N.L
    local mod = CC.NormalizeModifier(binding and binding.modifier)
    local parts = {}
    if mod ~= "none" then
        for key in mod:gmatch("[^-]+") do
            parts[#parts + 1] = key:sub(1, 1):upper() .. key:sub(2)
        end
    end
    local names = {
        LeftButton = L["Left Click"], RightButton = L["Right Click"],
        MiddleButton = L["Middle Click"], Button4 = L["Mouse Button 4"],
        Button5 = L["Mouse Button 5"],
    }
    parts[#parts + 1] = names[binding and binding.button or "LeftButton"] or L["Left Click"]
    return table.concat(parts, " + ")
end

-- Returns the four attribute name/value pairs a binding needs, or nil for an empty/invalid one. A
-- macro value starting with "/" or "#" is macro TEXT (older saves); anything else is the NAME of
-- one of the player's macros, run through the secure "macro" attribute. Kinds without a value: the
-- secure action type alone is the whole binding.
local PLAIN_ACTIONS = { target = "target", focus = "focus", menu = "togglemenu", assist = "assist" }

local function attrPairs(binding)
    if not binding or binding.kind == "none" then return nil end
    local idx = BUTTON_INDEX[binding.button]
    if not idx then return nil end
    local prefix = modPrefix(binding.modifier)
    local typeAttr = prefix .. "type" .. idx

    -- "general" keeps the action in value; the bare kinds are what an earlier build of the options
    -- window saved.
    local plain = (binding.kind == "general") and PLAIN_ACTIONS[binding.value]
        or PLAIN_ACTIONS[binding.kind]
    if plain then return typeAttr, plain end
    if not binding.value or binding.value == "" then return nil end
    if binding.kind == "spell" then
        return typeAttr, "spell", prefix .. "spell" .. idx, binding.value
    elseif binding.kind == "item" then
        return typeAttr, "item", prefix .. "item" .. idx, binding.value
    elseif binding.kind == "macro" then
        local v = binding.value
        if v:match("^[/#]") then
            return typeAttr, "macro", prefix .. "macrotext" .. idx, v
        end
        return typeAttr, "macro", prefix .. "macro" .. idx, v
    end
    return nil
end

-- Blizzard's click-binding gate: "target" with a modifier or on any button but plain left click,
-- and "togglemenu" on every button, only work through a secure action button of their own. A frame
-- with type="click" forwards the click to such a proxy (clickbutton attribute), which runs the
-- real action.
local proxyOf = setmetatable({}, { __mode = "k" }) -- kept off the secure frame
local function clickProxy(button)
    local have = proxyOf[button]
    if have or InCombatLockdown() then return have end -- a secure frame cannot be made in combat
    have = CreateFrame("Button", nil, button, "SecureActionButtonTemplate")
    -- It takes the unit from the frame it hangs on and fires on release, never by mouse itself.
    have:SetAttribute("useOnKeyDown", false)
    have:SetAttribute("useparent-unit", true)
    have:RegisterForClicks("AnyDown", "AnyUp")
    have:EnableMouse(false)
    proxyOf[button] = have
    return have
end

local function isGated(typeAttr, action)
    if action == "togglemenu" then return true end
    if action ~= "target" then return false end
    local mod, num = typeAttr:match("^(.-)type(%d+)$")
    return mod and (mod ~= "" or tonumber(num) ~= 1) or false
end

-- Sets typeAttr (e.g. "shift-type1") to a plain action, through the proxy when the
-- gate needs it.
local function setPlainAction(button, typeAttr, action)
    if isGated(typeAttr, action) then
        local proxy = clickProxy(button)
        if proxy then
            button:SetAttribute(typeAttr, "click")
            button:SetAttribute((typeAttr:gsub("type", "clickbutton")), proxy)
            proxy:SetAttribute(typeAttr, action)
            return
        end
    end
    button:SetAttribute(typeAttr, action)
end

-- Clears every click-cast attribute slot before reapplying, so a removed or retyped binding stops
-- firing.
function CC.ClearAll(button)
    for _, mod in ipairs(ALL_MODS) do
        local prefix = modPrefix(mod)
        for _, idx in pairs(BUTTON_INDEX) do
            button:SetAttribute(prefix .. "clickbutton" .. idx, nil)
            if proxyOf[button] then proxyOf[button]:SetAttribute(prefix .. "type" .. idx, nil) end
            button:SetAttribute(prefix .. "type" .. idx, nil)
            button:SetAttribute(prefix .. "spell" .. idx, nil)
            button:SetAttribute(prefix .. "item" .. idx, nil)
            button:SetAttribute(prefix .. "macro" .. idx, nil)
            button:SetAttribute(prefix .. "macrotext" .. idx, nil)
        end
    end
end

function CC.Apply(button, bindings)
    local menuOnRight = false
    for _, binding in ipairs(bindings or {}) do
        local ta, tv, va, vv = attrPairs(binding)
        if ta then
            if va then
                button:SetAttribute(ta, tv)
                button:SetAttribute(va, vv)
            else
                setPlainAction(button, ta, tv)
            end
            if ta == "type2" then menuOnRight = true end
        end
    end
    -- A plain right click without a binding falls back to the header's togglemenu wildcard, which
    -- the gate blocks the same way, so route it through the proxy too.
    if not menuOnRight then setPlainAction(button, "type2", "togglemenu") end
end

-- Bindings are per class. clickCasting.bindings always points at the list of the class being
-- played (so the rest of the code and the options page work on it); the others live in
-- clickCasting.byClass.
local function knownSpell(value)
    if value == nil or value == "" then return false end
    -- Forever: "Name(Rank N)" - look the spell up by its name.
    if type(value) == "string" then value = value:gsub("%b()", "") end
    local ok, info = pcall(C_Spell.GetSpellInfo, value)
    return ok and info ~= nil
end

function CC.SelectClass()
    local cc = N.db and N.db.clickCasting
    local _, class = UnitClass("player")
    if not (cc and cc.byClass and class and cc.byClass[class]) then return end
    if not cc.migrated then
        -- Older saves had one shared list: every class starts from it, and the current class drops
        -- the spells it doesn't know.
        for c in pairs(cc.byClass) do cc.byClass[c] = N.DeepCopy(cc.bindings) end
        local mine = cc.byClass[class]
        for i = #mine, 1, -1 do
            if mine[i].kind == "spell" and not knownSpell(mine[i].value) then table.remove(mine, i) end
        end
        cc.migrated = true
    end
    local specID = N.Profiles and N.Profiles.GetSpec and N.Profiles.GetSpec()
    local own = specID and type(cc.bySpec) == "table" and cc.bySpec[specID]
    cc.bindings = (type(own) == "table" and own) or cc.byClass[class]
end

function CC.ApplyToAll()
    if not N.db or not N.UnitFrame then return end
    N.RunWhenSafe(function()
        N.UnitFrame.ForEachButton(function(b)
            local child = b._secure or b -- bindings live on the secure button
            CC.ClearAll(child)
            child:SetAttribute("*type1", "target")
            child:SetAttribute("*type2", "togglemenu")
            CC.Apply(child, N.db.clickCasting and N.db.clickCasting.bindings)
        end)
    end, "clickcasting-apply")
end

N:On("NUCLEUS_SETTING_CHANGED", function(_, section)
    if section == "clickCasting" then
        CC.SelectClass() -- the list in use may have changed (a specialization got its own)
        CC.ApplyToAll()
    end
end)

local specWatcher = CreateFrame("Frame")
specWatcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
specWatcher:SetScript("OnEvent", function(_, _, unit)
    if unit and unit ~= "player" then return end
    C_Timer.After(0.5, function()
        CC.SelectClass()
        CC.ApplyToAll()
    end)
end)

-- Re-apply whenever the header may have (re)built children, same cadence as HeaderGroup's
-- re-style, so a child created in combat gets its bindings once combat ends.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", CC.ApplyToAll)

-- Pick the class's list once the spellbook is readable (a hidden spellbook would make every spell
-- look unknown), then again on a profile switch.
local selectTries = 0
local function trySelect()
    if IsPlayerSpell and IsPlayerSpell(6603) or selectTries >= 6 then -- 6603: Auto Attack
        if IsPlayerSpell and IsPlayerSpell(6603) then
            CC.SelectClass()
            CC.ApplyToAll()
        end
    else
        selectTries = selectTries + 1
        C_Timer.After(2, trySelect)
    end
end
local selector = CreateFrame("Frame")
selector:RegisterEvent("PLAYER_ENTERING_WORLD")
selector:SetScript("OnEvent", function() C_Timer.After(1, trySelect) end)

N:On("NUCLEUS_PROFILE_CHANGED", function()
    CC.SelectClass()
    CC.ApplyToAll()
end)

function CC.Init()
    CC.ApplyToAll()
end

-- /nucdebug helper: what each saved binding resolves to, and what is actually
-- on the first unit button (the real secure attributes).
function CC.DebugDump()
    local cc = N.db and N.db.clickCasting
    if not cc then return end
    N:Print("click-cast: bindings =", #cc.bindings)
    local btn
    N.UnitFrame.ForEachButton(function(child) btn = btn or child._secure or child end)
    for i, b in ipairs(cc.bindings) do
        local ta, tv, va, vv = attrPairs(b)
        local live = ta and btn and btn:GetAttribute(ta) or nil
        N:Print(("  #%d mod=%s btn=%s kind=%s value=%s -> %s=%s %s=%s | on button: %s")
            :format(i, tostring(b.modifier), tostring(b.button), tostring(b.kind),
                tostring(b.value), tostring(ta), tostring(tv), tostring(va), tostring(vv),
                tostring(live)))
    end
end
