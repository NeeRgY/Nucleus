local _, ns = ...
local N = ns.N

-- Secure attributes are written out of combat; *type1 / *type2 stay for unbound clicks.

local CC = {}
N.ClickCasting = CC

local BUTTON_INDEX = { LeftButton = 1, RightButton = 2, MiddleButton = 3, Button4 = 4, Button5 = 5 }

-- Wheel and keys have no button: an override binding clicks "ctrlSCROLLUP" / "KEY:Q".
local WHEEL = { ScrollUp = "SCROLLUP", ScrollDown = "SCROLLDOWN" }
local WHEEL_KEY = { ScrollUp = "MOUSEWHEELUP", ScrollDown = "MOUSEWHEELDOWN" }

local function mouseIndex(button)
    local idx = BUTTON_INDEX[button]
    if idx then return idx end
    local n = tonumber(tostring(button):match("^Button(%d+)$"))
    if n and n >= 1 and n <= 31 then return n end
end

local function keyOf(button)
    return type(button) == "string" and button:match("^KEY:(.+)$") or nil
end

local function hoverName(button)
    return WHEEL[button] or keyOf(button)
end

-- Modifiers use Blizzard's attribute order (alt-, ctrl-, shift-); NormalizeModifier fixes old saves.
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

local function wheelSuffix(mod, button)
    mod = CC.NormalizeModifier(mod)
    return "-" .. (mod == "none" and "" or (mod:gsub("-", ""))) .. hoverName(button)
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
        Button5 = L["Mouse Button 5"], ScrollUp = L["Scroll Up"], ScrollDown = L["Scroll Down"],
    }
    local button = binding and binding.button or "LeftButton"
    local key = keyOf(button)
    local text = names[button]
    if key then
        text = _G["KEY_" .. key] or key
    elseif not text then
        local n = mouseIndex(button)
        text = n and (L["Mouse Button 4"]:gsub("4", tostring(n))) or L["Left Click"]
    end
    parts[#parts + 1] = text
    return table.concat(parts, " + ")
end

-- Attributes a binding needs, or nil. Macro text starts with "/" or "#", else it is a macro name.
local PLAIN_ACTIONS = { target = "target", focus = "focus", menu = "togglemenu", assist = "assist" }

-- Smart res: a macro that resurrects a dead unit, else casts the bound spell.
local RES_SPELLS = {
    PRIEST = { normal = { 2006, 2010, 10880, 10881, 20770, 25435 } },
    PALADIN = { normal = { 7328, 10322, 10324, 20772, 20773, 48949 }, combat = { 391054 } },
    SHAMAN = { normal = { 2008, 20609, 20610, 20776, 20777, 25590 } },
    DRUID = { normal = { 437138, 1237948, 1237949, 1237950, 1237951 },
              combat = { 20484, 20739, 20742, 20747, 20748 } },
    MONK = { normal = { 115178 } }, DEATHKNIGHT = { combat = { 61999 } },
}

local function knownSpellName(ids)
    for _, id in ipairs(ids or {}) do
        if IsPlayerSpell and IsPlayerSpell(id) then
            local name = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
            if not name then
                local info = C_Spell.GetSpellInfo(id)
                name = info and info.name
            end
            if name and name ~= "" then return name end
        end
    end
    -- A rank with another ID than listed: the name still resolves through the spellbook.
    for _, id in ipairs(ids or {}) do
        local name = C_Spell.GetSpellName and C_Spell.GetSpellName(id)
        if name and name ~= "" and C_Spell.GetSpellInfo(name) then return name end
    end
    return nil
end

local function smartMacro(spell)
    local mode = N.db.clickCasting.smartRes
    if mode ~= "normal" and mode ~= "combat" then return nil end
    local _, class = UnitClass("player")
    local res = RES_SPELLS[class]
    if not res then return nil end
    local normal = knownSpellName(res.normal)
    local combat = mode == "combat" and knownSpellName(res.combat) or nil
    if not (normal or combat) then return nil end
    local name = tonumber(spell) and C_Spell.GetSpellName(tonumber(spell)) or spell
    if type(name) ~= "string" or name == "" then return nil end
    local parts = {}
    if normal then parts[#parts + 1] = "[@mouseover,help,dead,nocombat] " .. normal end
    if combat then
        parts[#parts + 1] = (normal and "[@mouseover,help,dead,combat] " or "[@mouseover,help,dead] ") .. combat
    end
    parts[#parts + 1] = "[@mouseover] " .. name
    return "/cast " .. table.concat(parts, "; ")
end

-- Whether the player's class knows a resurrection that works in combat.
function CC.HasCombatRes()
    local _, class = UnitClass("player")
    local res = RES_SPELLS[class]
    return res ~= nil and knownSpellName(res.combat) ~= nil
end

local function attrPairs(binding)
    if not binding or binding.kind == "none" then return nil end
    local idx, prefix
    if hoverName(binding.button) then
        idx, prefix = wheelSuffix(binding.modifier, binding.button), ""
    else
        idx, prefix = mouseIndex(binding.button), modPrefix(binding.modifier)
    end
    if not idx then return nil end
    local typeAttr = prefix .. "type" .. idx

    -- "general" keeps the action in value; the bare kinds are older saves.
    local plain = (binding.kind == "general") and PLAIN_ACTIONS[binding.value]
        or PLAIN_ACTIONS[binding.kind]
    if plain then return typeAttr, plain end
    -- Trinket 1 / 2 follow the equipment slot; a macro, so they also work in combat.
    if binding.kind == "trinket1" or binding.kind == "trinket2" then
        local slot = (binding.kind == "trinket1") and 13 or 14
        return typeAttr, "macro", prefix .. "macrotext" .. idx, "/use [@mouseover,exists,nodead] " .. slot
    end
    if not binding.value or binding.value == "" then return nil end
    if binding.kind == "spell" then
        local spell = binding.value
        if N.db.clickCasting.highestRank and type(spell) == "string" then
            spell = spell:gsub("%s*%b()$", "")
        end
        local smart = smartMacro(spell)
        if smart then return typeAttr, "macro", prefix .. "macrotext" .. idx, smart end
        return typeAttr, "spell", prefix .. "spell" .. idx, spell
    elseif binding.kind == "item" then
        -- Equipped item by slot ("slot:13"): a macro, so it follows swaps and works in combat.
        local slot = tostring(binding.value):match("^slot:(%d+)$")
        if slot then
            return typeAttr, "macro", prefix .. "macrotext" .. idx, "/use [@mouseover,exists,nodead] " .. slot
        end
        return typeAttr, "item", prefix .. "item" .. idx, binding.value
    elseif binding.kind == "macro" then
        local v = binding.value
        if v:match("^[/#]") then
            return typeAttr, "macro", prefix .. "macrotext" .. idx, v
        end
        -- A picked macro runs as its own text; a lookup by name does not always fire.
        local ok, body = pcall(GetMacroBody, v)
        if ok and type(body) == "string" and body ~= "" then
            return typeAttr, "macro", prefix .. "macrotext" .. idx, body
        end
        return typeAttr, "macro", prefix .. "macro" .. idx, v
    end
    return nil
end

-- "target" off plain left click and "togglemenu" only work through a secure proxy (type="click").
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
    if typeAttr:find("^type%-") then return true end
    local mod, num = typeAttr:match("^(.-)type(%d+)$")
    return mod and (mod ~= "" or tonumber(num) ~= 1) or false
end

-- Plain action on typeAttr, through the proxy when the gate needs it.
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

-- Clears every click-cast slot first, so removed or retyped bindings stop firing.
local appliedSlots = setmetatable({}, { __mode = "k" })
local SLOT_ATTRS = { "clickbutton", "type", "spell", "item", "macro", "macrotext" }

function CC.ClearAll(button)
    local slots = appliedSlots[button]
    if slots then
        for _, slot in ipairs(slots) do
            local prefix, idx = slot[1], slot[2]
            for _, a in ipairs(SLOT_ATTRS) do
                button:SetAttribute(prefix .. a .. idx, nil)
            end
            if proxyOf[button] then proxyOf[button]:SetAttribute(prefix .. "type" .. idx, nil) end
        end
        appliedSlots[button] = nil
    end
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
    for _, mod in ipairs(ALL_MODS) do
        for name in pairs(WHEEL) do
            local idx = wheelSuffix(mod, name)
            button:SetAttribute("clickbutton" .. idx, nil)
            if proxyOf[button] then proxyOf[button]:SetAttribute("type" .. idx, nil) end
            button:SetAttribute("type" .. idx, nil)
            button:SetAttribute("spell" .. idx, nil)
            button:SetAttribute("item" .. idx, nil)
            button:SetAttribute("macro" .. idx, nil)
            button:SetAttribute("macrotext" .. idx, nil)
        end
    end
end

-- Wheel bindings use an override binding set from a secure handler (works in combat).
local wheelHandler = CreateFrame("Frame", "NucleusWheelHandler", UIParent, "SecureHandlerBaseTemplate")
local wheelWrapped = setmetatable({}, { __mode = "k" })

local function wheelSnippet(bindings)
    local lines, seen = { "local btn = ..." }, {}
    for _, binding in ipairs(bindings or {}) do
        local key = WHEEL_KEY[binding.button] or keyOf(binding.button)
        if key and binding.kind ~= "none" and attrPairs(binding) then
            local mod = CC.NormalizeModifier(binding.modifier)
            local name = (mod == "none" and "" or (mod:gsub("-", ""))) .. hoverName(binding.button)
            if not seen[name] then
                seen[name] = true
                local full = (mod == "none" and "" or (mod:upper() .. "-")) .. key
                lines[#lines + 1] = ("self:SetBindingClick(true, %q, btn, %q)"):format(full, name)
            end
        end
    end
    return #lines > 1 and table.concat(lines, "\n") or ""
end

local function wrapWheel(button)
    if wheelWrapped[button] or not button:GetName() then return end -- the click target is found by name
    wheelWrapped[button] = true
    pcall(function()
        SecureHandlerWrapScript(button, "OnEnter", wheelHandler, [=[
            owner:ClearBindings()
            local snippet = owner:GetAttribute("wheelsnippet")
            if snippet and snippet ~= "" then owner:Run(snippet, self:GetName()) end
        ]=])
        SecureHandlerWrapScript(button, "OnLeave", wheelHandler, [=[ owner:ClearBindings() ]=])
        SecureHandlerWrapScript(button, "OnHide", wheelHandler, [=[ owner:ClearBindings() ]=])
    end)
end

function CC.Apply(button, bindings)
    local menuOnRight = false
    local slots = {}
    for _, binding in ipairs(bindings or {}) do
        local ta, tv, va, vv = attrPairs(binding)
        if ta then
            slots[#slots + 1] = { ta:match("^(.-)type"), ta:match("type(.*)$") }
            if va then
                button:SetAttribute(ta, tv)
                button:SetAttribute(va, vv)
            else
                setPlainAction(button, ta, tv)
            end
            if ta == "type2" then menuOnRight = true end
        end
    end
    appliedSlots[button] = slots
    -- An unbound right click falls back to the togglemenu wildcard, which the gate blocks: use the proxy.
    if not menuOnRight then setPlainAction(button, "type2", "togglemenu") end
end

-- Bindings are per class: clickCasting.bindings is the played class's list, others live in byClass.
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
        -- Older saves had one shared list: each class starts from it and drops the spells it doesn't know.
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

-- A button is only rewritten when its bindings changed since the last pass.
local appliedSig = setmetatable({}, { __mode = "k" })

local function bindingsSig(bindings, snippet)
    local t = { snippet }
    for _, binding in ipairs(bindings or {}) do
        local ta, tv, va, vv = attrPairs(binding)
        if ta then t[#t + 1] = ta .. "=" .. tostring(tv) .. "," .. tostring(va) .. "=" .. tostring(vv) end
    end
    return table.concat(t, "\n")
end

function CC.ApplyToAll()
    if not N.db or not N.UnitFrame then return end
    N.RunWhenSafe(function()
        local bindings = N.db.clickCasting and N.db.clickCasting.bindings
        local snippet = wheelSnippet(bindings)
        wheelHandler:SetAttribute("wheelsnippet", snippet)
        local sig = bindingsSig(bindings, snippet)
        N.UnitFrame.ForEachButton(function(b)
            local child = b._secure or b -- bindings live on the secure button
            if appliedSig[child] == sig then return end
            appliedSig[child] = sig
            CC.ClearAll(child)
            child:SetAttribute("*type1", "target")
            child:SetAttribute("*type2", "togglemenu")
            CC.Apply(child, bindings)
            if snippet ~= "" then wrapWheel(child) end
        end)
    end, "clickcasting-apply")
end

N:On("NUCLEUS_SETTING_CHANGED", function(_, section)
    if section == "clickCasting" then
        CC.SelectClass() -- the list in use may have changed (a specialization got its own)
        CC.ApplyToAll()
    end
end)

-- A binding on the self-cast key never reaches the frame. Asked once per binding set.
local function selfCastTokens()
    local key = GetModifiedClick and GetModifiedClick("SELFCAST")
    if type(key) ~= "string" or key == "" or key == "NONE" then return nil end
    local need = {}
    for part in key:gmatch("[^-]+") do need[#need + 1] = part:lower() end
    return #need > 0 and need or nil
end

local function selfCastConflicts()
    local need = selfCastTokens()
    if not need then return nil end
    local found = {}
    for _, b in ipairs(N.db.clickCasting.bindings or {}) do
        if (b.kind == "spell" or b.kind == "item" or b.kind == "macro") and b.value and b.value ~= "" then
            local has = {}
            for part in CC.NormalizeModifier(b.modifier):gmatch("[^-]+") do has[part] = true end
            local all = true
            for _, k in ipairs(need) do
                if not has[k] then all = false break end
            end
            if all then found[#found + 1] = tostring(b.modifier) .. "|" .. tostring(b.button) .. "|" .. tostring(b.value) end
        end
    end
    if #found == 0 then return nil end
    table.sort(found)
    return table.concat(need, "-") .. ":" .. table.concat(found, ";"), need
end

local function checkSelfCast()
    if InCombatLockdown() or not (N.db and N.db.clickCasting and SetModifiedClick and N.Dialog) then return end
    local sig, need = selfCastConflicts()
    if not sig or N.db.clickCasting.selfCastDeclined == sig then return end
    local names = {}
    for _, k in ipairs(need) do names[#names + 1] = N.L["SELFCAST_KEY_" .. k] or k end
    N.Dialog.Show({
        title = N.L["Nucleus"],
        text = N.L["SELFCAST_ASK"]:format(table.concat(names, " + ")),
        buttons = {
            { text = N.L["No"], onClick = function() N.db.clickCasting.selfCastDeclined = sig end },
            { text = N.L["Yes"], primary = true, onClick = function()
                local ok = pcall(SetModifiedClick, "SELFCAST", "NONE")
                if ok then pcall(SaveBindings, GetCurrentBindingSet()) end
                N:Print(N.L["SELFCAST_DONE"])
            end },
        },
    })
end

local selfCastPending
local function queueSelfCast(delay)
    if selfCastPending then return end
    selfCastPending = true
    C_Timer.After(delay, function()
        selfCastPending = nil
        checkSelfCast()
    end)
end

N:On("NUCLEUS_SETTING_CHANGED", function(_, section)
    if section == "clickCasting" then queueSelfCast(0.5) end
end)
local selfCastLogin = CreateFrame("Frame")
selfCastLogin:RegisterEvent("PLAYER_ENTERING_WORLD")
selfCastLogin:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    queueSelfCast(6)
end)

-- Bound macros run the text they had when applied: re-apply when a macro is edited.
local macroWatcher = CreateFrame("Frame")
macroWatcher:RegisterEvent("UPDATE_MACROS")
local macroPending
macroWatcher:SetScript("OnEvent", function()
    if macroPending then return end
    macroPending = true
    C_Timer.After(1, function()
        macroPending = false
        CC.ApplyToAll()
    end)
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

-- Re-apply after the header may have rebuilt children (a child made in combat gets bindings later).
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
watcher:SetScript("OnEvent", CC.ApplyToAll)

-- Pick the class's list once the spellbook is readable, and again on a profile switch.
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

-- /nucdebug: what each saved binding resolves to and what the first unit button really has.
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
