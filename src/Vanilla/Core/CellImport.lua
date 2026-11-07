local _, ns = ...
local N = ns.N


local CI = {}
N.CellImport = CI

local CORNERS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local GROWTH = {
    ["left-to-right"] = "RIGHT", ["right-to-left"] = "LEFT",
    ["top-to-bottom"] = "DOWN", ["bottom-to-top"] = "UP",
}


function CI.Decode(text)
    local LibSerialize = LibStub and LibStub:GetLibrary("LibSerialize", true)
    local LibDeflate = LibStub and LibStub:GetLibrary("LibDeflate", true)
    if not (LibSerialize and LibDeflate) then return false, "IMPORT_ERR_LIBS" end
    text = strtrim(text or "")
    local version, body = text:match("^!CELL:(%d+):ALL!(.+)$")
    if not body then return false, "CELL_BAD" end
    local decoded = LibDeflate:DecodeForPrint(body)
    local inflated = decoded and LibDeflate:DecompressDeflate(decoded)
    if not inflated then return false, "CELL_BAD" end
    local ok, success, data = pcall(function() return LibSerialize:Deserialize(inflated) end)
    if not (ok and success and type(data) == "table") then return false, "CELL_BAD" end
    return true, data, tonumber(version)
end

function CI.Layouts(data)
    local out = {}
    for name in pairs(data.layouts or {}) do out[#out + 1] = name end
    table.sort(out, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
    return out
end


local function num(v) return type(v) == "number" and v or nil end
local function bool(v) if type(v) == "boolean" then return v end return nil end

-- Color in either shape: {r,g,b[,a]} or { "custom_color", {r,g,b[,a]} }.
local function rgb(c)
    if type(c) ~= "table" then return nil end
    if type(c[1]) == "string" then c = c[2] end
    if type(c) ~= "table" or not (num(c[1]) and num(c[2]) and num(c[3])) then return nil end
    return { c[1], c[2], c[3] }, num(c[4])
end

local function ensure(t, ...)
    for i = 1, select("#", ...) do
        local k = select(i, ...)
        if type(t[k]) ~= "table" then t[k] = {} end
        t = t[k]
    end
    return t
end

local function put(t, k, v)
    if v ~= nil then t[k] = v end
end

-- Every size, spacing and offset is scaled by the source's appearance.scale.
local SCALE = 1
local function sc(v)
    if v == nil then return nil end
    return math.floor(v * SCALE + 0.5)
end

local function firstSize(s, unscaled)
    if type(s) ~= "table" then return nil end
    if type(s[1]) == "table" then s = s[1] end
    if unscaled then return num(s[1]), num(s[2]) end
    return sc(num(s[1])), sc(num(s[2]))
end

-- Position {point, relativeTo, relativePoint, x, y} -> point on the frame, x, y.
local function place(pos)
    if type(pos) ~= "table" then return nil end
    local point = (type(pos[3]) == "string" and CORNERS[pos[3]] and pos[3])
        or (type(pos[1]) == "string" and CORNERS[pos[1]] and pos[1]) or nil
    return point, sc(num(pos[4])), sc(num(pos[5]))
end

-- Objects hang on one point only: offset corrected by the point difference times the size.
local function fx(p) return p:find("LEFT") and 0 or p:find("RIGHT") and 1 or 0.5 end
local function fy(p) return p:find("BOTTOM") and 0 or p:find("TOP") and 1 or 0.5 end

local function placeFor(pos, w, h)
    if type(pos) ~= "table" then return nil end
    local own = type(pos[1]) == "string" and CORNERS[pos[1]] and pos[1] or nil
    local rel = (type(pos[3]) == "string" and CORNERS[pos[3]] and pos[3]) or own
    if not rel then return nil end
    local x, y = sc(num(pos[4])), sc(num(pos[5]))
    if own and own ~= rel and x and y then
        x = x + (fx(rel) - fx(own)) * (w or 0)
        y = y + (fy(rel) - fy(own)) * (h or 0)
    end
    if x then x = math.floor(x + 0.5) end
    if y then y = math.floor(y + 0.5) end
    return rel, x, y
end

-- Size of an icon that may be a rectangle (for example 12 x 20): the average, plus width and height.
local function avgSize(s)
    local w, h = firstSize(s)
    if w and h then return math.floor((w + h) / 2 + 0.5), w, h end
    return w or h, w, h
end

-- The icon indicators sit a pixel inside the frame edge; the source offsets are from the edge itself.
local function inset(point)
    local ax = point:find("LEFT") and 1 or point:find("RIGHT") and -1 or 0
    local ay = point:find("TOP") and -1 or point:find("BOTTOM") and 1 or 0
    return ax, ay
end


local function convertAppearance(a, out, report)
    if type(a) ~= "table" then return end
    local ap = ensure(out, "appearance")
    put(ap, "outOfRangeAlpha", num(a.outOfRangeAlpha))

    if type(a.barColor) == "table" then
        local mode = a.barColor[1]
        if mode == "custom_color" then
            local c = rgb(a.barColor)
            if c then ap.healthColorMode, ap.healthCustomColor = "custom", c end
        elseif type(mode) == "string" and (mode:find("threshold") or mode:find("gradient")) then
            ap.healthColorMode = "gradient"
        else
            ap.healthColorMode = "class"
        end
    end
    if type(a.lossColor) == "table" and a.lossColor[1] == "custom_color" then
        local c = rgb(a.lossColor)
        if c then ap.healthLossColor = c end
    end
    local t = rgb(a.targetColor)
    if t then ensure(ap, "targetBorder").color = t end
    local m = rgb(a.mouseoverColor)
    if m then ensure(ap, "hoverBorder").color = m end

    -- { enabled, { r, g, b } }
    if type(a.deathColor) == "table" then
        put(ap, "deadColorEnabled", bool(a.deathColor[1]))
        local c = rgb(a.deathColor[2])
        if c then ap.deadColor = c end
    end
    if a.healthFadeEnabled ~= nil then
        local g = ensure(ap, "healthFade")
        put(g, "enabled", bool(a.healthFadeEnabled))
        put(g, "threshold", num(a.healthFadeThreshold))
    end

    -- Duration text: { normal }, { colour, percent }, { colour, seconds }.
    local o = a.auraIconOptions
    if type(o) == "table" then
        local g = ensure(ap, "timeColor")
        put(g, "enabled", bool(o.durationColorEnabled))
        local last = type(o.durationColors) == "table" and o.durationColors[3]
        if type(last) == "table" then
            local c = rgb(last)
            if c then g.color = c end
            put(g, "seconds", num(last[4]))
        end
        put(g, "decimals", num(o.durationDecimal))
    end
    report.done[#report.done + 1] = "CELLR_APPEARANCE"
end


local ICONS = {
    statusIcon = "statusIcon", roleIcon = "role", leaderIcon = "leader",
    combatIcon = "combatIcon", readyCheckIcon = "readyCheck", playerRaidIcon = "raidMarker",
}
local TEXTS = { nameText = "name", healthText = "healthText", levelText = "levelText" }
local ROWS = {
    externalCooldowns = "externals", defensiveCooldowns = "defensives",
    offensiveCooldowns = "offensives", debuffs = "debuffs", crowdControls = "crowdControls",
}
local NO_MATCH = {
    aggroBlink = true, aggroBar = true, aoeHealing = true,
    allCooldowns = true, tankActiveMitigation = true, raidDebuffs = true,
    targetedSpells = true, targetedSpellBars = true, pingIcon = true, actions = false,
}

local function fontSizes(font)
    if type(font) ~= "table" then return nil end
    if type(font[1]) == "table" then -- aura rows: { duration font, stack font }
        return sc(num(font[1][2])), type(font[2]) == "table" and sc(num(font[2][2])) or nil
    end
    return sc(num(font[2]))
end

local function cdStyle(style, default)
    if style == "vertical" then return "vertical" end
    if style == "clock" or style == "spiral" then return "spiral" end
    return default
end

local function convertRow(ind, row, styleDefault)
    put(row, "enabled", bool(ind.enabled))
    put(row, "max", num(ind.num))
    local w, fw, fh = avgSize(ind.size)
    put(row, "size", w)
    local point, x, y = placeFor(ind.position, fw or w, fh or w)
    put(row, "point", point); put(row, "x", x); put(row, "y", y)
    put(row, "growth", GROWTH[ind.orientation])
    put(row, "showTime", bool(ind.showDuration))
    put(row, "showCooldown", bool(ind.showAnimation))
    put(row, "showStacks", bool(ind.showStack))
    row.cdStyle = cdStyle(ind.animationStyle, styleDefault)
    local ts, ss = fontSizes(ind.font)
    put(row, "timeSize", ts); put(row, "stackSize", ss)
end

local DISPEL_HIGHLIGHT = { fill = "fill", full = "full", none = "none",
    ["edge-top"] = "edge-top", ["edge-bottom"] = "edge-bottom" }

local function convertIndicators(list, out, report, styleDefault)
    local ind = ensure(out, "indicators")
    local auras = ensure(out, "auras")
    local skipped = report.skipped

    for _, e in ipairs(list or {}) do
        if type(e) == "table" and e.type == "built-in" then
            local name = e.indicatorName
            local label = e.name or name
            if TEXTS[name] then
                local o = ensure(ind, TEXTS[name])
                put(o, "enabled", bool(e.enabled))
                local fs = fontSizes(e.font)
                put(o, "size", fs)
                local point, x, y = placeFor(e.position, 0, fs or 10)
                if point and name ~= "levelText" then o.position = point:lower() end
                put(o, "x", x); put(o, "y", y)
                if name == "levelText" then
                    local f = e.levelFormat
                    if f == "full" or f == "short" or f == "number" then o.format = f end
                    local c = rgb(e.color)
                    if c then o.color = c end
                elseif name == "nameText" then
                    local c = rgb(e.color)
                    if c then o.color, o.colorMode = c, "custom" end
                elseif name == "healthText" and type(e.format) == "table" and type(e.format.health1) == "table" then
                    local f = e.format.health1.format
                    if f == "percent" or f == "effective_percent" or f == "health_percent" then o.format = "percent"
                    elseif f == "number" or f == "short" then o.format = "value"
                    elseif f == "none" then o.enabled = false end
                end
            elseif ICONS[name] then
                local o = ensure(ind, ICONS[name])
                put(o, "enabled", bool(e.enabled))
                local size, fw, fh = avgSize(e.size)
                put(o, "size", size)
                local point, x, y = placeFor(e.position, fw or size, fh or size)
                if point then
                    o.position = point:lower()
                    local ax, ay = inset(point)
                    if x then x = x - ax end
                    if y then y = y - ay end
                end
                put(o, "x", x); put(o, "y", y)
                if name == "roleIcon" and e.hideDamager ~= nil then o.showDamager = not e.hideDamager end
                if name == "leaderIcon" then put(o, "hideInCombat", bool(e.hideInCombat)) end
            elseif name == "statusText" then
                local o = ensure(ind, "status")
                put(o, "enabled", bool(e.enabled))
                put(o, "size", fontSizes(e.font))
                put(o, "showTimer", bool(e.showTimer))
                put(o, "showBackground", bool(e.showBackground))
                if type(e.colors) == "table" then
                    local MAP = { OFFLINE = "offline", AFK = "afk", FEIGN = "feignDeath", GHOST = "ghost",
                        DEAD = "dead", DRINKING = "drinking", PENDING = "summonPending",
                        ACCEPTED = "summonAccepted", DECLINED = "summonDeclined" }
                    for cellKey, ours in pairs(MAP) do
                        local col = rgb(e.colors[cellKey])
                        if col then ensure(o, "stateColors")[ours] = col end
                    end
                end
            elseif name == "healthThresholds" then
                local o = ensure(ind, "healthThresholds")
                put(o, "enabled", bool(e.enabled))
                put(o, "thickness", num(e.thickness))
                if type(e.thresholds) == "table" then
                    local list = {}
                    for _, t in ipairs(e.thresholds) do
                        if type(t) == "table" and num(t[1]) and #list < 8 then
                            list[#list + 1] = {
                                pct = math.max(1, math.min(99, math.floor(t[1] * 100 + 0.5))),
                                color = rgb(t[2]) or { 1, 0, 0 },
                            }
                        end
                    end
                    o.thresholds = list
                end
            elseif name == "powerText" then
                local o = ensure(ind, "powerBar")
                if e.enabled == true then o.text = true end
            elseif name == "targetCounter" then
                local o = ensure(ind, "targetCounter")
                put(o, "enabled", bool(e.enabled))
                put(o, "size", fontSizes(e.font))
                local c = rgb(e.color)
                if c then o.color = c end
            elseif name == "aggroBorder" then
                local o = ensure(ind, "aggroBorder")
                put(o, "enabled", bool(e.enabled))
                put(o, "thickness", num(e.thickness))
            elseif name == "missingBuffs" then
                local o = ensure(ind, "missingBuffs")
                put(o, "enabled", bool(e.enabled))
                put(o, "size", (avgSize(e.size)))
                put(o, "growth", (GROWTH[e.orientation] == "LEFT" or GROWTH[e.orientation] == "RIGHT")
                    and GROWTH[e.orientation] or nil)
            elseif ROWS[name] then
                convertRow(e, ensure(auras, ROWS[name]), styleDefault)
                if name == "crowdControls" then
                    put(auras.crowdControls, "dispellableOnly", bool(e.dispellableByMe))
                elseif name == "debuffs" then
                    put(auras.debuffs, "dispelBorder", bool(e.showDispelBorder))
                end
            elseif name == "dispels" then
                local o = ensure(auras, "dispels")
                put(o, "enabled", bool(e.enabled))
                o.typeIcons = true
                local tsize, tw, th = avgSize(e.size)
                put(o, "typeIconSize", tsize)
                local point, x, y = placeFor(e.position, tw or tsize, th or tsize)
                put(o, "typeIconPoint", point); put(o, "typeIconX", x); put(o, "typeIconY", y)
                put(o, "typeIconGrowth", GROWTH[e.orientation])
                if type(e.highlightType) == "table" then
                    local h = DISPEL_HIGHLIGHT[e.highlightType[1]]
                    if h then o.highlightType = h end
                    put(o, "highlightOpacity", num(e.highlightType[2]))
                end
                put(o, "frameBorder", bool(e.showDispelFrameBorder))
                put(o, "frameBorderThickness", num(e.thickness))
            elseif NO_MATCH[name] then
                skipped[#skipped + 1] = label
            end
        end
    end
end

-- The player's own indicators ("icon" / "icons"); other shapes are skipped.
local function convertCustom(list, report)
    local out = {}
    for _, e in ipairs(list or {}) do
        if type(e) == "table" and e.type ~= "built-in" then
            if (e.type == "icon" or e.type == "icons") and N.CustomIndicators then
                local c = N.CustomIndicators.NewEntry(e.type, e.name or e.indicatorName or "Indicator")
                put(c, "enabled", bool(e.enabled))
                c.aura = (e.auraType == "debuff") and "debuff" or "buff"
                c.mine = (e.castBy == "me")
                local ids = {}
                for _, v in ipairs(e.auras or {}) do
                    if type(v) == "number" then ids[#ids + 1] = v end
                end
                if type(e.auras) == "table" and #ids == 0 then
                    -- { spell, ... } pairs are possible too; keep numeric keys.
                    for k, v in pairs(e.auras) do
                        if type(k) == "number" and type(v) == "number" then ids[#ids + 1] = v end
                    end
                end
                c.spells = table.concat(ids, ",")
                local csize, cw, ch = avgSize(e.size)
                put(c, "size", csize)
                local point, x, y = placeFor(e.position, cw or csize, ch or csize)
                put(c, "point", point); put(c, "x", x); put(c, "y", y)
                put(c, "growth", GROWTH[e.orientation])
                put(c, "max", num(e.num))
                put(c, "perRow", num(e.numPerLine))
                if type(e.spacing) == "table" then
                    put(c, "spacing", sc(num(e.spacing[1])))
                    put(c, "lineSpacing", sc(num(e.spacing[2])))
                end
                put(c, "showTime", bool(e.showDuration))
                put(c, "showStacks", bool(e.showStack))
                put(c, "showCooldown", bool(e.showAnimation))
                c.cdStyle = cdStyle(e.animationStyle, "spiral")
                out[#out + 1] = c
            else
                report.skipped[#report.skipped + 1] = (e.name or e.indicatorName or "?") .. " (" .. tostring(e.type) .. ")"
            end
        end
    end
    return out
end


local function convertGroup(layout, out, report, isRaid)
    local main = layout.main
    if type(main) == "table" then
        local w, h = firstSize(main.size)
        put(out, "width", w); put(out, "height", h)
        local o = main.orientation
        if o == "vertical" or o == "horizontal" then out.orientation = o end
        local along, across = sc(num(main.spacingY)), sc(num(main.spacingX))
        if o == "horizontal" then along, across = across, along end
        if along then out.spacing = math.max(0, along) end
        if across then out.columnSpacing = math.max(0, across) end
        put(out, "unitsPerColumn", num(main.unitsPerColumn))
        put(out, "maxColumns", num(main.maxColumns))
        if type(main.anchor) == "string" and CORNERS[main.anchor] then out.point = main.anchor end
        if main.hideSelf ~= nil then out.showPlayer = not main.hideSelf end

        if isRaid then
            if main.combineGroups == true then out.groupBy = "NONE"
            elseif main.combineGroups == false then out.groupBy = "GROUP" end
        end
        -- Role sorting inside groups is replaced by the custom order, so it only applies with combined groups.
        local ord = ensure(out, "ordering")
        if type(main.roleOrder) == "table" then
            ord.first, ord.second, ord.third = main.roleOrder[1], main.roleOrder[2], main.roleOrder[3]
        end
        if main.sortByRole == true and (not isRaid or main.combineGroups == true) then
            ord.enabled = true
        end
    end

    local ps = sc(num(layout.powerSize))
    if ps then
        local pb = ensure(out, "indicators", "powerBar")
        if ps <= 0 then pb.enabled = false else pb.enabled, pb.height = true, ps end
    end
    local gf = layout.groupFilter
    if isRaid and type(gf) == "table" then
        local t = {}
        for g = 1, 8 do t[g] = gf[g] ~= false end
        out.groupFilter = t
    end

    -- Power bar per class and role (class = true for every role, or a role table).
    local pf = layout.powerFilters
    if type(pf) == "table" then
        local filter = {}
        for _, e in ipairs(N.CLASS_ROLES or {}) do
            local v = pf[e[1]]
            if v ~= nil then
                filter[e[1]] = {}
                for _, role in ipairs(e[2]) do
                    filter[e[1]][role] = (v == true) or (type(v) == "table" and v[role] == true)
                end
            end
        end
        if next(filter) then ensure(out, "indicators", "powerBar").filter = filter end
    end
    report.done[#report.done + 1] = "CELLR_LAYOUT"
end

-- Pets and NPC companions: enabled + size (+ attach side for pets).
local function convertSide(layout, profile, report)
    local main = layout.main
    local mw, mh = firstSize(main and main.size)

    local pet = layout.pet
    if type(pet) == "table" then
        local on = (pet.partyEnabled or pet.raidEnabled or pet.soloEnabled) and true or false
        local w, h = mw, mh
        if pet.sameSizeAsMain == false then w, h = firstSize(pet.size) end
        for _, key in ipairs({ "ownPet", "groupPets" }) do
            local g = ensure(profile, key)
            g.enabled = on
            put(g, "width", w); put(g, "height", h)
            if pet.partyDetached == false then g.attachEnabled = true elseif pet.partyDetached == true then g.attachEnabled = false end
            local side = type(pet.petSide) == "string" and pet.petSide:upper()
            if side == "LEFT" or side == "RIGHT" or side == "TOP" or side == "BOTTOM" then g.attachSide = side end
        end
    end
    local npc = layout.npc
    if type(npc) == "table" then
        local g = ensure(profile, "npc")
        g.enabled = npc.enabled and true or false
        local w, h = mw, mh
        if npc.sameSizeAsMain == false then w, h = firstSize(npc.size) end
        put(g, "width", w); put(g, "height", h)
    end
    local spot = layout.spotlight
    if type(spot) == "table" then
        local g = ensure(profile, "spotlight")
        local w, h = mw, mh
        if spot.sameSizeAsMain == false then w, h = firstSize(spot.size) end
        put(g, "width", w); put(g, "height", h)
    end
    report.done[#report.done + 1] = "CELLR_PETS"
end


local BUTTONS = { [1] = "LeftButton", [2] = "RightButton", [3] = "MiddleButton", [4] = "Button4", [5] = "Button5" }
local PLAIN = { target = "target", togglemenu = "menu", focus = "focus", assist = "assist" }

local function spellValue(id)
    local name = N.Compat.Spell and N.Compat.Spell.GetSpellName and N.Compat.Spell.GetSpellName(id)
    return name or tostring(id)
end

local function convertBinding(entry)
    local key, action, value = entry[1], entry[2], entry[3]
    if type(key) ~= "string" then return nil end
    local mods, idx = key:match("^(.-)%-?type(%d)$")
    idx = tonumber(idx)
    local button = idx and (BUTTONS[idx] or (idx >= 6 and idx <= 31 and ("Button" .. idx)) or nil)
    if not button then
        local wm, dir = key:match("^(.-)%-?type%-SCROLL(%u+)$")
        if wm and (dir == "UP" or dir == "DOWN") then
            mods, button = wm, (dir == "UP") and "ScrollUp" or "ScrollDown"
        end
    end
    if not button then return nil end
    local mod = (mods and mods ~= "") and mods:gsub("%-$", "") or "none"
    local b = { modifier = mod, button = button }
    if PLAIN[action] then
        b.kind, b.value = "general", PLAIN[action]
    elseif action == "spell" and num(value) then
        b.kind, b.value = "spell", spellValue(value)
    elseif action == "spell" and type(value) == "string" and value ~= "" then
        b.kind, b.value = "spell", value
    elseif action == "macro" and type(value) == "string" and value ~= "" then
        b.kind, b.value = "macro", value
    elseif action == "item" and (type(value) == "string" or num(value)) then
        b.kind, b.value = "item", tostring(value)
    else
        return nil
    end
    return b
end

local function convertBindingList(list, dropped)
    local out, seen = {}, {}
    for _, entry in ipairs(list) do
        local b = type(entry) == "table" and convertBinding(entry)
        if b then
            local id = b.modifier .. "/" .. b.button
            if not seen[id] then seen[id] = true; out[#out + 1] = b end
        elseif type(entry) == "table" and entry[1] ~= "notBound" then
            dropped.n = dropped.n + 1
        end
    end
    return out
end

local function convertClickCasting(cc, profile, report)
    if type(cc) ~= "table" then return end
    local byClass, bySpec, count, dropped = {}, {}, 0, { n = 0 }
    for class, spec in pairs(cc) do
        if type(class) == "string" and type(spec) == "table" then
            local ids = {}
            for k, v in pairs(spec) do
                if type(k) == "number" and type(v) == "table" then ids[#ids + 1] = k end
            end
            table.sort(ids)
            -- "common" when one list serves every specialization, else the first specialization's.
            local list = spec.useCommon and spec.common
            if type(list) ~= "table" then list = ids[1] and spec[ids[1]] or spec.common end
            if type(list) == "table" then
                local out = convertBindingList(list, dropped)
                if #out > 0 then byClass[class] = out; count = count + #out end
            end
            -- A list per specialization unless "common" is on, same here.
            if not spec.useCommon then
                for _, id in ipairs(ids) do
                    local out = convertBindingList(spec[id], dropped)
                    if #out > 0 then bySpec[id] = out end
                end
            end
        end
    end
    if next(byClass) then
        local c = ensure(profile, "clickCasting")
        c.byClass = byClass
        if next(bySpec) then
            bySpec._list = true
            c.bySpec = bySpec
        end
        c.migrated = true
        report.ccCount, report.ccDropped = count, dropped.n
        report.done[#report.done + 1] = "CELLR_CLICK"
    end
end
-- spell lists (externals / defensives the player switched off)

local function convertDisabled(cell, key, rowKey, profile)
    local disabled = cell and cell[key] and cell[key].disabled
    if type(disabled) ~= "table" or not next(disabled) then return end
    local defaults = N.Defaults and N.Defaults.party and N.Defaults.party.auras
    local row = defaults and defaults[rowKey]
    if not (row and row.list) then return end
    local keep = {}
    for tok in row.list:gmatch("%d+") do
        if not disabled[tonumber(tok)] then keep[#keep + 1] = tok end
    end
    for _, grp in ipairs({ "party", "raid" }) do
        ensure(profile, grp, "auras", rowKey).list = table.concat(keep, ",")
    end
end


local function indicatorsOf(layout, name)
    for _, e in ipairs(layout and layout.indicators or {}) do
        if type(e) == "table" and e.indicatorName == name then return e end
    end
end

function CI.Convert(data, partyLayout, raidLayout)
    local report = { done = {}, skipped = {} }
    local profile = {}
    SCALE = (data.appearance and num(data.appearance.scale)) or 1
    if SCALE <= 0 then SCALE = 1 end
    local layouts = data.layouts or {}
    local party, raid = layouts[partyLayout], layouts[raidLayout]

    local style = (data.appearance and data.appearance.cooldownStyle == "VERTICAL") and "vertical" or "spiral"

    for key, layout in pairs({ party = party, raid = raid }) do
        local g = ensure(profile, key)
        convertAppearance(data.appearance, g, { done = {}, skipped = {} })
        convertGroup(layout, g, { done = {}, skipped = {} }, key == "raid")
        local sub = { done = {}, skipped = {} }
        convertIndicators(layout.indicators, g, key == "raid" and report or sub, style)
        g.customIndicators = convertCustom(layout.indicators, key == "raid" and report or sub)
        if #g.customIndicators == 0 then g.customIndicators = nil end
        if data.general then
            if key == "party" then put(g, "hideBlizzard", bool(data.general.hideBlizzardParty))
            else put(g, "hideBlizzard", bool(data.general.hideBlizzardRaid)) end
        end
    end
    report.done[#report.done + 1] = "CELLR_APPEARANCE"
    report.done[#report.done + 1] = "CELLR_LAYOUT"
    report.done[#report.done + 1] = "CELLR_INDICATORS"

    if party then convertSide(party, profile, report) end

    local g = data.general
    if type(g) == "table" then
        local t = ensure(profile, "tooltip")
        put(t, "enabled", bool(g.enableTooltips))
        put(t, "hideInCombat", bool(g.hideTooltipsInCombat))
    end

    convertClickCasting(data.clickCastings, profile, report)
    convertDisabled(data, "externals", "externals", profile)
    convertDisabled(data, "defensives", "defensives", profile)

    -- Actions and Targeted Spell Bars are global in Nucleus: taken from the raid layout.
    local ref = raid or party
    local act = indicatorsOf(ref, "actions")
    if act then
        local o = ensure(profile, "actions")
        put(o, "enabled", bool(act.enabled)); put(o, "speed", num(act.speed))
    end
    return profile, report
end
