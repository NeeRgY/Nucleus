local _, ns = ...
local N = ns.N
local M = N.Media
local L = N.L

local function uc(c) return c[1], c[2], c[3], c[4] or 1 end

-- A plain skinned button with centered text, for one-off actions (open a popup, add/remove a row)
-- that don't fit the label/control row pattern of the other widgets.
local function ActionButton(parent, label, onClick)
    local b = CreateFrame("Button", nil, parent)
    b._rowHeight = 28
    N.SkinButton(b)
    local fs = N.FontString(b, 12)
    fs:SetPoint("CENTER")
    fs:SetText(label)
    b:SetScript("OnClick", onClick)
    return b
end

-- Window chrome: header (title, version badge, close), a segmented tab strip under it, a rounded
-- left rail for tabs with sub-pages, and a bottom mode bar, all on one rounded, shadowed surface.
local HEADER  = 42
local TAB_H   = 32
local BODY_TOP = HEADER + TAB_H + 12
local MODEBAR = 44
local RAIL_W  = 200
local WIN_W   = 700
local WIN_H   = 660
-- Content width for the two layouts: rail tabs (left list + content) vs flow tabs (no rail, titled
-- sections stacked full width).
local RAIL_CW = WIN_W - RAIL_W - 30
local FLOW_CW = WIN_W - 32
local CONTENT_W = FLOW_CW
N.CONTENT_WIDTH = FLOW_CW
local vHair

local window, scroll, scrollChild, subnavHost, railScroll, railChild, modeLabel
local topTabButtons = {}
local subNavPool = {}
local modeButtons = {}
local panelCache = {}
local activeTab, activeSub
local lastSubOf = {}
local statsText, statsTicker

-- Panel builders. Each takes a panel frame (+ mode, for per-mode panels) and stacks cards into it.

local function NewPanel(twoCol)
    local p = CreateFrame("Frame", nil, scrollChild)
    p:SetPoint("TOPLEFT")
    p:SetPoint("TOPRIGHT")
    p:Hide()

    if twoCol then
        local colW = math.floor((N.CONTENT_WIDTH - 14) / 2)
        p._cardW = colW
        p._colY = { -4, -4 }
        function p:AddCard(card)
            local i = (self._colY[1] >= self._colY[2]) and 1 or 2
            card:SetParent(self)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", self, "TOPLEFT", (i == 1) and 2 or (colW + 12), self._colY[i])
            self._colY[i] = self._colY[i] - card:GetHeight() - 14
            self:SetHeight(math.max(-self._colY[1], -self._colY[2]) + 10)
        end
    else
        p._cardW = N.CONTENT_WIDTH
        p._y = -4
        function p:AddCard(card)
            card:SetParent(self)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", self, "TOPLEFT", 2, self._y)
            card:SetPoint("TOPRIGHT", self, "TOPRIGHT", -2, self._y)
            self._y = self._y - card:GetHeight() - 12
            self:SetHeight(-self._y + 10)
        end
    end
    return p
end

local MODE_TITLES = {
    party = "Party Frames", raid = "Raid Frames",
    ownPet = "Own Pet Frame", groupPets = "Group Pet Frames", npc = "NPC Companion Frames",
    spotlight = "Spotlight Frame",
}

local function BuildGeneralOverview(p, key)
    if N.PET_KEYS[key] or key == "spotlight" then
        local pc = N.MakeCard(p, L[MODE_TITLES[key]])
        pc:AddRow(N.MakeCheckbox(pc, L["Enabled"],
            function() return N.db[key].enabled end,
            function(v) N:Set(key .. ".enabled", v) end))
        local hint = N.FontString(pc, 11)
        hint:SetPoint("TOPLEFT", pc, "TOPLEFT", N.CARD_PAD, pc._y)
        hint:SetWidth(pc:GetWidth() - 2 * N.CARD_PAD)
        hint:SetJustifyH("LEFT")
        hint:SetTextColor(uc(M.color.textDim))
        hint:SetText(L["PET_HINT_" .. key])
        hint:SetHeight(hint:GetStringHeight() + 4)
        pc:SetHeight(-pc._y + hint:GetHeight() + N.CARD_PAD)
        p:AddCard(pc)
    end
    local frames = N.MakeCard(p, L[MODE_TITLES[key]])
    frames:AddRow(N.MakeCheckbox(frames, L["Hide Blizzard frames"],
        function() return N.db[key].hideBlizzard end,
        function(v) N:Set(key .. ".hideBlizzard", v) end))
    frames:AddRow(N.MakeCheckbox(frames, L["Show when solo"],
        function() return N.db[key].showSolo end,
        function(v) N:Set(key .. ".showSolo", v) end))
    if not (N.PET_KEYS[key] or key == "spotlight") then p:AddCard(frames) end

    local ui = N.MakeCard(p, L["Interface"])
    ui:AddRow(N.MakeCheckbox(ui, L["Minimap button"],
        function() return not N.db.minimap.hide end,
        function(v) N:Set("minimap.hide", not v) end))
    ui:AddRow(N.MakeDropdown(ui, L["Language"], {
        { value = "auto", text = L["Automatic (game language)"] },
        { value = "enUS", text = "English" },
        { value = "deDE", text = "Deutsch" },
        { value = "esES", text = "Español (España)" },
        { value = "esMX", text = "Español (México)" },
        { value = "frFR", text = "Français" },
        { value = "itIT", text = "Italiano" },
        { value = "ptBR", text = "Português (Brasil)" },
        { value = "ruRU", text = "Russian (ruRU)" },
        { value = "koKR", text = "Korean (koKR)" },
        { value = "zhCN", text = "Chinese, Simplified (zhCN)" },
        { value = "zhTW", text = "Chinese, Traditional (zhTW)" },
    }, function() return N.db.locale end,
       function(v)
           N:Set("locale", v)
           N.Dialog.Reload(L["LANG_RELOAD"])
       end))
    ui:AddRow(N.MakeCheckbox(ui, L["Transliterate Cyrillic names"],
        function() return N.db.translitNames end,
        function(v) N:Set("translitNames", v) end))
    ui:AddRow(N.MakeCheckbox(ui, L["Show welcome message"],
        function() return N.db.welcomeMessage ~= false end,
        function(v) N:Set("welcomeMessage", v) end))
    p:AddCard(ui)

    -- Window scale applies immediately (SetScale on the live window). The highlight color recolors
    -- the shared M.color table for anything built from here on; elements already painted baked
    -- their color into a texture, so a /reload is needed to see it everywhere, hence the hint.
    local winCard = N.MakeCard(p, L["Options Window"])
    winCard:AddRow(N.MakeSlider(winCard, L["Window Scale"], 0.7, 1.3, 0.05,
        function() return N.db.uiScale end,
        function(v)
            N:Set("uiScale", v)
            if window then window:SetScale(v) end
        end))
    winCard:AddRow(N.MakeSlider(winCard, L["Font Size"], 0.9, 1.5, 0.05,
        function() return N.db.fontScale end,
        function(v)
            N:Set("fontScale", v)
            N.ApplyFontScale()
        end))
    winCard:AddRow(N.MakeColorPicker(winCard, L["Highlight Color"],
        function() return N.db.accentColor end,
        function(v)
            N:Set("accentColor", v)
            if N.Recolor then N.Recolor(v) end
        end))
    local accentHint = N.FontString(winCard, 11)
    accentHint:SetPoint("TOPLEFT", winCard, "TOPLEFT", N.CARD_PAD, winCard._y)
    accentHint:SetWidth(winCard:GetWidth() - 2 * N.CARD_PAD)
    accentHint:SetJustifyH("LEFT")
    accentHint:SetTextColor(uc(M.color.textDim))
    accentHint:SetText(L["ACCENT_HINT"])
    accentHint:SetHeight(accentHint:GetStringHeight() + 4)
    winCard:SetHeight(-winCard._y + accentHint:GetHeight() + N.CARD_PAD)
    p:AddCard(winCard)

    -- Two font choices: the options window / dialogs, and every text on the unit frames.
    local fontOpts = {}
    for _, f in ipairs(M.FONTS) do
        fontOpts[#fontOpts + 1] = { value = f.key, text = f.key == "game" and L["Game default"] or f.text }
    end
    local fontCard = N.MakeCard(p, L["Fonts"])
    fontCard:AddRow(N.MakeDropdown(fontCard, L["Options window font"], fontOpts,
        function() return N.db.fontUI or "nucleus" end,
        function(v)
            N:Set("fontUI", v)
            N.ApplyFontChoices()
            N.ApplyFontScale()
        end))
    fontCard:AddRow(N.MakeDropdown(fontCard, L["Frame font"], fontOpts,
        function() return N.db.fontFrame or "nucleus" end,
        function(v)
            N:Set("fontFrame", v)
            N.ApplyFontChoices()
            N.ApplyFontScale()
            -- repaint the frames and aura rows with the new face
            for key in pairs(N.GROUP_KEYS) do
                N:Fire("NUCLEUS_SETTING_CHANGED", key, key .. ".appearance.font")
                N:Fire("NUCLEUS_SETTING_CHANGED", key, key .. ".auras.font")
            end
        end))
    local fontHint = N.FontString(fontCard, 11)
    fontHint:SetPoint("TOPLEFT", fontCard, "TOPLEFT", N.CARD_PAD, fontCard._y)
    fontHint:SetWidth(fontCard:GetWidth() - 2 * N.CARD_PAD)
    fontHint:SetJustifyH("LEFT")
    fontHint:SetTextColor(uc(M.color.textDim))
    fontHint:SetText(L["FONT_HINT"])
    fontHint:SetHeight(fontHint:GetStringHeight() + 4)
    fontCard:SetHeight(-fontCard._y + fontHint:GetHeight() + N.CARD_PAD)
    p:AddCard(fontCard)


    local ping = N.MakeCard(p, L["Ping"])
    ping:AddRow(ActionButton(ping, L["Ping Settings"], function() N.ShowPingPopup() end))
    p:AddCard(ping)
end

local function BuildTooltip(p)
    local c = N.MakeCard(p, L["Tooltip"])
    c:AddRow(N.MakeCheckbox(c, L["Show tooltips"],
        function() return N.db.tooltip.enabled end,
        function(v) N:Set("tooltip.enabled", v) end))
    c:AddRow(N.MakeCheckbox(c, L["Hide tooltips in combat"],
        function() return N.db.tooltip.hideInCombat end,
        function(v) N:Set("tooltip.hideInCombat", v) end))
    p:AddCard(c)
end

local function BuildPosition(p)
    local c = N.MakeCard(p, L["Position"])
    c:AddRow(N.MakeCheckbox(c, L["Lock frames"],
        function() return N.db.locked end,
        function(v) N:Set("locked", v) end))
    local hint = N.FontString(c, 11)
    hint:SetPoint("TOPLEFT", N.CARD_PAD, c._y)
    hint:SetWidth(c:GetWidth() - 2 * N.CARD_PAD)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(uc(M.color.textDim))
    hint:SetText(L["POSITION_HINT"])
    hint:SetHeight(hint:GetStringHeight() + 4)
    c:SetHeight(-c._y + hint:GetHeight() + N.CARD_PAD)
    p:AddCard(c)
end

local function BuildPetSwitch(p, key)
    if key == "spotlight" then return end
    local c = N.MakeCard(p, L["Pets / NPCs"])
    if N.PET_KEYS[key] then
        c:AddRow(N.MakeDropdown(c, L["Frame type"], {
            { value = "ownPet", text = L["Own pet"] },
            { value = "groupPets", text = L["Group pets"] },
            { value = "npc", text = L["NPC companions"] },
        }, function() return N:Mode() end,
           function(v) N:SetMode(v); if N.RefreshMode then N.RefreshMode() end end))
        c:AddRow(ActionButton(c, L["Back to Group / Raid frames"], function()
            N:SetMode("party")
            if N.RefreshMode then N.RefreshMode() end
        end))
    else
        c:AddRow(ActionButton(c, L["Edit pets, companions and NPCs"], function()
            N:SetMode(N.db.lastPetMode or "ownPet")
            if N.RefreshMode then N.RefreshMode() end
        end))
    end
    p:AddCard(c)
end

local function CheckGrid(card, items, cols)
    local inner = card:GetWidth() - 2 * N.CARD_PAD
    local colW = math.floor(inner / cols)
    local i = 1
    while i <= #items do
        local row = CreateFrame("Frame", nil, card)
        row._rowHeight = 26
        for c = 0, cols - 1 do
            local it = items[i]
            if not it then break end
            local cb = N.MakeCheckbox(row, it.label, it.get, it.set)
            cb:SetParent(row)
            cb:ClearAllPoints()
            cb:SetPoint("LEFT", row, "LEFT", c * colW, 0)
            cb:SetPoint("RIGHT", row, "LEFT", (c + 1) * colW - 6, 0)
            cb:SetHeight(24)
            i = i + 1
        end
        card:AddRow(row)
    end
end

local function BuildLayout(p, key)
    BuildPetSwitch(p, key)
    local layout = N.MakeCard(p, L["Layout"])
    layout:AddRow(N.MakeCheckbox(layout, L["Enabled"],
        function() return N.db[key].enabled end,
        function(v) N:Set(key .. ".enabled", v) end))
    if key ~= "ownPet" then
        layout:AddRow(N.MakeDropdown(layout, L["Orientation"], {
            { value = "vertical", text = L["Vertical"] },
            { value = "horizontal", text = L["Horizontal"] },
        }, function() return N.db[key].orientation end,
           function(v) N:Set(key .. ".orientation", v) end))
        layout:AddRow(N.MakeCheckbox(layout, L["Reverse growth"],
            function() return N.db[key].reverse end,
            function(v) N:Set(key .. ".reverse", v) end))
    end
    if key == "raid" then
        layout:AddRow(N.MakeDropdown(layout, L["Group by"], {
            { value = "GROUP", text = L["Raid group"] },
            { value = "CLASS", text = L["Class"] },
            { value = "ROLE", text = L["Role"] },
            { value = "NONE", text = L["None"] },
        }, function() return N.db.raid.groupBy end,
           function(v) N:Set("raid.groupBy", v) end))
        layout:AddRow(N.MakeDropdown(layout, L["Sort"], {
            { value = "INDEX", text = L["By index"] },
            { value = "NAME", text = L["By name"] },
        }, function() return N.db.raid.sortMethod end,
           function(v) N:Set("raid.sortMethod", v) end))
    elseif key == "party" then
        layout:AddRow(N.MakeCheckbox(layout, L["Show self"],
            function() return N.db.party.showPlayer end,
            function(v) N:Set("party.showPlayer", v) end))
    end
    p:AddCard(layout)

    if key == "raid" then
        local gc = N.MakeCard(p, L["Raid groups"])
        local items = {}
        for g = 1, 8 do
            items[#items + 1] = {
                label = L["Group %d"]:format(g),
                get = function() return N.db.raid.groupFilter[g] ~= false end,
                set = function(v)
                    local t = {}
                    for i = 1, 8 do t[i] = N.db.raid.groupFilter[i] ~= false end
                    t[g] = v and true or false
                    N:Set("raid.groupFilter", t)
                end,
            }
        end
        gc:AddRow(N.MakeSlider(gc, L["Groups shown"], 1, 8, 1,
            function() return N.db.raid.maxGroups or 8 end,
            function(v) N:Set("raid.maxGroups", N.Round(v)) end))
        CheckGrid(gc, items, 2)
        local gnote = N.FontString(gc, 11)
        gnote:SetPoint("TOPLEFT", gc, "TOPLEFT", N.CARD_PAD, gc._y)
        gnote:SetWidth(gc:GetWidth() - 2 * N.CARD_PAD)
        gnote:SetJustifyH("LEFT")
        gnote:SetTextColor(uc(M.color.textDim))
        gnote:SetText(L["RAIDGROUPS_NOTE"])
        gnote:SetHeight(gnote:GetStringHeight() + 4)
        gc:SetHeight(-gc._y + gnote:GetHeight() + N.CARD_PAD)
        p:AddCard(gc)

        local nc = N.MakeCard(p, L["Group names"])
        local gn = N.db.raid.groupNames
        nc:AddRow(N.MakeCheckbox(nc, L["Show group names"],
            function() return gn.enabled end, function(v) N:Set("raid.groupNames.enabled", v) end))
        nc:AddRow(N.MakeDropdown(nc, L["Position"], {
            { value = "above", text = L["Above the first frame"] },
            { value = "inside", text = L["Inside the first frame"] },
        }, function() return gn.position end, function(v) N:Set("raid.groupNames.position", v) end))
        nc:AddRow(N.MakeSlider(nc, L["Size"], 6, 24, 1,
            function() return gn.size end, function(v) N:Set("raid.groupNames.size", N.Round(v)) end))
        nc:AddRow(N.MakeColorPicker(nc, L["Color"],
            function() return gn.color end, function(v) N:Set("raid.groupNames.color", v) end))
        nc:AddRow(N.MakeSlider(nc, L["X offset"], -40, 40, 1,
            function() return gn.x end, function(v) N:Set("raid.groupNames.x", N.Round(v)) end))
        nc:AddRow(N.MakeSlider(nc, L["Y offset"], -40, 40, 1,
            function() return gn.y end, function(v) N:Set("raid.groupNames.y", N.Round(v)) end))
        local note = N.FontString(nc, 11)
        note:SetPoint("TOPLEFT", nc, "TOPLEFT", N.CARD_PAD, nc._y)
        note:SetWidth(nc:GetWidth() - 2 * N.CARD_PAD)
        note:SetJustifyH("LEFT")
        note:SetTextColor(uc(M.color.textDim))
        note:SetText(L["GROUPNAMES_NOTE"])
        note:SetHeight(note:GetStringHeight() + 4)
        nc:SetHeight(-nc._y + note:GetHeight() + N.CARD_PAD)
        p:AddCard(nc)
    end

    if key == "party" or key == "raid" then
        local so = N.MakeCard(p, L["Sorting"])
        local ord = function() return N.db[key].ordering end
        local dim = {}
        local function refreshDim()
            for _, w in ipairs(dim) do w:SetAlpha(ord().enabled and 1 or 0.4) end
        end
        so:AddRow(N.MakeCheckbox(so, L["Custom sorting"],
            function() return ord().enabled end,
            function(v) N:Set(key .. ".ordering.enabled", v); refreshDim() end))

        -- Who comes after whom: three slots, each one a role; picking a role that
        -- another slot already has swaps the two.
        local slots = { "first", "second", "third" }
        local slotLabels = { L["Comes first"], L["Comes second"], L["Comes third"] }
        local roleOpts = {
            { value = "TANK", text = L["Tank"] },
            { value = "HEALER", text = L["Healer"] },
            { value = "DAMAGER", text = L["Damage dealer"] },
        }
        local dropdowns = {}
        for i, slot in ipairs(slots) do
            local dd = N.MakeDropdown(so, slotLabels[i], roleOpts,
                function() return ord()[slot] end,
                function(v)
                    local o = ord()
                    local old = o[slot]
                    for _, other in ipairs(slots) do
                        if other ~= slot and o[other] == v then
                            N:Set(key .. ".ordering." .. other, old)
                        end
                    end
                    N:Set(key .. ".ordering." .. slot, v)
                    for _, d in ipairs(dropdowns) do d.Refresh() end
                end)
            dropdowns[#dropdowns + 1] = dd
            dim[#dim + 1] = dd
            so:AddRow(dd)
        end

        local names = N.MakeMultiEdit(so, L["Always on top (optional)"],
            function() return ord().pinned end,
            function(v) N:Set(key .. ".ordering.pinned", v) end)
        dim[#dim + 1] = names
        so:AddRow(names)
        local sh = N.FontString(so, 11)
        sh:SetPoint("TOPLEFT", so, "TOPLEFT", N.CARD_PAD, so._y)
        sh:SetWidth(so:GetWidth() - 2 * N.CARD_PAD)
        sh:SetJustifyH("LEFT")
        sh:SetTextColor(uc(M.color.textDim))
        sh:SetText(L["SORT_HINT"])
        sh:SetHeight(sh:GetStringHeight() + 4)
        so:SetHeight(-so._y + sh:GetHeight() + N.CARD_PAD)
        refreshDim()
        p:AddCard(so)
    end

    local size = N.MakeCard(p, L["Size"])
    size:AddRow(N.MakeSlider(size, L["Frame width"], 40, 260, 1,
        function() return N.db[key].width end,
        function(v) N:Set(key .. ".width", N.Round(v)) end))
    size:AddRow(N.MakeSlider(size, L["Frame height"], 20, 120, 1,
        function() return N.db[key].height end,
        function(v) N:Set(key .. ".height", N.Round(v)) end))
    if key ~= "ownPet" then
        size:AddRow(N.MakeSlider(size, L["Spacing"], 0, 20, 1,
            function() return N.db[key].spacing end,
            function(v) N:Set(key .. ".spacing", N.Round(v)) end))
    end
    if key == "raid" or key == "groupPets" then
        size:AddRow(N.MakeSlider(size, L["Units per column"], 1, 10, 1,
            function() return N.db[key].unitsPerColumn end,
            function(v) N:Set(key .. ".unitsPerColumn", N.Round(v)) end))
    end
    if key == "groupPets" then
        size:AddRow(N.MakeSlider(size, L["Columns"], 1, 8, 1,
            function() return N.db[key].maxColumns end,
            function(v) N:Set(key .. ".maxColumns", N.Round(v)) end))
    end
    p:AddCard(size)

    if key == "ownPet" or key == "groupPets" then
        local at = N.MakeCard(p, L["Attach to owner"])
        at:AddRow(N.MakeCheckbox(at, L["Attach to the owner's frame"],
            function() return N.db[key].attachEnabled end,
            function(v) N:Set(key .. ".attachEnabled", v) end))
        at:AddRow(N.MakeDropdown(at, L["Side of the owner's frame"], {
            { value = "RIGHT", text = L["Right"] },
            { value = "LEFT", text = L["Left"] },
            { value = "TOP", text = L["Up"] },
            { value = "BOTTOM", text = L["Down"] },
        }, function() return N.db[key].attachSide end,
           function(v) N:Set(key .. ".attachSide", v) end))
        at:AddRow(N.MakeSlider(at, L["Distance"], -10, 30, 1,
            function() return N.db[key].attachGap end,
            function(v) N:Set(key .. ".attachGap", N.Round(v)) end))
        at:AddRow(N.MakeSlider(at, L["Shift"], -40, 40, 1,
            function() return N.db[key].attachShift end,
            function(v) N:Set(key .. ".attachShift", N.Round(v)) end))
        local ah = N.FontString(at, 11)
        ah:SetPoint("TOPLEFT", at, "TOPLEFT", N.CARD_PAD, at._y)
        ah:SetWidth(at:GetWidth() - 2 * N.CARD_PAD)
        ah:SetJustifyH("LEFT")
        ah:SetTextColor(uc(M.color.textDim))
        ah:SetText(L["ATTACH_HINT"])
        ah:SetHeight(ah:GetStringHeight() + 4)
        at:SetHeight(-at._y + ah:GetHeight() + N.CARD_PAD)
        p:AddCard(at)
    end
end

local function BuildRange(p, key)
    local c = N.MakeCard(p, L["Range"])
    c:AddRow(N.MakeSlider(c, L["Out-of-range opacity"], 0.1, 1, 0.05,
        function() return N.db[key].appearance.outOfRangeAlpha end,
        function(v) N:Set(key .. ".appearance.outOfRangeAlpha", v) end))
    c:AddRow(N.MakeSlider(c, L["Range check interval"], 0.05, 0.5, 0.05,
        function() return N.db.core.rangeUpdateInterval end,
        function(v) N:Set("core.rangeUpdateInterval", v) end))
    p:AddCard(c)

    -- Reuses the out-of-range opacity above as the fade amount: one dial for how faded, this only
    -- decides when it also applies.
    local fade = N.MakeCard(p, L["Fade at Full Health"])
    fade:AddRow(N.MakeCheckbox(fade, L["Fade at Full Health"],
        function() return N.db[key].appearance.healthFade.enabled end,
        function(v) N:Set(key .. ".appearance.healthFade.enabled", v) end))
    fade:AddRow(N.MakeSlider(fade, L["Health Fade Threshold"], 1, 100, 1,
        function() return (N.db[key].appearance.healthFade.threshold or 1) * 100 end,
        function(v) N:Set(key .. ".appearance.healthFade.threshold", v / 100) end))
    p:AddCard(fade)
end

local function BuildColor(p, key)
    local a = N.db[key].appearance

    local tex = N.MakeCard(p, L["Texture"])
    tex:AddRow(N.MakeDropdown(tex, L["Bar texture"], {
        { value = "nucleus", text = "Nucleus" },
        { value = "nucleus2", text = "Nucleus 2" },
        { value = "nucleus3", text = "Nucleus Gloss" },
        { value = "flat", text = L["Flat"] },
        { value = "gradient", text = L["Gradient"] },
        { value = "modern", text = L["Modern"] },
    }, function() return a.barTexture end,
       function(v) N:Set(key .. ".appearance.barTexture", v) end))
    p:AddCard(tex)

    local col = N.MakeCard(p, L["Health Bar Color"])
    col:AddRow(N.MakeDropdown(col, L["Color mode"], {
        { value = "class", text = L["Class color"] },
        { value = "custom", text = L["Custom color"] },
        { value = "gradient", text = L["Health gradient"] },
    }, function() return a.healthColorMode end,
       function(v) N:Set(key .. ".appearance.healthColorMode", v) end))
    col:AddRow(N.MakeColorPicker(col, L["Custom color"],
        function() return a.healthCustomColor end,
        function(v) N:Set(key .. ".appearance.healthCustomColor", v) end))
    col:AddRow(N.MakeColorPicker(col, L["Health loss color"],
        function() return a.healthLossColor end,
        function(v) N:Set(key .. ".appearance.healthLossColor", v) end))
    p:AddCard(col)

    local STYLE_OPTS = {
        { value = "flat", text = L["Flat"] },
        { value = "striped", text = L["Striped"] },
    }
    local ap = key .. ".appearance."

    local shield = N.MakeCard(p, L["Shield"])
    shield:AddRow(N.MakeCheckbox(shield, L["Enabled"],
        function() return a.absorb.enabled end, function(v) N:Set(ap .. "absorb.enabled", v) end))
    shield:AddRow(N.MakeDropdown(shield, L["Texture Style"], STYLE_OPTS,
        function() return a.absorb.style end, function(v) N:Set(ap .. "absorb.style", v) end))
    shield:AddRow(N.MakeSlider(shield, L["Opacity"], 0.1, 1, 0.05,
        function() return a.absorb.opacity end, function(v) N:Set(ap .. "absorb.opacity", v) end))
    shield:AddRow(N.MakeColorPicker(shield, L["Color"],
        function() return a.absorb.color end, function(v) N:Set(ap .. "absorb.color", v) end))
    shield:AddRow(N.MakeCheckbox(shield, L["Inverted fill"],
        function() return a.absorb.invertFill end, function(v) N:Set(ap .. "absorb.invertFill", v) end))
    shield:AddRow(N.MakeCheckbox(shield, L["Show Overshield Spark"],
        function() return a.showOvershield end, function(v) N:Set(ap .. "showOvershield", v) end))
    shield:AddRow(N.MakeColorPicker(shield, L["Overshield color"],
        function() return a.overshieldColor end, function(v) N:Set(ap .. "overshieldColor", v) end))
    p:AddCard(shield)

    local healAbsorb = N.MakeCard(p, L["Heal Absorb"])
    healAbsorb:AddRow(N.MakeCheckbox(healAbsorb, L["Enabled"],
        function() return a.healAbsorb.enabled end, function(v) N:Set(ap .. "healAbsorb.enabled", v) end))
    healAbsorb:AddRow(N.MakeDropdown(healAbsorb, L["Texture Style"], STYLE_OPTS,
        function() return a.healAbsorb.style end, function(v) N:Set(ap .. "healAbsorb.style", v) end))
    healAbsorb:AddRow(N.MakeSlider(healAbsorb, L["Opacity"], 0.1, 1, 0.05,
        function() return a.healAbsorb.opacity end, function(v) N:Set(ap .. "healAbsorb.opacity", v) end))
    healAbsorb:AddRow(N.MakeColorPicker(healAbsorb, L["Color"],
        function() return a.healAbsorb.color end, function(v) N:Set(ap .. "healAbsorb.color", v) end))
    p:AddCard(healAbsorb)

    local healPredict = N.MakeCard(p, L["Heal Prediction"])
    healPredict:AddRow(N.MakeCheckbox(healPredict, L["Enabled"],
        function() return a.healPredict.enabled end, function(v) N:Set(ap .. "healPredict.enabled", v) end))
    healPredict:AddRow(N.MakeSlider(healPredict, L["Opacity"], 0.1, 1, 0.05,
        function() return a.healPredict.opacity end, function(v) N:Set(ap .. "healPredict.opacity", v) end))
    healPredict:AddRow(N.MakeColorPicker(healPredict, L["Color"],
        function() return a.healPredict.color end, function(v) N:Set(ap .. "healPredict.color", v) end))
    p:AddCard(healPredict)

    local tcc = N.MakeCard(p, L["Time text"])
    tcc:AddRow(N.MakeCheckbox(tcc, L["Change the colour when time is running out"],
        function() return a.timeColor.enabled end,
        function(v) N:Set(key .. ".appearance.timeColor.enabled", v) end))
    tcc:AddRow(N.MakeSlider(tcc, L["Below (seconds)"], 1, 30, 1,
        function() return a.timeColor.seconds end,
        function(v) N:Set(key .. ".appearance.timeColor.seconds", N.Round(v)) end))
    tcc:AddRow(N.MakeColorPicker(tcc, L["Color"],
        function() return a.timeColor.color end,
        function(v) N:Set(key .. ".appearance.timeColor.color", v) end))
    tcc:AddRow(N.MakeSlider(tcc, L["Count in tenths below (seconds)"], 0, 30, 1,
        function() return a.timeColor.decimals end,
        function(v) N:Set(key .. ".appearance.timeColor.decimals", N.Round(v)) end))
    local tch = N.FontString(tcc, 11)
    tch:SetPoint("TOPLEFT", tcc, "TOPLEFT", N.CARD_PAD, tcc._y)
    tch:SetWidth(tcc:GetWidth() - 2 * N.CARD_PAD)
    tch:SetJustifyH("LEFT")
    tch:SetTextColor(uc(M.color.textDim))
    tch:SetText(L["TIMECOLOR_HINT"])
    tch:SetHeight(tch:GetStringHeight() + 4)
    tcc:SetHeight(-tcc._y + tch:GetHeight() + N.CARD_PAD)
    p:AddCard(tcc)

    local fb = N.MakeCard(p, L["Frame border"])
    fb:AddRow(N.MakeCheckbox(fb, L["Enabled"],
        function() return a.frameBorder.enabled end,
        function(v) N:Set(key .. ".appearance.frameBorder.enabled", v) end))
    fb:AddRow(N.MakeColorPicker(fb, L["Color"],
        function() return a.frameBorder.color end,
        function(v) N:Set(key .. ".appearance.frameBorder.color", v) end))
    fb:AddRow(N.MakeSlider(fb, L["Thickness"], 1, 4, 1,
        function() return a.frameBorder.thickness end,
        function(v) N:Set(key .. ".appearance.frameBorder.thickness", N.Round(v)) end))
    p:AddCard(fb)

    local border = N.MakeCard(p, L["Border"])
    border:AddRow(N.MakeColorPicker(border, L["Target Border Color"],
        function() return a.targetBorder.color end,
        function(v) N:Set(key .. ".appearance.targetBorder.color", v) end))
    border:AddRow(N.MakeSlider(border, L["Target Border Thickness"], 1, 4, 1,
        function() return a.targetBorder.thickness end,
        function(v) N:Set(key .. ".appearance.targetBorder.thickness", N.Round(v)) end))
    border:AddRow(N.MakeColorPicker(border, L["Mouseover Border Color"],
        function() return a.hoverBorder.color end,
        function(v) N:Set(key .. ".appearance.hoverBorder.color", v) end))
    border:AddRow(N.MakeSlider(border, L["Mouseover Border Thickness"], 1, 4, 1,
        function() return a.hoverBorder.thickness end,
        function(v) N:Set(key .. ".appearance.hoverBorder.thickness", N.Round(v)) end))
    p:AddCard(border)
end

-- The Status Icon shows one of several icons depending on the unit's state, but the preview can
-- only show one at a time. This card lists every kind with its icons, large enough to recognise,
-- and lets the player switch each kind on or off.
local function AddStatusIconKinds(card, o, pth)
    for _, kind in ipairs(N.Indicators.statusIconKinds) do
        local row = CreateFrame("Frame", nil, card)
        row._rowHeight = 34

        local right = 0
        for i = #kind.icons, 1, -1 do
            local ic = kind.icons[i]
            local t = row:CreateTexture(nil, "ARTWORK")
            t:SetSize(30, 30)
            t:SetPoint("RIGHT", row, "RIGHT", -right, 0)
            if ic.atlas then
                t:SetAtlas(ic.atlas)
            else
                t:SetTexture(ic.tex)
                if ic.coord then t:SetTexCoord(unpack(ic.coord)) end
            end
            if ic.color then t:SetVertexColor(ic.color[1], ic.color[2], ic.color[3]) end
            right = right + 34
        end

        local cb = N.MakeCheckbox(row, L[kind.label] or kind.label,
            function() return not (o.show and o.show[kind.key] == false) end,
            function(v) N:Set(pth("show." .. kind.key), v) end)
        cb:SetParent(row)
        cb:ClearAllPoints()
        cb:SetPoint("LEFT", row, "LEFT", 0, 0)
        cb:SetPoint("RIGHT", row, "RIGHT", -(right + 6), 0)
        cb:SetHeight(24)
        card:AddRow(row)
    end
end

local TEXT_POSITION_LABELS = {
    topleft = "Top Left", top = "Top", topright = "Top Right",
    left = "Left", center = "Center", right = "Right",
    bottomleft = "Bottom Left", bottom = "Bottom", bottomright = "Bottom Right",
}

-- Health Thresholds: a list of marks (health percentage + colour); rows can be
-- added and removed, so the page rebuilds itself below the preview.
local function BuildThresholds(p, key, meta)
    local o = N.db[key].indicators.healthThresholds
    local base = key .. ".indicators.healthThresholds"
    local function touch() N:Fire("NUCLEUS_SETTING_CHANGED", key, base .. ".thresholds") end
    if N.Preview then p.previewHost = N.Preview.Create(p, meta.name) end

    local body
    local function rebuild()
        body()
        if N.OptionsResize then N.OptionsResize(p) end
    end

    body = function()
        for _, child in ipairs({ p:GetChildren() }) do
            if child ~= p.previewHost then child:Hide(); child:SetParent(nil) end
        end
        p._y = -4

        local c = N.MakeCard(p, L[meta.label])
        c:AddRow(N.MakeCheckbox(c, L["Enabled"],
            function() return o.enabled end, function(v) N:Set(base .. ".enabled", v) end))
        c:AddRow(N.MakeSlider(c, L["Thickness"], 1, 6, 1,
            function() return o.thickness end, function(v) N:Set(base .. ".thickness", N.Round(v)) end))
        local hint = N.FontString(c, 11)
        hint:SetPoint("TOPLEFT", c, "TOPLEFT", N.CARD_PAD, c._y)
        hint:SetWidth(c:GetWidth() - 2 * N.CARD_PAD)
        hint:SetJustifyH("LEFT")
        hint:SetTextColor(uc(M.color.textDim))
        hint:SetText(L["THRESHOLD_HINT"])
        hint:SetHeight(hint:GetStringHeight() + 4)
        c:SetHeight(-c._y + hint:GetHeight() + N.CARD_PAD)
        p:AddCard(c)

        local list = N.MakeCard(p, L["Thresholds"])
        for i, t in ipairs(o.thresholds) do
            local row = CreateFrame("Frame", nil, list)
            row._rowHeight = 32

            local pct = N.MakeTextInput(row, nil,
                function() return tostring(t.pct or 0) end,
                function(v)
                    local n = tonumber(v)
                    if n then
                        t.pct = math.max(1, math.min(99, math.floor(n + 0.5)))
                        touch()
                    end
                end)
            pct:SetParent(row)
            pct:ClearAllPoints()
            pct:SetPoint("LEFT", row, "LEFT", 0, 0)
            pct:SetSize(64, 24)
            local sign = N.FontString(row, 12)
            sign:SetPoint("LEFT", pct, "RIGHT", 4, 0)
            sign:SetText("%")
            sign:SetTextColor(uc(M.color.textDim))

            local sw = CreateFrame("Button", nil, row)
            sw:SetSize(34, 20)
            sw:SetPoint("LEFT", pct, "RIGHT", 28, 0)
            N.SkinRound(sw, M.color.base, M.color.line, true)
            local fill = sw._nucFill
            local col = t.color or { 1, 0, 0 }
            fill:SetColorTexture(col[1], col[2], col[3])
            sw:SetScript("OnEnter", function() N.SetPanelBorder(sw, M.color.accent) end)
            sw:SetScript("OnLeave", function() N.SetPanelBorder(sw, M.color.line) end)
            sw:SetScript("OnClick", function()
                local cc = t.color or { 1, 0, 0 }
                N.ColorPicker:Open({
                    r = cc[1], g = cc[2], b = cc[3], title = L["Color"],
                    onChange = function(r, g, b) fill:SetColorTexture(r, g, b) end,
                    onAccept = function(r, g, b)
                        t.color = { r, g, b }
                        fill:SetColorTexture(r, g, b)
                        touch()
                    end,
                    onCancel = function()
                        local old = t.color or { 1, 0, 0 }
                        fill:SetColorTexture(old[1], old[2], old[3])
                    end,
                })
            end)

            local del = CreateFrame("Button", nil, row)
            del:SetSize(24, 22)
            del:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            N.SkinRound(del, M.color.base, M.color.line, true)
            local tint = N.MakeCross(del, 9, 2)
            tint(uc(M.color.textDim))
            del:SetScript("OnEnter", function()
                del._nucFill:SetColorTexture(0.80, 0.22, 0.22, 1)
                tint(1, 1, 1, 1)
            end)
            del:SetScript("OnLeave", function()
                del._nucFill:SetColorTexture(uc(M.color.base))
                tint(uc(M.color.textDim))
            end)
            del:SetScript("OnClick", function()
                table.remove(o.thresholds, i)
                touch()
                rebuild()
            end)
            list:AddRow(row)
        end
        if #o.thresholds < N.Indicators.THRESHOLD_MAX then
            list:AddRow(ActionButton(list, "+  " .. L["Add threshold"], function()
                table.insert(o.thresholds, { pct = 50, color = { 1, 0.85, 0 } })
                touch()
                rebuild()
            end))
        end
        p:AddCard(list)
    end
    body()
end

local function BuildIndicator(p, key, meta)
    if meta.thresholds then return BuildThresholds(p, key, meta) end
    local base = key .. ".indicators." .. meta.name
    local o = N.db[key].indicators[meta.name]
    local function pth(f) return base .. "." .. f end

    -- The preview is not part of the scrolling panel: SelectSub pins it above the
    -- scroll area so it stays in view while the settings scroll.
    if N.Preview then p.previewHost = N.Preview.Create(p, meta.name) end

    local c = N.MakeCard(p, L[meta.label])
    c:AddRow(N.MakeCheckbox(c, L["Enabled"],
        function() return o.enabled end,
        function(v) N:Set(pth("enabled"), v) end))

    if meta.name == "name" then
        -- Forever characters have a surname: show both, only the first name or only the last.
        c:AddRow(N.MakeDropdown(c, L["Name format"], {
            { value = "full", text = L["First and last name"] },
            { value = "first", text = L["First name only"] },
            { value = "last", text = L["Last name only"] },
        }, function() return o.nameFormat or "full" end, function(v) N:Set(pth("nameFormat"), v) end))
    end

    if meta.name == "role" then
        c:AddRow(N.MakeDropdown(c, L["Icon Style"], {
            { value = "square", text = L["Square"] },
            { value = "square2", text = L["Square 2"] },
            { value = "circle", text = L["Circle"] },
        }, function() return o.shape end, function(v) N:Set(pth("shape"), v) end))
        c:AddRow(N.MakeCheckbox(c, L["Show for tanks"],
            function() return o.showTank end, function(v) N:Set(pth("showTank"), v) end))
        c:AddRow(N.MakeCheckbox(c, L["Show for healers"],
            function() return o.showHealer end, function(v) N:Set(pth("showHealer"), v) end))
        c:AddRow(N.MakeCheckbox(c, L["Show for damage dealers"],
            function() return o.showDamager end, function(v) N:Set(pth("showDamager"), v) end))
        c:AddRow(N.MakeCheckbox(c, L["Hide in combat"],
            function() return o.hideInCombat end, function(v) N:Set(pth("hideInCombat"), v) end))
        c:AddRow(N.MakeCheckbox(c, L["Show when solo"],
            function() return o.showSolo ~= false end, function(v) N:Set(pth("showSolo"), v) end))
    end

    if meta.format then
        c:AddRow(N.MakeDropdown(c, L["Format"], {
            { value = "percent", text = L["Percent"] },
            { value = "percentNoSign", text = L["Percent (no %)"] },
            { value = "value", text = L["Value"] },
            { value = "valuePercent", text = L["Value | Percent"] },
            { value = "percentValue", text = L["Percent | Value"] },
            { value = "deficit", text = L["Deficit"] },
            { value = "custom", text = L["Custom"] },
        }, function() return o.format end, function(v) N:Set(pth("format"), v) end))
        c:AddRow(N.MakeTextInput(c, L["CUSTOM_FORMAT_LABEL"],
            function() return o.customFormat end, function(v) N:Set(pth("customFormat"), v) end))
    end

    if meta.absorbFormat then
        c:AddRow(N.MakeDropdown(c, L["Format"], {
            { value = "short", text = L["Short (12K)"] },
            { value = "full", text = L["Full (12,345)"] },
            { value = "percent", text = L["Percent of max health"] },
        }, function() return o.format end, function(v) N:Set(pth("format"), v) end))
    end

    if meta.levelFormat then
        c:AddRow(N.MakeDropdown(c, L["Format"], {
            { value = "full", text = L["Level 80"] },
            { value = "short", text = L["Lvl 80"] },
            { value = "number", text = L["80"] },
        }, function() return o.format end, function(v) N:Set(pth("format"), v) end))
    end

    if meta.shield then
        c:AddRow(N.MakeSlider(c, L["Height"], 1, 100, 1,
            function() return o.height end, function(v) N:Set(pth("height"), N.Round(v)) end))
        c:AddRow(N.MakeDropdown(c, L["Position"], {
            { value = "bottom", text = L["Bottom"] },
            { value = "top", text = L["Top"] },
        }, function() return o.position end, function(v) N:Set(pth("position"), v) end))
        c:AddRow(N.MakeSlider(c, L["X offset"], -100, 100, 1,
            function() return o.x end, function(v) N:Set(pth("x"), N.Round(v)) end))
        c:AddRow(N.MakeSlider(c, L["Y offset"], -100, 100, 1,
            function() return o.y end, function(v) N:Set(pth("y"), N.Round(v)) end))
        c:AddRow(N.MakeDropdown(c, L["Fill from"], {
            { value = "left", text = L["Left"] },
            { value = "right", text = L["Right"] },
        }, function() return o.growFrom end, function(v) N:Set(pth("growFrom"), v) end))
        c:AddRow(N.MakeColorPicker(c, L["Color"],
            function() return o.color end, function(v) N:Set(pth("color"), v) end))
        c:AddRow(N.MakeSlider(c, L["Opacity"], 0.1, 1, 0.05,
            function() return o.alpha end, function(v) N:Set(pth("alpha"), v) end))
        c:AddRow(N.MakeCheckbox(c, L["Only show overshields"],
            function() return o.onlyOvershield end, function(v) N:Set(pth("onlyOvershield"), v) end))
    elseif meta.missing then
        c:AddRow(N.MakeSlider(c, L["Icon size"], 8, 32, 1,
            function() return o.size end, function(v) N:Set(pth("size"), N.Round(v)) end))
        c:AddRow(N.MakeSlider(c, L["Spacing"], 0, 10, 1,
            function() return o.spacing end, function(v) N:Set(pth("spacing"), N.Round(v)) end))
        local posOpts = {}
        for _, key in ipairs(N.UnitFrame.TEXT_POSITIONS) do
            posOpts[#posOpts + 1] = { value = key, text = L[TEXT_POSITION_LABELS[key]] }
        end
        c:AddRow(N.MakeDropdown(c, L["Position"], posOpts,
            function() return o.position end, function(v) N:Set(pth("position"), v) end))
        c:AddRow(N.MakeDropdown(c, L["Growth direction"], {
            { value = "RIGHT", text = L["Right"] },
            { value = "LEFT", text = L["Left"] },
            { value = "UP", text = L["Up"] },
            { value = "DOWN", text = L["Down"] },
        }, function() return o.growth end, function(v) N:Set(pth("growth"), v) end))
        c:AddRow(N.MakeSlider(c, L["X offset"], -60, 60, 1,
            function() return o.x end, function(v) N:Set(pth("x"), N.Round(v)) end))
        c:AddRow(N.MakeSlider(c, L["Y offset"], -60, 60, 1,
            function() return o.y end, function(v) N:Set(pth("y"), N.Round(v)) end))
        c:AddRow(N.MakeCheckbox(c, L["Hide in combat"],
            function() return o.hideInCombat end, function(v) N:Set(pth("hideInCombat"), v) end))
    elseif meta.private then
        -- Blizzard draws these icons (boss mechanics addons may not read); we
        -- only choose where the slots go and what each shows.
        c:AddRow(N.MakeSlider(c, L["Max icons"], 1, 5, 1,
            function() return o.num end, function(v) N:Set(pth("num"), N.Round(v)) end))
        c:AddRow(N.MakeSlider(c, L["Icon size"], 8, 48, 1,
            function() return o.size end, function(v) N:Set(pth("size"), N.Round(v)) end))
        c:AddRow(N.MakeSlider(c, L["Spacing"], 0, 10, 1,
            function() return o.spacing end, function(v) N:Set(pth("spacing"), N.Round(v)) end))
        local posOpts = {}
        for _, key in ipairs(N.UnitFrame.TEXT_POSITIONS) do
            posOpts[#posOpts + 1] = { value = key, text = L[TEXT_POSITION_LABELS[key]] }
        end
        c:AddRow(N.MakeDropdown(c, L["Position"], posOpts,
            function() return o.position end, function(v) N:Set(pth("position"), v) end))
        c:AddRow(N.MakeDropdown(c, L["Growth direction"], {
            { value = "RIGHT", text = L["Right"] },
            { value = "LEFT", text = L["Left"] },
            { value = "UP", text = L["Up"] },
            { value = "DOWN", text = L["Down"] },
        }, function() return o.growth end, function(v) N:Set(pth("growth"), v) end))
        c:AddRow(N.MakeSlider(c, L["X offset"], -60, 60, 1,
            function() return o.x end, function(v) N:Set(pth("x"), N.Round(v)) end))
        c:AddRow(N.MakeSlider(c, L["Y offset"], -60, 60, 1,
            function() return o.y end, function(v) N:Set(pth("y"), N.Round(v)) end))
        c:AddRow(N.MakeSlider(c, L["Border scale"], 0.5, 2, 0.1,
            function() return o.borderScale end, function(v) N:Set(pth("borderScale"), v) end))
    elseif meta.aggro then
        c:AddRow(N.MakeSlider(c, L["Thickness"], 1, 10, 1,
            function() return o.thickness end, function(v) N:Set(pth("thickness"), N.Round(v)) end))
        c:AddRow(N.MakeCheckbox(c, L["Fade inward"],
            function() return o.gradient end, function(v) N:Set(pth("gradient"), v) end))
        -- One picker per threat level, with a dim note on the right saying what
        -- the colour stands for.
        local function colorRow(label, note, key)
            local row = N.MakeColorPicker(c, label,
                function() return o[key] end, function(v) N:Set(pth(key), v) end)
            local info = N.FontString(row, 11)
            info:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            info:SetTextColor(uc(M.color.textDim))
            info:SetText(note)
            c:AddRow(row)
        end
        colorRow(L["Orange"], L["AGGRO_ORANGE_INFO"], "warnColor")
        colorRow(L["Red"], L["AGGRO_RED_INFO"], "tankColor")
    elseif meta.status then
        c:AddRow(N.MakeDropdown(c, L["Anchor"], {
            { value = "top", text = L["Top"] },
            { value = "center", text = L["Center"] },
            { value = "bottom", text = L["Bottom"] },
        }, function() return o.anchor end, function(v) N:Set(pth("anchor"), v) end))
        c:AddRow(N.MakeDropdown(c, L["Alignment"], {
            { value = "left", text = L["Left"] },
            { value = "center", text = L["Center"] },
            { value = "right", text = L["Right"] },
        }, function() return o.align end, function(v) N:Set(pth("align"), v) end))
        c:AddRow(N.MakeCheckbox(c, L["Show timer"],
            function() return o.showTimer end, function(v) N:Set(pth("showTimer"), v) end))
        c:AddRow(N.MakeCheckbox(c, L["Show background"],
            function() return o.showBackground end, function(v) N:Set(pth("showBackground"), v) end))
        c:AddRow(N.MakeSlider(c, L["Size"], 6, 30, 1,
            function() return o.size end, function(v) N:Set(pth("size"), N.Round(v)) end))
        c:AddRow(N.MakeSlider(c, L["Y offset"], -40, 40, 1,
            function() return o.y end, function(v) N:Set(pth("y"), N.Round(v)) end))
    elseif meta.bar then
        c:AddRow(N.MakeSlider(c, L["Height"], 2, 14, 1,
            function() return o.height end, function(v) N:Set(pth("height"), N.Round(v)) end))
        c:AddRow(N.MakeSlider(c, L["X offset"], -40, 40, 1,
            function() return o.x end, function(v) N:Set(pth("x"), N.Round(v)) end))
        c:AddRow(N.MakeSlider(c, L["Y offset"], -40, 40, 1,
            function() return o.y end, function(v) N:Set(pth("y"), N.Round(v)) end))
    else
        if meta.positioned or meta.iconPosition then
            local posOpts = {}
            for _, key in ipairs(N.UnitFrame.TEXT_POSITIONS) do
                posOpts[#posOpts + 1] = { value = key, text = L[TEXT_POSITION_LABELS[key]] }
            end
            c:AddRow(N.MakeDropdown(c, L["Position"], posOpts,
                function()
                    return o.position or (meta.iconPosition and N.Indicators.DefaultPosition(meta.name)) or "center"
                end,
                function(v) N:Set(pth("position"), v) end))
        end
        if meta.positioned then
            c:AddRow(N.MakeDropdown(c, L["Color mode"], {
                { value = "custom", text = L["Custom color"] },
                { value = "class", text = L["Class color"] },
            }, function() return o.colorMode end, function(v) N:Set(pth("colorMode"), v) end))
        end
        if meta.text then
            c:AddRow(N.MakeColorPicker(c, L["Color"],
                function() return o.color end, function(v) N:Set(pth("color"), v) end))
        end
        c:AddRow(N.MakeSlider(c, L["Size"], 6, meta.icon and 64 or 30, 1,
            function() return o.size end, function(v) N:Set(pth("size"), N.Round(v)) end))
        c:AddRow(N.MakeSlider(c, L["X offset"], -40, 40, 1,
            function() return o.x end, function(v) N:Set(pth("x"), N.Round(v)) end))
        c:AddRow(N.MakeSlider(c, L["Y offset"], -40, 40, 1,
            function() return o.y end, function(v) N:Set(pth("y"), N.Round(v)) end))
    end
    p:AddCard(c)

    if meta.private then
        local cd = N.MakeCard(p, L["Countdown"])
        cd:AddRow(N.MakeCheckbox(cd, L["Show cooldown spiral"],
            function() return o.showCountdownFrame end, function(v) N:Set(pth("showCountdownFrame"), v) end))
        cd:AddRow(N.MakeCheckbox(cd, L["Show countdown numbers"],
            function() return o.showCountdownNumbers end, function(v) N:Set(pth("showCountdownNumbers"), v) end))
        p:AddCard(cd)
    end

    if meta.missing then
        local bc = N.MakeCard(p, L["Buffs to check"])
        for _, buff in ipairs(N.Indicators.missingBuffs) do
            local cb = N.MakeCheckbox(bc, L[buff.label] or buff.label,
                function() return not (o.buffs and o.buffs[buff.key] == false) end,
                function(v) N:Set(pth("buffs." .. buff.key), v) end)
            local pic = cb:CreateTexture(nil, "ARTWORK")
            pic:SetSize(20, 20)
            pic:SetPoint("RIGHT", cb, "RIGHT", 0, 0)
            pic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            pic:SetTexture((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(buff.icon or buff.ids[1])) or 134400)
            cb._rowHeight = 24
            bc:AddRow(cb)
        end
        p:AddCard(bc)
    end

    -- Power bar by class: Forever has no roles, so one switch per class.
    if meta.bar then
        local pc = N.MakeCard(p, L["Power bar by class"])
        local items = {}
        for _, e in ipairs(N.CLASS_ROLES) do
            local class = e[1]
            items[#items + 1] = {
                label = (_G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[class]) or class,
                get = function() local f = o.filter and o.filter[class]; return not (f and f.ALL == false) end,
                set = function(v) N:Set(pth("filter." .. class .. ".ALL"), v and true or false) end,
            }
        end
        CheckGrid(pc, items, 3)
        p:AddCard(pc)
    end
    if meta.bar then
        local t = N.MakeCard(p, L["Power Text"])
        t:AddRow(N.MakeCheckbox(t, L["Show text"],
            function() return o.text end, function(v) N:Set(pth("text"), v) end))
        t:AddRow(N.MakeDropdown(t, L["Text format"], {
            { value = "percent", text = L["Percent"] },
            { value = "percentNoSign", text = L["Percent (no %)"] },
            { value = "value", text = L["Value"] },
            { value = "valuePercent", text = L["Value | Percent"] },
            { value = "percentValue", text = L["Percent | Value"] },
            { value = "custom", text = L["Custom"] },
        }, function() return o.textFormat end, function(v) N:Set(pth("textFormat"), v) end))
        t:AddRow(N.MakeTextInput(t, L["CUSTOM_FORMAT_LABEL"],
            function() return o.customFormat end, function(v) N:Set(pth("customFormat"), v) end))
        local posOpts = {}
        for _, key in ipairs(N.UnitFrame.TEXT_POSITIONS) do
            posOpts[#posOpts + 1] = { value = key, text = L[TEXT_POSITION_LABELS[key]] }
        end
        t:AddRow(N.MakeDropdown(t, L["Position"], posOpts,
            function() return o.textPosition end, function(v) N:Set(pth("textPosition"), v) end))
        t:AddRow(N.MakeDropdown(t, L["Color mode"], {
            { value = "power", text = L["Power color"] },
            { value = "class", text = L["Class color"] },
            { value = "custom", text = L["Custom color"] },
        }, function() return o.textColorMode end, function(v) N:Set(pth("textColorMode"), v) end))
        t:AddRow(N.MakeColorPicker(t, L["Color"],
            function() return o.textColor end, function(v) N:Set(pth("textColor"), v) end))
        t:AddRow(N.MakeSlider(t, L["Size"], 6, 20, 1,
            function() return o.textSize end, function(v) N:Set(pth("textSize"), N.Round(v)) end))
        t:AddRow(N.MakeSlider(t, L["X offset"], -40, 40, 1,
            function() return o.textX end, function(v) N:Set(pth("textX"), N.Round(v)) end))
        t:AddRow(N.MakeSlider(t, L["Y offset"], -40, 40, 1,
            function() return o.textY end, function(v) N:Set(pth("textY"), N.Round(v)) end))
        p:AddCard(t)
    end

    if meta.name == "statusIcon" then
        local legend = N.MakeCard(p, L["Icons"])
        AddStatusIconKinds(legend, o, pth)
        p:AddCard(legend)
    elseif meta.status then
        local states = N.MakeCard(p, L["States"])
        for _, s in ipairs(N.Indicators.statusStates) do
            local row = CreateFrame("Frame", nil, states)
            row._rowHeight = 24
            local cb = N.MakeCheckbox(row, L[s.label] or s.label,
                function() return not (o.show and o.show[s.key] == false) end,
                function(v) N:Set(pth("show." .. s.key), v) end)
            cb:SetParent(row)
            cb:ClearAllPoints()
            cb:SetPoint("LEFT", row, "LEFT", 0, 0)
            cb:SetPoint("RIGHT", row, "RIGHT", -40, 0)
            cb:SetHeight(22)
            local sw = CreateFrame("Button", nil, row)
            sw:SetSize(30, 16)
            sw:SetPoint("RIGHT")
            N.SkinRound(sw, M.color.base, M.color.line, true)
            local tex = sw._nucFill
            local function refreshSwatch()
                local col = o.stateColors[s.key]
                tex:SetColorTexture(col[1], col[2], col[3])
            end
            refreshSwatch()
            sw:SetScript("OnEnter", function() N.SetPanelBorder(sw, M.color.accent) end)
            sw:SetScript("OnLeave", function() N.SetPanelBorder(sw, M.color.line) end)
            sw:SetScript("OnClick", function()
                N.ColorPicker:Open({
                    r = o.stateColors[s.key][1], g = o.stateColors[s.key][2], b = o.stateColors[s.key][3],
                    title = L[s.label] or s.label,
                    onChange = function(r, g, b) tex:SetColorTexture(r, g, b) end,
                    onAccept = function(r, g, b)
                        N:Set(pth("stateColors." .. s.key), { r, g, b })
                        refreshSwatch()
                    end,
                    onCancel = refreshSwatch,
                })
            end)
            states:AddRow(row)
        end
        p:AddCard(states)
    end
end

local AURA_TITLES = {
    buffs = "Buffs", debuffs = "Debuffs",
    dispels = "Dispellable Debuffs", defensives = "Defensive Cooldowns",
    externals = "External Cooldowns", offensives = "Offensive Cooldowns",
    crowdControls = "Crowd Controls",
}

local function BuildAuras(p, key, kind)
    local o = N.db[key].auras[kind]
    local base = key .. ".auras." .. kind
    local function pth(f) return base .. "." .. f end

    if N.Preview then p.previewHost = N.Preview.Create(p, kind) end

    local c = N.MakeCard(p, L[AURA_TITLES[kind]])
    c:AddRow(N.MakeCheckbox(c, L["Enabled"],
        function() return o.enabled end, function(v) N:Set(pth("enabled"), v) end))
    c:AddRow(N.MakeSlider(c, L["Max icons"], 1, 8, 1,
        function() return o.max end, function(v) N:Set(pth("max"), N.Round(v)) end))
    c:AddRow(N.MakeSlider(c, L["Icon size"], 8, 48, 1,
        function() return o.size end, function(v) N:Set(pth("size"), N.Round(v)) end))
    c:AddRow(N.MakeSlider(c, L["Spacing"], 0, 10, 1,
        function() return o.spacing end, function(v) N:Set(pth("spacing"), N.Round(v)) end))
    c:AddRow(N.MakeDropdown(c, L["Anchor"], {
        { value = "BOTTOMLEFT", text = L["Bottom left"] },
        { value = "BOTTOMRIGHT", text = L["Bottom right"] },
        { value = "TOPLEFT", text = L["Top left"] },
        { value = "TOPRIGHT", text = L["Top right"] },
        { value = "LEFT", text = L["Left"] },
        { value = "RIGHT", text = L["Right"] },
        { value = "TOP", text = L["Up"] },
        { value = "BOTTOM", text = L["Down"] },
        { value = "CENTER", text = L["Center"] },
    }, function() return o.point end, function(v) N:Set(pth("point"), v) end))
    c:AddRow(N.MakeDropdown(c, L["Growth direction"], {
        { value = "RIGHT", text = L["Right"] },
        { value = "LEFT", text = L["Left"] },
        { value = "UP", text = L["Up"] },
        { value = "DOWN", text = L["Down"] },
    }, function() return o.growth end, function(v) N:Set(pth("growth"), v) end))
    c:AddRow(N.MakeSlider(c, L["X offset"], -40, 40, 1,
        function() return o.x end, function(v) N:Set(pth("x"), N.Round(v)) end))
    c:AddRow(N.MakeSlider(c, L["Y offset"], -40, 40, 1,
        function() return o.y end, function(v) N:Set(pth("y"), N.Round(v)) end))
    if kind == "buffs" then
        c:AddRow(N.MakeCheckbox(c, L["Only my auras"],
            function() return o.onlyMine end, function(v) N:Set(pth("onlyMine"), v) end))
    elseif kind == "dispels" then
        c:AddRow(N.MakeCheckbox(c, L["Only what I can dispel"],
            function() return o.dispellableOnly ~= false end, function(v) N:Set(pth("dispellableOnly"), v) end))
        c:AddRow(N.MakeCheckbox(c, L["Show spell icons"],
            function() return o.showIcons end, function(v) N:Set(pth("showIcons"), v) end))
    elseif kind == "debuffs" then
        c:AddRow(N.MakeCheckbox(c, L["Dispel-type border"],
            function() return o.dispelBorder end, function(v) N:Set(pth("dispelBorder"), v) end))
        local npo = N.MakeCheckbox(c, L["NONPLAYER_ONLY"],
            function() return o.onlyNonPlayer ~= false end, function(v) N:Set(pth("onlyNonPlayer"), v) end)
        N.SetTip(npo, L["NONPLAYER_ONLY"], L["NONPLAYER_ONLY_TIP"])
        c:AddRow(npo)
    elseif kind == "crowdControls" then
        c:AddRow(N.MakeCheckbox(c, L["Only what I can dispel"],
            function() return o.dispellableOnly end, function(v) N:Set(pth("dispellableOnly"), v) end))
    end
    p:AddCard(c)

    if kind == "debuffs" then
        local fc = N.MakeCard(p, L["Filter"])
        fc:AddRow(N.MakeCheckbox(fc, L["Show all debuffs"],
            function() return o.showAll end, function(v) N:Set(pth("showAll"), v) end))
        fc:AddRow(N.MakeDropdown(fc, L["Match"], {
            { value = "any", text = L["Any ticked filter"] },
            { value = "all", text = L["All ticked filters"] },
        }, function() return o.match end, function(v) N:Set(pth("match"), v) end))
        for _, flt in ipairs(N.Auras.DEBUFF_FILTERS) do
            local cb = N.MakeCheckbox(fc, L["DFILTER_" .. flt.key],
                function() return o.filters[flt.key] end,
                function(v) N:Set(pth("filters." .. flt.key), v) end)
            N.SetTip(cb, L["DFILTER_" .. flt.key], L["DFILTER_TIP_" .. flt.key])
            fc:AddRow(cb)
        end
        local note = N.FontString(fc, 11)
        note:SetPoint("TOPLEFT", fc, "TOPLEFT", N.CARD_PAD, fc._y)
        note:SetWidth(fc:GetWidth() - 2 * N.CARD_PAD)
        note:SetJustifyH("LEFT")
        note:SetTextColor(uc(M.color.textDim))
        note:SetText(L["DFILTER_NOTE"])
        note:SetHeight(note:GetStringHeight() + 4)
        fc:SetHeight(-fc._y + note:GetHeight() + N.CARD_PAD)
        p:AddCard(fc)
    end

    if kind == "dispels" then
        local hc = N.MakeCard(p, L["Highlight"])
        hc:AddRow(N.MakeDropdown(hc, L["Highlight type"], {
            { value = "none", text = L["None"] },
            { value = "edge-top", text = L["Gradient - top"] },
            { value = "edge-bottom", text = L["Gradient - bottom"] },
            { value = "fill", text = L["Current health"] },
            { value = "full", text = L["Entire frame"] },
        }, function() return o.highlightType end, function(v) N:Set(pth("highlightType"), v) end))
        hc:AddRow(N.MakeSlider(hc, L["Opacity"], 5, 100, 5,
            function() return o.highlightOpacity end, function(v) N:Set(pth("highlightOpacity"), N.Round(v)) end))
        p:AddCard(hc)

        local bc = N.MakeCard(p, L["Border"])
        bc:AddRow(N.MakeCheckbox(bc, L["Show border"],
            function() return o.frameBorder end, function(v) N:Set(pth("frameBorder"), v) end))
        bc:AddRow(N.MakeSlider(bc, L["Thickness"], 1, 8, 1,
            function() return o.frameBorderThickness end, function(v) N:Set(pth("frameBorderThickness"), N.Round(v)) end))
        p:AddCard(bc)

        local ic = N.MakeCard(p, L["Dispel type icons"])
        ic:AddRow(N.MakeCheckbox(ic, L["Enabled"],
            function() return o.typeIcons end, function(v) N:Set(pth("typeIcons"), v) end))
        ic:AddRow(N.MakeSlider(ic, L["Icon size"], 6, 32, 1,
            function() return o.typeIconSize end, function(v) N:Set(pth("typeIconSize"), N.Round(v)) end))
        ic:AddRow(N.MakeDropdown(ic, L["Anchor"], {
            { value = "BOTTOMLEFT", text = L["Bottom left"] },
            { value = "BOTTOMRIGHT", text = L["Bottom right"] },
            { value = "TOPLEFT", text = L["Top left"] },
            { value = "TOPRIGHT", text = L["Top right"] },
            { value = "CENTER", text = L["Center"] },
        }, function() return o.typeIconPoint end, function(v) N:Set(pth("typeIconPoint"), v) end))
        ic:AddRow(N.MakeDropdown(ic, L["Growth direction"], {
            { value = "RIGHT", text = L["Right"] },
            { value = "LEFT", text = L["Left"] },
            { value = "UP", text = L["Up"] },
            { value = "DOWN", text = L["Down"] },
        }, function() return o.typeIconGrowth end, function(v) N:Set(pth("typeIconGrowth"), v) end))
        ic:AddRow(N.MakeSlider(ic, L["X offset"], -40, 40, 1,
            function() return o.typeIconX end, function(v) N:Set(pth("typeIconX"), N.Round(v)) end))
        ic:AddRow(N.MakeSlider(ic, L["Y offset"], -40, 40, 1,
            function() return o.typeIconY end, function(v) N:Set(pth("typeIconY"), N.Round(v)) end))
        p:AddCard(ic)

        local cc = N.MakeCard(p, L["Dispel type colors"])
        local TYPE_DEFAULT = { Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 },
                               Poison = { 0, 0.6, 0 }, Bleed = { 1, 0.2, 0.6 } }
        for _, token in ipairs({ "Magic", "Curse", "Disease", "Poison", "Bleed" }) do
            local row = N.MakeColorPicker(cc, L["DTYPE_" .. token],
                function() return (o.typeColors and o.typeColors[token]) or TYPE_DEFAULT[token] end,
                function(v) N:Set(pth("typeColors." .. token), v) end)
            local reset = CreateFrame("Button", nil, row)
            reset:SetSize(56, 18)
            reset:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            N.SkinButton(reset)
            local rfs = N.FontString(reset, 11)
            rfs:SetPoint("CENTER")
            rfs:SetText(L["Reset"])
            reset:SetScript("OnClick", function()
                local d = TYPE_DEFAULT[token]
                N:Set(pth("typeColors." .. token), { d[1], d[2], d[3] })
                row.Refresh()
            end)
            cc:AddRow(row)
        end
        p:AddCard(cc)
    end

    -- Own cards for the countdown (animation + time text) and the stack count.
    -- Dispellable debuffs show no icons of their own by default, so no such cards.
    if kind == "dispels" then return end
    local tc = N.MakeCard(p, L["Time"])
    tc:AddRow(N.MakeCheckbox(tc, L["Show cooldown animation"],
        function() return o.showCooldown end, function(v) N:Set(pth("showCooldown"), v) end))
    tc:AddRow(N.MakeDropdown(tc, L["Animation style"], {
        { value = "vertical", text = L["Top to bottom"] },
        { value = "spiral", text = L["Spiral"] },
    }, function() return o.cdStyle or "spiral" end, function(v) N:Set(pth("cdStyle"), v) end))
    tc:AddRow(N.MakeCheckbox(tc, L["Show time on icon"],
        function() return o.showTime end, function(v) N:Set(pth("showTime"), v) end))
    tc:AddRow(N.MakeSlider(tc, L["Size"], 6, 24, 1,
        function() return o.timeSize end, function(v) N:Set(pth("timeSize"), N.Round(v)) end))
    tc:AddRow(N.MakeSlider(tc, L["X offset"], -30, 30, 1,
        function() return o.timeX end, function(v) N:Set(pth("timeX"), N.Round(v)) end))
    tc:AddRow(N.MakeSlider(tc, L["Y offset"], -30, 30, 1,
        function() return o.timeY end, function(v) N:Set(pth("timeY"), N.Round(v)) end))
    p:AddCard(tc)

    local sc = N.MakeCard(p, L["Stacks"])
    sc:AddRow(N.MakeCheckbox(sc, L["Show stacks"],
        function() return o.showStacks end, function(v) N:Set(pth("showStacks"), v) end))
    sc:AddRow(N.MakeSlider(sc, L["Size"], 6, 24, 1,
        function() return o.stackSize end, function(v) N:Set(pth("stackSize"), N.Round(v)) end))
    sc:AddRow(N.MakeSlider(sc, L["X offset"], -30, 30, 1,
        function() return o.stackX end, function(v) N:Set(pth("stackX"), N.Round(v)) end))
    sc:AddRow(N.MakeSlider(sc, L["Y offset"], -30, 30, 1,
        function() return o.stackY end, function(v) N:Set(pth("stackY"), N.Round(v)) end))
    p:AddCard(sc)

    -- Cooldown rows: which spells count. When the game shows an aura's spell ID
    -- this list decides; when it hides the ID, Blizzard's own classification is
    -- used (defensives / externals) if the checkbox is on.
    if kind == "defensives" or kind == "externals" or kind == "offensives" or kind == "buffs" then
        local lc = N.MakeCard(p, L["Spell list"])
        local relayout
        if kind == "buffs" then
            lc:AddRow(N.MakeCheckbox(lc, L["Only the spells below"],
                function() return o.useList end, function(v) N:Set(pth("useList"), v) end))
            lc:AddRow(N.MakeCheckbox(lc, L["Show all classes"],
                function() return o.pickAll end,
                function(v) N:Set(pth("pickAll"), v); if relayout then relayout() end end))
        elseif kind ~= "offensives" then
            lc:AddRow(N.MakeCheckbox(lc, L["Use Blizzard classification when the spell is hidden"],
                function() return o.useFilter end, function(v) N:Set(pth("useFilter"), v) end))
        end
        local note = N.FontString(lc, 11)
        note:SetPoint("TOPLEFT", lc, "TOPLEFT", N.CARD_PAD, lc._y)
        note:SetWidth(lc:GetWidth() - 2 * N.CARD_PAD)
        note:SetJustifyH("LEFT")
        note:SetTextColor(uc(M.color.textDim))
        note:SetText(kind == "offensives" and L["SPELLLIST_NOTE_OFFENSIVE"]
            or kind == "buffs" and L["SPELLLIST_NOTE_BUFFS"] or L["SPELLLIST_NOTE"])
        note:SetHeight(note:GetStringHeight() + 4)
        lc._y = lc._y - note:GetHeight() - 8
        lc:SetHeight(-lc._y + N.CARD_PAD)

        -- Every known spell of this row as an icon; ticked = shown. The saved
        -- list holds only the ticked IDs. Your own IDs are appended as extra icons.
        local function parse(str)
            local out = {}
            for tok in (str or ""):gmatch("%d+") do out[#out + 1] = tonumber(tok) end
            return out
        end
        local function baseIDs()
            local pool = N.SpellPool and N.SpellPool[kind]
            return pool or parse(N.Defaults.party.auras[kind].list)
        end
        local items, known = {}, {}
        for _, id in ipairs(baseIDs()) do
            if not known[id] then known[id] = true; items[#items + 1] = id end
        end
        local function addCustoms()
            for _, id in ipairs(parse(o.list)) do
                if not known[id] then known[id] = true; items[#items + 1] = id end
            end
        end
        addCustoms()
        local on = {}
        local function loadOn()
            on = {}
            for _, id in ipairs(parse(o.list)) do on[id] = true end
        end
        loadOn()
        local function save()
            local ids = {}
            for _, id in ipairs(items) do if on[id] then ids[#ids + 1] = id end end
            N:Set(pth("list"), table.concat(ids, ","))
        end

        local CELL, GAP, HEAD = 30, 4, 18
        local grid = CreateFrame("Frame", nil, lc)
        local cells, heads = {}, {}
        local function paint(btn)
            local state = false
            for _, id in ipairs(btn.ids) do if on[id] then state = true end end
            btn.tex:SetDesaturated(not state)
            btn.tex:SetAlpha(state and 1 or 0.35)
            N.SetPanelBorder(btn, state and M.color.accent or M.color.line)
        end
        local function cell(i)
            local btn = cells[i]
            if btn then return btn end
            btn = CreateFrame("Button", nil, grid)
            btn:SetSize(CELL, CELL)
            N.SkinPanel(btn, M.color.base, M.color.line, true)
            btn.tex = btn:CreateTexture(nil, "ARTWORK")
            btn.tex:SetPoint("TOPLEFT", 2, -2)
            btn.tex:SetPoint("BOTTOMRIGHT", -2, 2)
            btn.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn:SetScript("OnClick", function(s)
                local any = false
                for _, id in ipairs(s.ids) do if on[id] then any = true end end
                for _, id in ipairs(s.ids) do on[id] = (not any) or nil end
                paint(s)
                save()
            end)
            btn:SetScript("OnEnter", function(s)
                GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, s.ids[1])
                if not ok then GameTooltip:SetText(tostring(s.ids[1])) end
                GameTooltip:AddLine("ID " .. table.concat(s.ids, ", "), 0.6, 0.6, 0.6)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            cells[i] = btn
            return btn
        end
        local function head(i)
            local fs = heads[i]
            if not fs then
                fs = N.FontString(grid, 11)
                heads[i] = fs
            end
            return fs
        end
        local classNames = LOCALIZED_CLASS_NAMES_MALE or {}
        local function layoutGrid()
            local w = lc:GetWidth() - 2 * N.CARD_PAD
            local cols = math.max(1, math.floor((w + GAP) / (CELL + GAP)))
            local byClass, order = {}, {}
            for _, id in ipairs(items) do
                local cls = N.SpellClass and N.SpellClass[id] or "GENERAL"
                local hide = kind == "buffs" and not o.pickAll and cls ~= "GENERAL" and cls ~= select(2, UnitClass("player"))
                -- Forever: a rank this client does not know has no icon - leave it out.
                local known = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
                if not hide and known and known ~= 134400 then
                local tex = known
                local bucket = byClass[cls]
                if not bucket then
                    bucket = { list = {}, byTex = {} }
                    byClass[cls] = bucket
                    order[#order + 1] = cls
                end
                local g = bucket.byTex[tex]
                if not g then
                    g = { ids = {}, tex = tex }
                    bucket.byTex[tex] = g
                    bucket.list[#bucket.list + 1] = g
                end
                g.ids[#g.ids + 1] = id
                end
            end
            table.sort(order, function(a, b)
                if a == "GENERAL" then return false end
                if b == "GENERAL" then return true end
                return (classNames[a] or a) < (classNames[b] or b)
            end)
            local y, ci, hi = 0, 0, 0
            for _, cls in ipairs(order) do
                hi = hi + 1
                local fs = head(hi)
                fs:ClearAllPoints()
                fs:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -y)
                local name = (cls == "GENERAL") and L["General"] or (classNames[cls] or cls)
                local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
                fs:SetText(name)
                if cc then fs:SetTextColor(cc.r, cc.g, cc.b) else fs:SetTextColor(uc(M.color.textDim)) end
                fs:Show()
                y = y + HEAD
                local list = byClass[cls].list
                for i, g in ipairs(list) do
                    ci = ci + 1
                    local btn = cell(ci)
                    btn.ids = g.ids
                    btn.tex:SetTexture(type(g.tex) == "number" and g.tex or 134400)
                    btn:ClearAllPoints()
                    btn:SetPoint("TOPLEFT", grid, "TOPLEFT",
                        ((i - 1) % cols) * (CELL + GAP), -(y + math.floor((i - 1) / cols) * (CELL + GAP)))
                    paint(btn)
                    btn:Show()
                end
                y = y + math.ceil(#list / cols) * (CELL + GAP) + 4
            end
            for i = ci + 1, #cells do cells[i]:Hide() end
            for i = hi + 1, #heads do heads[i]:Hide() end
            local h = math.max(1, y - 4)
            local delta = h - (grid._h or 0)
            grid._h = h
            grid:SetHeight(h)
            if grid._added then
                lc:SetHeight(lc:GetHeight() + delta)
                p:SetHeight(p:GetHeight() + delta)
                if N.OptionsResize then N.OptionsResize(p) end
            end
        end

        local addBox = N.MakeTextInput(lc, L["Add spell ID"], function() return "" end, function(v)
            local id = tonumber(v)
            if not id or id <= 0 then return end
            if not known[id] then known[id] = true; items[#items + 1] = id end
            on[id] = true
            save()
            layoutGrid()
        end)
        lc:AddRow(addBox)
        lc:AddRow(ActionButton(lc, L["Reset to default list"], function()
            N:Set(pth("list"), N.Defaults.party.auras[kind].list)
            items, known = {}, {}
            for _, id in ipairs(baseIDs()) do
                known[id] = true
                items[#items + 1] = id
            end
            loadOn()
            layoutGrid()
        end))

        relayout = layoutGrid
        layoutGrid()
        grid._rowHeight = grid._h
        lc:AddRow(grid)
        grid._added = true
        p:AddCard(lc)
    end
end

-- Actions page: global (not per party/raid). The list of spells that trigger a frame animation,
-- each with its animation and color; rebuilt in place when an entry is added or removed.
local function BuildActions(p)
    if N.Preview and not p.previewHost then p.previewHost = N.Preview.Create(p, "actions") end
    for _, child in ipairs({ p:GetChildren() }) do
        if child ~= p.previewHost then
            child:Hide()
            child:SetParent(nil)
        end
    end
    p._y = -4

    local cfg = N.db.actions
    local function touch()
        N:Fire("NUCLEUS_SETTING_CHANGED", "actions", "actions.list")
    end
    local function rebuild()
        BuildActions(p)
        if scrollChild then scrollChild:SetHeight(math.max(p:GetHeight(), 10) + 8) end
    end

    local c = N.MakeCard(p, L["Actions"])
    c:AddRow(N.MakeCheckbox(c, L["Enabled"],
        function() return cfg.enabled end, function(v) N:Set("actions.enabled", v) end))
    c:AddRow(N.MakeSlider(c, L["Animation speed"], 0.5, 3, 0.1,
        function() return cfg.speed end, function(v) N:Set("actions.speed", v) end))
    local hint = N.FontString(c, 11)
    hint:SetPoint("TOPLEFT", c, "TOPLEFT", N.CARD_PAD, c._y)
    hint:SetWidth(c:GetWidth() - 2 * N.CARD_PAD)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(uc(M.color.textDim))
    hint:SetText(L["ACTIONS_HINT"] .. "\n\n|cffffaa33" .. L["ACTIONS_SECRET_WARN"] .. "|r")
    hint:SetHeight(hint:GetStringHeight() + 4)
    c:SetHeight(-c._y + hint:GetHeight() + N.CARD_PAD)
    p:AddCard(c)

    local list = N.MakeCard(p, L["Spells"])
    local animOpts = {
        { value = "sweep", text = L["Sweep up"] },
        { value = "wipe",  text = L["Wipe across"] },
        { value = "rise",  text = L["Rising icon"] },
    }
    for i, entry in ipairs(cfg.list) do
        local row = CreateFrame("Frame", nil, list)
        row._rowHeight = 42

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(22, 22)
        icon:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local tex = entry.spell and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(entry.spell)
        icon:SetTexture(tex or 134400)

        local idBox = N.MakeTextInput(row, nil,
            function() return entry.spell and tostring(entry.spell) or "" end,
            function(v)
                local n = tonumber(v)
                if n and n ~= entry.spell then
                    entry.spell = n
                    touch()
                    rebuild()
                end
            end)
        idBox:SetParent(row)
        idBox:ClearAllPoints()
        idBox:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        idBox:SetSize(84, 24)

        local anim = N.MakeDropdown(row, nil, animOpts,
            function() return entry.anim end,
            function(v) entry.anim = v; touch() end)
        anim:SetParent(row)
        anim:ClearAllPoints()
        anim:SetPoint("LEFT", idBox, "RIGHT", 6, 0)
        anim:SetSize(130, 24)

        local sw = CreateFrame("Button", nil, row)
        sw:SetSize(34, 20)
        sw:SetPoint("LEFT", anim, "RIGHT", 6, 0)
        N.SkinRound(sw, M.color.base, M.color.line, true)
        local fill = sw._nucFill
        local col = entry.color or { 1, 1, 1 }
        fill:SetColorTexture(col[1], col[2], col[3])
        sw:SetScript("OnEnter", function() N.SetPanelBorder(sw, M.color.accent) end)
        sw:SetScript("OnLeave", function() N.SetPanelBorder(sw, M.color.line) end)
        sw:SetScript("OnClick", function()
            local cc = entry.color or { 1, 1, 1 }
            N.ColorPicker:Open({
                r = cc[1], g = cc[2], b = cc[3], title = L["Color"],
                onChange = function(r, g, b) fill:SetColorTexture(r, g, b) end,
                onAccept = function(r, g, b)
                    entry.color = { r, g, b }
                    fill:SetColorTexture(r, g, b)
                    touch()
                end,
                onCancel = function()
                    local o = entry.color or { 1, 1, 1 }
                    fill:SetColorTexture(o[1], o[2], o[3])
                end,
            })
        end)

        local test = CreateFrame("Button", nil, row)
        test:SetSize(46, 22)
        test:SetPoint("LEFT", sw, "RIGHT", 6, 0)
        N.SkinButton(test)
        local tfs = N.FontString(test, 11)
        tfs:SetPoint("CENTER")
        tfs:SetText(L["Test"])
        test:SetScript("OnClick", function() N.Actions.Test(entry) end)

        local del = CreateFrame("Button", nil, row)
        del:SetSize(24, 22)
        del:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2)
        N.SkinRound(del, M.color.base, M.color.line, true)
        local tint = N.MakeCross(del, 9, 2)
        tint(uc(M.color.textDim))
        del:SetScript("OnEnter", function()
            del._nucFill:SetColorTexture(0.80, 0.22, 0.22, 1)
            tint(1, 1, 1, 1)
        end)
        del:SetScript("OnLeave", function()
            del._nucFill:SetColorTexture(uc(M.color.base))
            tint(uc(M.color.textDim))
        end)
        del:SetScript("OnClick", function()
            table.remove(cfg.list, i)
            touch()
            rebuild()
        end)

        local nameFS = N.FontString(row, 11)
        nameFS:SetPoint("TOPLEFT", row, "TOPLEFT", 28, -28)
        nameFS:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetWordWrap(false)
        local sname = entry.spell and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(entry.spell)
        nameFS:SetTextColor(uc(sname and M.color.textDim or { 0.85, 0.45, 0.45, 1 }))
        nameFS:SetText(sname or L["Unknown spell"])

        list:AddRow(row)
    end
    list:AddRow(ActionButton(list, "+  " .. L["Add action"], function()
        table.insert(cfg.list, { spell = 6262, anim = "sweep", color = { 1, 1, 1 } })
        touch()
        rebuild()
    end))
    p:AddCard(list)
end

local function BuildTools(p, kind)
    local o = N.db.tools[kind]
    local function pth(f) return "tools." .. kind .. "." .. f end
    local titles = { readyPull = "Ready & Pull", battleRes = "Battle Res", marks = "Marks" }

    local pos = N.MakeCard(p, L["Position"])
    local mv = CreateFrame("Button", nil, pos)
    mv._rowHeight = 28
    N.SkinButton(mv)
    local mvText = N.FontString(mv, 12)
    mvText:SetPoint("CENTER")
    local function mvPaint()
        local on = N.Tools and N.Tools.moving
        mvText:SetText(on and L["Lock tools"] or L["Move tools"])
        mv:SetActiveState(on and true or false)
    end
    mv:SetScript("OnClick", function()
        N.Tools.SetMoving(not N.Tools.moving)
        mvPaint()
    end)
    mvPaint()
    pos:AddRow(mv)
    p:AddCard(pos)

    local c = N.MakeCard(p, L[titles[kind]])
    c:AddRow(N.MakeCheckbox(c, L["Enabled"],
        function() return o.enabled end, function(v) N:Set(pth("enabled"), v) end))

    local function addHint()
        local hint = N.FontString(c, 11)
        hint:SetPoint("TOPLEFT", c, "TOPLEFT", N.CARD_PAD, c._y)
        hint:SetWidth(c:GetWidth() - 2 * N.CARD_PAD)
        hint:SetJustifyH("LEFT")
        hint:SetTextColor(uc(M.color.textDim))
        hint:SetText(L["TOOLS_HINT"])
        hint:SetHeight(hint:GetStringHeight() + 4)
        c:SetHeight(-c._y + hint:GetHeight() + N.CARD_PAD)
    end

    local orient = {
        { value = "horizontal", text = L["Horizontal"] },
        { value = "vertical", text = L["Vertical"] },
    }
    if kind == "readyPull" then
        c:AddRow(N.MakeCheckbox(c, L["Show Ready button"],
            function() return o.showReady end, function(v) N:Set(pth("showReady"), v) end))
        c:AddRow(N.MakeCheckbox(c, L["Show Pull button"],
            function() return o.showPull end, function(v) N:Set(pth("showPull"), v) end))
        c:AddRow(N.MakeCheckbox(c, L["Only for leader / assistants"],
            function() return o.onlyLeader end, function(v) N:Set(pth("onlyLeader"), v) end))
        c:AddRow(N.MakeDropdown(c, L["Orientation"], orient,
            function() return o.orientation end, function(v) N:Set(pth("orientation"), v) end))
        c:AddRow(N.MakeSlider(c, L["Button width"], 40, 140, 1,
            function() return o.width end, function(v) N:Set(pth("width"), N.Round(v)) end))
        c:AddRow(N.MakeSlider(c, L["Button height"], 16, 40, 1,
            function() return o.height end, function(v) N:Set(pth("height"), N.Round(v)) end))
        c:AddRow(N.MakeSlider(c, L["Spacing"], 0, 20, 1,
            function() return o.gap end, function(v) N:Set(pth("gap"), N.Round(v)) end))
        addHint()
        p:AddCard(c)

        local pc = N.MakeCard(p, L["Pull Timer"])
        pc:AddRow(N.MakeSlider(pc, L["Pull time (seconds)"], 3, 30, 1,
            function() return o.pullTime end, function(v) N:Set(pth("pullTime"), N.Round(v)) end))
        pc:AddRow(N.MakeDropdown(pc, L["Pull method"], {
            { value = "default", text = L["Blizzard countdown"] },
            { value = "dbm", text = "DBM" },
            { value = "bw", text = "BigWigs" },
            { value = "mrt", text = "MRT" },
        }, function() return o.pullMethod end, function(v) N:Set(pth("pullMethod"), v) end))
        p:AddCard(pc)
    elseif kind == "battleRes" then
        c:AddRow(N.MakeSlider(c, L["Icon size"], 16, 64, 1,
            function() return o.iconSize end, function(v) N:Set(pth("iconSize"), N.Round(v)) end))
        c:AddRow(N.MakeCheckbox(c, L["Show recharge timer"],
            function() return o.showTimer end, function(v) N:Set(pth("showTimer"), v) end))
        addHint()
        p:AddCard(c)
    else
        c:AddRow(N.MakeDropdown(c, L["Markers"], {
            { value = "target", text = L["Target markers"] },
            { value = "world", text = L["World markers"] },
            { value = "both", text = L["Both"] },
        }, function() return o.mode end, function(v) N:Set(pth("mode"), v) end))
        c:AddRow(N.MakeCheckbox(c, L["Only for leader / assistants"],
            function() return o.onlyLeader end, function(v) N:Set(pth("onlyLeader"), v) end))
        c:AddRow(N.MakeCheckbox(c, L["Show clear button"],
            function() return o.showClear end, function(v) N:Set(pth("showClear"), v) end))
        c:AddRow(N.MakeDropdown(c, L["Orientation"], orient,
            function() return o.orientation end, function(v) N:Set(pth("orientation"), v) end))
        c:AddRow(N.MakeSlider(c, L["Size"], 14, 40, 1,
            function() return o.size end, function(v) N:Set(pth("size"), N.Round(v)) end))
        c:AddRow(N.MakeSlider(c, L["Spacing"], 0, 10, 1,
            function() return o.spacing end, function(v) N:Set(pth("spacing"), N.Round(v)) end))
        addHint()
        p:AddCard(c)
    end

end

-- Custom indicators: one options page per entry (Indicators > the entry in the
-- rail), plus the "+" in the rail that creates one. See Frames/CustomIndicators.lua.
local CUSTOM_ANCHORS = {
    { value = "BOTTOMLEFT", text = "Bottom left" }, { value = "BOTTOMRIGHT", text = "Bottom right" },
    { value = "TOPLEFT", text = "Top left" }, { value = "TOPRIGHT", text = "Top right" },
    { value = "LEFT", text = "Left" }, { value = "RIGHT", text = "Right" },
    { value = "TOP", text = "Up" }, { value = "BOTTOM", text = "Down" }, { value = "CENTER", text = "Center" },
}

local function customAnchorOptions()
    local out = {}
    for _, a in ipairs(CUSTOM_ANCHORS) do out[#out + 1] = { value = a.value, text = L[a.text] } end
    return out
end

local function customEntryIndex(mode, id)
    for i, e in ipairs(N.db[mode].customIndicators or {}) do
        if e.id == id then return i, e end
    end
end

local function BuildCustom(p, mode, id)
    local _, entry = customEntryIndex(mode, id)
    if not entry then return end
    if N.Preview then p.previewHost = N.Preview.Create(p, "custom", id) end

    local function set(f, v)
        entry[f] = v
        N:Fire("NUCLEUS_SETTING_CHANGED", mode, mode .. ".customIndicators." .. id .. "." .. f, v)
    end
    local function checkbox(card, label, f)
        card:AddRow(N.MakeCheckbox(card, label, function() return entry[f] end, function(v) set(f, v) end))
    end
    local function slider(card, label, f, lo, hi, step)
        card:AddRow(N.MakeSlider(card, label, lo, hi, step or 1,
            function() return entry[f] end, function(v) set(f, step and v or N.Round(v)) end))
    end
    local function color(card, label)
        card:AddRow(N.MakeColorPicker(card, label,
            function() return entry.color end, function(v) set("color", v) end))
    end
    local function position(card)
        card:AddRow(N.MakeDropdown(card, L["Anchor"], customAnchorOptions(),
            function() return entry.point end, function(v) set("point", v) end))
        slider(card, L["X offset"], "x", -60, 60)
        slider(card, L["Y offset"], "y", -60, 60)
    end

    local function body()
        for _, child in ipairs({ p:GetChildren() }) do
            if child ~= p.previewHost then child:Hide(); child:SetParent(nil) end
        end
        p._y = -4

        local head = N.MakeCard(p, entry.name)
        checkbox(head, L["Enabled"], "enabled")
        head:AddRow(N.MakeTextInput(head, L["Name"], function() return entry.name end, function(v)
            v = strtrim(v or "")
            if v ~= "" and v ~= entry.name then
                set("name", v)
                if N.RefreshCustomRail then N.RefreshCustomRail() end
            end
        end))

        head:AddRow(ActionButton(head, L["Delete indicator"], function()
            N.Dialog.Confirm(L["CI_DELETE_CONFIRM"]:format(entry.name), function()
                if N.DeleteCustomIndicator then N.DeleteCustomIndicator(mode, id) end
            end)
        end))
        p:AddCard(head)

        local track = N.MakeCard(p, L["Tracking"])
        track:AddRow(N.MakeDropdown(track, L["Watch for"], {
            { value = "buff", text = L["Buffs"] },
            { value = "debuff", text = L["Debuffs"] },
        }, function() return entry.aura end, function(v) set("aura", v) end))
        checkbox(track, L["Only my auras"], "mine")
        if entry.aura == "buff" then
            checkbox(track, L["Remove from Buffs"], "hideFromBuffs")
        end

        -- Suggested spells (your class first, other classes on request) as
        -- icons to tick; spells added by hand show up as ticked icons too.
        local items, known, on = {}, {}, {}
        local function add(sid) if not known[sid] then known[sid] = true; items[#items + 1] = sid end end
        for _, sid in ipairs(N.CustomIndicators.Suggestions(entry.aura)) do add(sid) end
        for tok in (entry.spells or ""):gmatch("%d+") do
            local sid = tonumber(tok)
            on[sid] = true
            add(sid)
        end
        local function save()
            local out = {}
            for _, sid in ipairs(items) do if on[sid] then out[#out + 1] = sid end end
            set("spells", table.concat(out, ","))
        end

        if #items > 0 then
            track:AddRow(N.MakeCheckbox(track, L["Show all classes"], function() return entry.pickAll end,
                function(v) set("pickAll", v); body(); if N.OptionsResize then N.OptionsResize(p) end end))
        end

        local CELL, GAP, HEAD = 30, 4, 18
        local grid = CreateFrame("Frame", nil, track)
        local playerClass = select(2, UnitClass("player"))
        local classNames = LOCALIZED_CLASS_NAMES_MALE or {}
        local w = track:GetWidth() - 2 * N.CARD_PAD
        local cols = math.max(1, math.floor((w + GAP) / (CELL + GAP)))
        local byClass, order = {}, {}
        for _, sid in ipairs(items) do
            local cls = N.SpellClass and N.SpellClass[sid] or playerClass
            local real = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(sid)
            -- Forever: an ID this client does not know shows a "?" - leave it out unless ticked.
            local unknown = (not real) or real == 134400
            if (entry.pickAll or on[sid] or cls == playerClass) and (on[sid] or not unknown) then
                local tex = real or ("id" .. sid)
                local bucket = byClass[cls]
                if not bucket then bucket = { list = {}, byTex = {} }; byClass[cls] = bucket; order[#order + 1] = cls end
                local g = bucket.byTex[tex]
                if not g then g = { ids = {}, tex = tex }; bucket.byTex[tex] = g; bucket.list[#bucket.list + 1] = g end
                g.ids[#g.ids + 1] = sid
            end
        end
        table.sort(order, function(x, y)
            if x == playerClass then return y ~= playerClass end
            if y == playerClass then return false end
            return (classNames[x] or x) < (classNames[y] or y)
        end)
        local y = 0
        for _, cls in ipairs(order) do
            local hd = N.FontString(grid, 11)
            hd:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -y)
            local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
            hd:SetText(classNames[cls] or cls)
            if cc then hd:SetTextColor(cc.r, cc.g, cc.b) else hd:SetTextColor(uc(M.color.textDim)) end
            y = y + HEAD
            local list = byClass[cls].list
            for i, g in ipairs(list) do
                local btn = CreateFrame("Button", nil, grid)
                btn:SetSize(CELL, CELL)
                btn:SetPoint("TOPLEFT", grid, "TOPLEFT",
                    ((i - 1) % cols) * (CELL + GAP), -(y + math.floor((i - 1) / cols) * (CELL + GAP)))
                N.SkinPanel(btn, M.color.base, M.color.line, true)
                local tx = btn:CreateTexture(nil, "ARTWORK")
                tx:SetPoint("TOPLEFT", 2, -2)
                tx:SetPoint("BOTTOMRIGHT", -2, 2)
                tx:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                tx:SetTexture(type(g.tex) == "number" and g.tex or 134400)
                local function paint()
                    local state = false
                    for _, sid in ipairs(g.ids) do if on[sid] then state = true end end
                    tx:SetDesaturated(not state)
                    tx:SetAlpha(state and 1 or 0.35)
                    N.SetPanelBorder(btn, state and M.color.accent or M.color.line)
                end
                paint()
                btn:SetScript("OnClick", function()
                    local any = false
                    for _, sid in ipairs(g.ids) do if on[sid] then any = true end end
                    for _, sid in ipairs(g.ids) do on[sid] = (not any) or nil end
                    paint()
                    save()
                end)
                btn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, g.ids[1])
                    if not ok then GameTooltip:SetText(tostring(g.ids[1])) end
                    GameTooltip:AddLine("ID " .. table.concat(g.ids, ", "), 0.6, 0.6, 0.6)
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
            y = y + math.ceil(#list / cols) * (CELL + GAP) + 4
        end
        if #order > 0 then
            grid._rowHeight = math.max(1, y - 4)
            track:AddRow(grid)
        end

        track:AddRow(N.MakeTextInput(track, L["Add spell (ID or name)"], function() return "" end, function(v)
            v = strtrim(v or "")
            if v == "" then return end
            local sid = tonumber(v)
            if not sid then
                local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(v)
                sid = info and info.spellID
            end
            if not sid then N:Print(L["CI_SPELL_NOT_FOUND"]:format(v)); return end
            on[sid] = true
            add(sid)
            save()
            body()
            if N.OptionsResize then N.OptionsResize(p) end
        end))        local note = N.FontString(track, 11)
        note:SetPoint("TOPLEFT", track, "TOPLEFT", N.CARD_PAD, track._y)
        note:SetWidth(track:GetWidth() - 2 * N.CARD_PAD)
        note:SetJustifyH("LEFT")
        note:SetTextColor(uc(M.color.textDim))
        note:SetText(L["CI_TRACK_NOTE"])
        note:SetHeight(note:GetStringHeight() + 4)
        track:SetHeight(-track._y + note:GetHeight() + N.CARD_PAD)
        p:AddCard(track)

        local kind = entry.type
        local look = N.MakeCard(p, L["Appearance"])
        if kind == "icon" or kind == "icons" then
            slider(look, L["Icon size"], "size", 8, 48)
            if kind == "icons" then
                slider(look, L["Max icons"], "max", 1, 8)
                slider(look, L["Spacing"], "spacing", 0, 10)
                look:AddRow(N.MakeDropdown(look, L["Growth direction"], {
                    { value = "RIGHT", text = L["Right"] }, { value = "LEFT", text = L["Left"] },
                    { value = "UP", text = L["Up"] }, { value = "DOWN", text = L["Down"] },
                }, function() return entry.growth end, function(v) set("growth", v) end))
            end
            position(look)
        elseif kind == "text" then
            -- Older entries used a "stack count" mode: it is the text {stacks} now.
            if entry.textKind == "stacks" then entry.textKind = "fixed"; entry.text = "{stacks}" end
            look:AddRow(N.MakeDropdown(look, L["Text shows"], {
                { value = "fixed", text = L["Own text"] },
                { value = "duration", text = L["Remaining time"] },
            }, function() return entry.textKind end,
               function(v) set("textKind", v); body(); if N.OptionsResize then N.OptionsResize(p) end end))
            if entry.textKind ~= "duration" then
                look:AddRow(N.MakeTextInput(look, L["Text"], function() return entry.text end,
                    function(v) set("text", v) end))
                local hint = N.FontString(look, 11)
                hint:SetPoint("TOPLEFT", look, "TOPLEFT", N.CARD_PAD, look._y)
                hint:SetWidth(look:GetWidth() - 2 * N.CARD_PAD)
                hint:SetJustifyH("LEFT")
                hint:SetTextColor(uc(M.color.textDim))
                hint:SetText(L["CI_TEXT_HINT"])
                hint:SetHeight(hint:GetStringHeight() + 4)
                look._y = look._y - hint:GetHeight() - 8
                look:SetHeight(-look._y + N.CARD_PAD)
            end
            slider(look, L["Size"], "fontSize", 6, 32)
            color(look, L["Color"])
            position(look)
        elseif kind == "rect" or kind == "bar" then
            if kind == "bar" then
                look:AddRow(N.MakeDropdown(look, L["Bar runs"], {
                    { value = "left", text = L["Right to left"] },
                    { value = "right", text = L["Left to right"] },
                    { value = "down", text = L["Top to bottom"] },
                    { value = "up", text = L["Bottom to top"] },
                }, function() return entry.fill or "left" end, function(v) set("fill", v) end))
            end
            slider(look, L["Width"], "width", 2, 120)
            slider(look, L["Height"], "height", 2, 60)
            color(look, L["Color"])
            position(look)
        elseif kind == "color" or kind == "overlay" then
            look:AddRow(N.MakeDropdown(look, L["Fill"], {
                { value = "solid", text = L["Solid"] },
                { value = "class", text = L["Class color"] },
                { value = "gradient-v", text = L["Gradient top to bottom"] },
                { value = "gradient-h", text = L["Gradient left to right"] },
            }, function() return entry.colorMode or "solid" end,
               function(v) set("colorMode", v); body(); if N.OptionsResize then N.OptionsResize(p) end end))
            local areas = {}
            if kind == "color" then areas[#areas + 1] = { value = "free", text = L["Own size and position"] } end
            for _, a in ipairs({
                { value = "frame", text = L["The whole frame"] },
                { value = "health", text = L["Health bar"] },
                { value = "health-current", text = L["Filled part of the health bar"] },
                { value = "health-loss", text = L["Empty part of the health bar"] },
            }) do areas[#areas + 1] = a end
            look:AddRow(N.MakeDropdown(look, L["Area"], areas, function() return entry.colorArea or (kind == "overlay" and "health" or "free") end,
               function(v) set("colorArea", v); body(); if N.OptionsResize then N.OptionsResize(p) end end))
            local mode = entry.colorMode or "solid"
            if mode ~= "class" then color(look, L["Color"]) end
            if mode == "gradient-v" or mode == "gradient-h" then
                look:AddRow(N.MakeColorPicker(look, L["Second color"],
                    function() return entry.color2 end, function(v) set("color2", v) end))
            end
            slider(look, L["Opacity"], "opacity", 0.05, 1, 0.05)
            if kind == "color" and (entry.colorArea or "free") == "free" then
                slider(look, L["Width"], "width", 2, 200)
                slider(look, L["Height"], "height", 2, 120)
                position(look)
            end
        elseif kind == "glow" then
            local style = entry.glow or "pixel"
            look:AddRow(N.MakeDropdown(look, L["Glow style"], {
                { value = "pixel", text = L["GLOW_pixel"] },
                { value = "halo", text = L["GLOW_halo"] },
                { value = "pulse", text = L["GLOW_pulse"] },
            }, function() local v = entry.glow or "pixel"; if v == "autocast" then return "pixel" elseif v == "proc" then return "pulse" end return v end,
               function(v) set("glow", v); body(); if N.OptionsResize then N.OptionsResize(p) end end))
            color(look, L["Color"])
            if style == "autocast" then style = "pixel" elseif style == "proc" then style = "pulse" end
            if style == "pixel" then slider(look, L["Line length"], "length", 2, 30) end
            if style == "pixel" or style == "pulse" or style == "halo" then
                slider(look, L["Thickness"], "thickness", 1, 8)
            end
            slider(look, L["Speed"], "speed", 0.05, 1.5, 0.05)
            slider(look, L["Distance"], "offset", -6, 12)
        elseif kind == "border" then
            look:AddRow(N.MakeDropdown(look, L["Border around"], {
                { value = "frame", text = L["The whole frame"] },
                { value = "health", text = L["Health bar only"] },
            }, function() return entry.around or "frame" end, function(v) set("around", v) end))
            slider(look, L["Thickness"], "thickness", 1, 8)
            color(look, L["Color"])
        end
        p:AddCard(look)

        if kind == "icon" or kind == "icons" or kind == "rect" then
            local tc = N.MakeCard(p, L["Time"])
            checkbox(tc, L["Show cooldown animation"], "showCooldown")
            tc:AddRow(N.MakeDropdown(tc, L["Animation style"], {
                { value = "vertical", text = L["Top to bottom"] },
                { value = "spiral", text = L["Spiral"] },
            }, function() return entry.cdStyle or "spiral" end, function(v) set("cdStyle", v) end))
            checkbox(tc, L["Show time on icon"], "showTime")
            slider(tc, L["Size"], "timeSize", 6, 24)
            slider(tc, L["X offset"], "timeX", -30, 30)
            slider(tc, L["Y offset"], "timeY", -30, 30)
            p:AddCard(tc)

            local sc = N.MakeCard(p, L["Stacks"])
            checkbox(sc, L["Show stacks"], "showStacks")
            slider(sc, L["Size"], "stackSize", 6, 24)
            slider(sc, L["X offset"], "stackX", -30, 30)
            slider(sc, L["Y offset"], "stackY", -30, 30)
            p:AddCard(sc)
        end
    end
    body()
end

local function BuildTargetedSpellBars(p)
    local o = N.db.targetedSpellBars
    local function pth(f) return "targetedSpellBars." .. f end

    local c = N.MakeCard(p, L["Targeted Spell Bars"])
    c:AddRow(N.MakeCheckbox(c, L["Enabled"],
        function() return o.enabled end, function(v) N:Set(pth("enabled"), v) end))
    c:AddRow(N.MakeDropdown(c, L["Where to show"], {
        { value = "both", text = L["Everywhere"] },
        { value = "party", text = L["Party only"] },
        { value = "raid", text = L["Raid only"] },
    }, function() return o.where end, function(v) N:Set(pth("where"), v) end))
    c:AddRow(N.MakeSlider(c, L["Max bars"], 1, 10, 1,
        function() return o.num end, function(v) N:Set(pth("num"), N.Round(v)) end))
    c:AddRow(N.MakeDropdown(c, L["Orientation"], {
        { value = "top-to-bottom", text = L["Top to bottom"] },
        { value = "bottom-to-top", text = L["Bottom to top"] },
        { value = "left-to-right", text = L["Left to right"] },
        { value = "right-to-left", text = L["Right to left"] },
    }, function() return o.orientation end, function(v) N:Set(pth("orientation"), v) end))
    c:AddRow(N.MakeSlider(c, L["Bar width"], 120, 400, 1,
        function() return o.width end, function(v) N:Set(pth("width"), N.Round(v)) end))
    c:AddRow(N.MakeSlider(c, L["Bar height"], 14, 40, 1,
        function() return o.height end, function(v) N:Set(pth("height"), N.Round(v)) end))
    p:AddCard(c)

    local d = N.MakeCard(p, L["Display"])
    d:AddRow(N.MakeCheckbox(d, L["Show spell icon"],
        function() return o.showIcon end, function(v) N:Set(pth("showIcon"), v) end))
    d:AddRow(N.MakeCheckbox(d, L["Show spell name"],
        function() return o.showSpellName end, function(v) N:Set(pth("showSpellName"), v) end))
    d:AddRow(N.MakeCheckbox(d, L["Show target name"],
        function() return o.showTargetText end, function(v) N:Set(pth("showTargetText"), v) end))
    d:AddRow(N.MakeColorPicker(d, L["Cast color"],
        function() return o.color end, function(v) N:Set(pth("color"), v) end))
    d:AddRow(N.MakeColorPicker(d, L["Important cast color"],
        function() return o.importantColor end, function(v) N:Set(pth("importantColor"), v) end))
    p:AddCard(d)

    local pv = N.MakeCard(p, L["Preview"])
    pv:AddRow(ActionButton(pv, L["Toggle Preview"], function()
        N.TargetedSpellBars.SetPreview(not N.TargetedSpellBars.IsPreviewing())
    end))
    local hint = N.FontString(pv, 11)
    hint:SetPoint("TOPLEFT", pv, "TOPLEFT", N.CARD_PAD, pv._y)
    hint:SetWidth(pv:GetWidth() - 2 * N.CARD_PAD)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(uc(M.color.textDim))
    hint:SetText(L["TSB_HINT"])
    hint:SetHeight(hint:GetStringHeight() + 4)
    pv:SetHeight(-pv._y + hint:GetHeight() + N.CARD_PAD)
    p:AddCard(pv)
end

local KIND_OPTS = {
    { value = "none", text = L["None"] },
    { value = "spell", text = L["Spell"] },
    { value = "item", text = L["Item"] },
    { value = "macro", text = L["Macro"] },
    { value = "general", text = L["General"] },
}

local GENERAL_OPTS = {
    { value = "target", text = L["Target"] },
    { value = "focus", text = L["Focus"] },
    { value = "menu", text = L["Menu"] },
    { value = "assist", text = L["Assist"] },
}
local PLAIN_KINDS = { target = true, focus = true, menu = true, assist = true }

local QUESTION_ICON = 134400

-- Pickers' data. Each builder returns { { value, text, icon }, ... } and re-runs every time a list
-- opens, so it reflects the current spellbook, macros and bags. All pcall-guarded: the
-- spellbook/container APIs change between patches and a failure should give an empty list, not an
-- error in the options window.

-- Forever (Classic): every rank of a spell is its own spellbook entry. A binding is written
-- Name(Rank N), which is what the secure "spell" attribute needs to cast exactly that rank, and
-- every spell is shown with its rank behind the name. The rank text is the client's own ("Rank 3"
-- / "Rang 3").
local function spellBookEntries(fn)
    pcall(function()
        local bank = Enum.SpellBookSpellBank.Player
        for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local skill = C_SpellBook.GetSpellBookSkillLineInfo(i)
            if skill and skill.numSpellBookItems then
                for j = (skill.itemIndexOffset or 0) + 1, (skill.itemIndexOffset or 0) + skill.numSpellBookItems do
                    local okItem, item = pcall(C_SpellBook.GetSpellBookItemInfo, j, bank)
                    local okName, name, sub = pcall(C_SpellBook.GetSpellBookItemName, j, bank)
                    if okItem and item and okName and type(name) == "string" and not N.IsSecret(name) then
                        if type(sub) ~= "string" or N.IsSecret(sub) or sub == "" then sub = nil end
                        local isSpell = (not (Enum.SpellBookItemType and item.itemType))
                            or item.itemType == Enum.SpellBookItemType.Spell
                        local passive = item.isPassive
                            or (item.spellID and C_Spell.IsSpellPassive and C_Spell.IsSpellPassive(item.spellID))
                        if isSpell and not passive then fn(item, name, sub) end
                    end
                end
            end
        end
    end)
end

-- Highest known rank text of each spell name ("Rank 7"), for bindings saved without one.
local function highestRanks()
    local best = {}
    spellBookEntries(function(_, name, sub)
        local n = sub and tonumber(sub:match("(%d+)")) or 0
        if not best[name] or n > best[name].n then best[name] = { n = n, sub = sub } end
    end)
    return best
end

-- Spells the player knows that are beneficial (can be cast on another player),
-- one entry per rank.
local function getSpellOptions()
    local out, seen = {}, {}
    local helpful = C_Spell and C_Spell.IsSpellHelpful
    spellBookEntries(function(item, name, sub)
        local ok = true
        if helpful and item.spellID then
            local okCall, isHelpful = pcall(helpful, item.spellID)
            if okCall and isHelpful == false then ok = false end
        end
        local value = sub and (name .. "(" .. sub .. ")") or name
        if ok and not seen[value] then
            seen[value] = true
            out[#out + 1] = {
                value = value, text = sub and (name .. " (" .. sub .. ")") or name,
                icon = item.iconID, name = name, rank = sub and tonumber(sub:match("(%d+)")) or 0,
            }
        end
    end)
    table.sort(out, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        return a.rank > b.rank
    end)
    return out
end

local function getMacroOptions()
    local out = {}
    pcall(function()
        local numGlobal, numChar = GetNumMacros()
        local function add(index, suffix)
            local name, icon = GetMacroInfo(index)
            if name then
                out[#out + 1] = { value = name, text = name, icon = icon, sort = suffix }
            end
        end
        for i = 1, numGlobal do add(i, "a") end
        for i = 1, numChar do add(120 + i, "b") end
    end)
    return out
end

local function getItemOptions()
    local out = {}
    pcall(function()
        local seen = {}
        local function consider(itemID, name, icon)
            if not itemID or seen[itemID] or not name then return end
            local spell = C_Item and C_Item.GetItemSpell and C_Item.GetItemSpell(itemID)
            if spell then
                seen[itemID] = true
                out[#out + 1] = { value = name, text = name, icon = icon }
            end
        end
        local C = C_Container
        if C and C.GetContainerNumSlots then
            local last = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4)
            for bag = 0, last do
                for slot = 1, C.GetContainerNumSlots(bag) do
                    local info = C.GetContainerItemInfo(bag, slot)
                    if info then consider(info.itemID, info.itemName, info.iconFileID) end
                end
            end
        end
        for _, slot in ipairs({ 13, 14 }) do
            local id = GetInventoryItemID("player", slot)
            if id then
                local name, _, _, _, _, _, _, _, _, icon = C_Item.GetItemInfo(id)
                consider(id, name, icon)
            end
        end
    end)
    table.sort(out, function(a, b) return a.text < b.text end)
    return out
end

-- Text + icon for a SAVED value, whether or not it is in the open list (the
-- spell may be off-spec now, the item sold, the macro deleted).
local function resolveSpell(value)
    local text, base = value, value
    if type(value) == "string" and value ~= "" then
        local name, rank = value:match("^(.-)%((.-)%)$")
        if name then
            base, text = name, name .. " (" .. rank .. ")"
        else
            -- Saved without a rank: it casts the highest known rank, so show that one.
            local hi = highestRanks()[value]
            if hi and hi.sub then text = value .. " (" .. hi.sub .. ")" end
        end
    end
    local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(base)
    return text, icon
end

local function resolveMacro(value)
    if value:match("^[/#]") then
        return value:gsub("\n", " "), QUESTION_ICON
    end
    local name, icon = GetMacroInfo(value)
    return value, name and icon or QUESTION_ICON
end

local function resolveItem(value)
    local icon
    if C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, _, tex = C_Item.GetItemInfoInstant(value)
        icon = tex
    end
    return value, icon
end

local PICKERS = {
    spell = { options = getSpellOptions, resolve = resolveSpell },
    macro = { options = getMacroOptions, resolve = resolveMacro },
    item  = { options = getItemOptions,  resolve = resolveItem },
}

local function fireClickCastingChanged()
    N:Fire("NUCLEUS_SETTING_CHANGED", "clickCasting", "clickCasting.bindings")
end

-- Click-Casting tab. Rebuilds in place (wipes and refills the same panel frame), so adding,
-- removing or retyping a binding doesn't need a round trip through the tab/sub selection.
--
-- One binding = one compact row: [key combo] [kind] [value + icon] [x]. The key combo is a capture
-- button: click it, hold any modifiers and click a mouse button. The value takes whatever width is
-- left.

local CC_KEY_W, CC_KIND_W, CC_DEL_W, CC_GAP = 150, 84, 24, 6

local function BuildBindingRow(card, cc, binding, i, rebuild)
    -- Fold the bare kinds an earlier build saved into the General kind.
    if PLAIN_KINDS[binding.kind] then
        binding.value, binding.kind = binding.kind, "general"
    end
    local row = CreateFrame("Frame", nil, card)
    row._rowHeight = 24

    local function put(widget, x, w)
        widget:SetParent(row)
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
        if w then widget:SetWidth(w) end
        widget:SetHeight(24)
        return widget
    end

    local x = 0
    put(N.MakeKeyCapture(row,
        function() return N.ClickCasting.BindingText(binding) end,
        function(mod, btn)
            binding.modifier, binding.button = mod, btn
            fireClickCastingChanged()
        end), x, CC_KEY_W)
    x = x + CC_KEY_W + CC_GAP

    put(N.MakeDropdown(row, nil, KIND_OPTS,
        function() return binding.kind end,
        function(v)
            if binding.kind ~= v then
                binding.value = (v == "general") and "target" or ""
            end
            binding.kind = v
            fireClickCastingChanged()
            rebuild()
        end), x, CC_KIND_W)
    x = x + CC_KIND_W + CC_GAP

    if binding.kind == "general" then
        local value = N.MakeDropdown(row, nil, GENERAL_OPTS,
            function() return binding.value end,
            function(v) binding.value = v; fireClickCastingChanged() end)
        put(value, x)
        value:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(CC_DEL_W + CC_GAP), 0)
    end

    local picker = PICKERS[binding.kind]
    if picker then
        local value = N.MakeIconPicker(row, picker.options,
            function() return binding.value end,
            function(v) binding.value = v; fireClickCastingChanged() end,
            picker.resolve)
        put(value, x)
        value:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(CC_DEL_W + CC_GAP), 0)
    end

    local del = CreateFrame("Button", nil, row)
    del:SetSize(CC_DEL_W, 22)
    del:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -1)
    N.SkinRound(del, M.color.base, M.color.line, true)
    local tint = N.MakeCross(del, 9, 2)
    tint(uc(M.color.textDim))
    del:SetScript("OnEnter", function()
        del._nucFill:SetColorTexture(0.80, 0.22, 0.22, 1)
        tint(1, 1, 1, 1)
    end)
    del:SetScript("OnLeave", function()
        del._nucFill:SetColorTexture(uc(M.color.base))
        tint(uc(M.color.textDim))
    end)
    del:SetScript("OnClick", function()
        table.remove(cc.bindings, i)
        fireClickCastingChanged()
        rebuild()
    end)
    return row
end

local function PlayerSpecs()
    local out = {}
    local _, _, classID = UnitClass("player")
    if not classID then return out end
    local info = _G.C_SpecializationInfo
    local getNum = _G.GetNumSpecializationsForClassID or (info and info.GetNumSpecializationsForClassID)
    local getInfo = _G.GetSpecializationInfoForClassID or (info and info.GetSpecializationInfoForClassID)
    if not (getNum and getInfo) then return out end
    for i = 1, getNum(classID) or 0 do
        local id, name = getInfo(classID, i)
        if id then out[#out + 1] = { id = id, name = name or tostring(id) } end
    end
    return out
end

local ccScope = "class"

local function BuildClickCasting(p)
    for _, child in ipairs({ p:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end
    p._y = -4

    local function rebuild()
        BuildClickCasting(p)
        if scrollChild then scrollChild:SetHeight(math.max(p:GetHeight(), 10)) end
    end

    local cc = N.db.clickCasting
    local _, class = UnitClass("player")
    if type(cc.bySpec) ~= "table" then cc.bySpec = { _list = true } end

    local specs = PlayerSpecs()
    local scopeOpts = { { value = "class", text = L["All specializations"] } }
    local valid = ccScope == "class"
    for _, s in ipairs(specs) do
        scopeOpts[#scopeOpts + 1] = { value = s.id, text = s.name }
        if s.id == ccScope then valid = true end
    end
    if not valid then ccScope = "class" end

    local scope = N.MakeCard(p, L["Specialization"])
    scope:AddRow(N.MakeDropdown(scope, L["Bindings for"], scopeOpts,
        function() return ccScope end,
        function(v) ccScope = v; rebuild() end))
    local bindings = cc.byClass[class]
    if ccScope ~= "class" then
        local own = cc.bySpec[ccScope]
        scope:AddRow(N.MakeCheckbox(scope, L["Own bindings for this specialization"],
            function() return type(cc.bySpec[ccScope]) == "table" end,
            function(v)
                if v then
                    cc.bySpec[ccScope] = N.DeepCopy(cc.byClass[class])
                else
                    cc.bySpec[ccScope] = nil
                end
                fireClickCastingChanged()
                rebuild()
            end))
        bindings = own
    end
    p:AddCard(scope)
    if not bindings then
        local note = N.MakeCard(p, L["Bindings"])
        local fs = N.FontString(note, 11)
        fs:SetPoint("TOPLEFT", note, "TOPLEFT", N.CARD_PAD, note._y)
        fs:SetWidth(note:GetWidth() - 2 * N.CARD_PAD)
        fs:SetJustifyH("LEFT")
        fs:SetTextColor(uc(M.color.textDim))
        fs:SetText(L["CC_SPEC_USES_CLASS"])
        fs:SetHeight(fs:GetStringHeight() + 4)
        note:SetHeight(-note._y + fs:GetHeight() + N.CARD_PAD)
        p:AddCard(note)
        return
    end

    local list = N.MakeCard(p, L["Bindings"])
    local head = CreateFrame("Frame", nil, list)
    head._rowHeight = 14
    local function caption(text, x, w)
        local fs = N.FontString(head, 10)
        fs:SetPoint("TOPLEFT", head, "TOPLEFT", x + 2, 0)
        if w then fs:SetWidth(w) end
        fs:SetJustifyH("LEFT")
        fs:SetTextColor(uc(M.color.textDim))
        fs:SetText(text)
    end
    local x = 0
    caption(L["Key"], x, CC_KEY_W); x = x + CC_KEY_W + CC_GAP
    caption(L["Kind"], x, CC_KIND_W); x = x + CC_KIND_W + CC_GAP
    caption(L["Value"], x)
    list:AddRow(head)

    for i, binding in ipairs(bindings) do
        list:AddRow(BuildBindingRow(list, { bindings = bindings }, binding, i, rebuild))
    end

    list:AddRow(ActionButton(list, "+  " .. L["Add Binding"], function()
        table.insert(bindings, { modifier = "none", button = "LeftButton", kind = "none", value = "" })
        fireClickCastingChanged()
        rebuild()
    end))
    p:AddCard(list)
end

local function BuildAbout(p)
    local c = N.MakeCard(p, L["About"])
    local body = N.FontString(c, 12)
    body:SetPoint("TOPLEFT", N.CARD_PAD, -N.CARD_TOP)
    body:SetWidth(c:GetWidth() - 2 * N.CARD_PAD)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetText(L["ABOUT_BODY"])
    body:SetHeight(body:GetStringHeight() + 4)
    local author = N.FontString(c, 12)
    author:SetPoint("TOPLEFT", body, "BOTTOMLEFT", 0, -12)
    author:SetText(L["Author"] .. ":  |cffffffff" .. N.About.author .. "|r")
    c:SetHeight(N.CARD_TOP + body:GetHeight() + 12 + 16 + N.CARD_PAD)
    p:AddCard(c)

    local links = N.MakeCard(p, L["Links"])
    for _, link in ipairs(N.About.links) do
        local row = CreateFrame("Button", nil, links)
        row._rowHeight = 22
        local dot = links:CreateTexture(nil, "ARTWORK")
        local lc = link.color or M.color.accent
        dot:SetColorTexture(lc[1], lc[2], lc[3], 1)
        local nm = N.FontString(row, 12)
        nm:SetText(link.label)
        local url = N.FontString(row, 11)
        url:SetTextColor(uc(M.color.textDim))
        url:SetText(link.url)
        links:AddRow(row)
        dot:SetPoint("LEFT", row, "LEFT", 0, 0)
        dot:SetSize(8, 8)
        nm:SetPoint("LEFT", dot, "RIGHT", 8, 0)
        url:SetPoint("LEFT", nm, "RIGHT", 12, 0)
        row:SetScript("OnEnter", function() nm:SetTextColor(uc(M.color.accentBright)) end)
        row:SetScript("OnLeave", function() nm:SetTextColor(uc(M.color.text)) end)
        row:SetScript("OnClick", function() N.ShowLinkPopup(link.label, link.url) end)
        if not link.color then
            N.OnRecolor(function() dot:SetColorTexture(M.color.accent[1], M.color.accent[2], M.color.accent[3], 1) end)
        end
    end
    p:AddCard(links)

    local sup = N.MakeCard(p, L["Supporters"])
    sup:AddRow(N.Supporters.MakeButton(sup))
    p:AddCard(sup)
end

local function BuildChangelog(p)
    local c = N.MakeCard(p, L["Changelog"])
    local lines = {}
    for _, entry in ipairs(N.Changelog) do
        lines[#lines + 1] = string.format("|cff61aef7%s|r  |cff8a8a8a%s|r", entry.version, entry.date)
        for _, note in ipairs(entry.notes) do
            lines[#lines + 1] = "   \194\183 " .. note
        end
        lines[#lines + 1] = ""
    end
    local text = N.FontString(c, 12)
    text:SetPoint("TOPLEFT", N.CARD_PAD, -N.CARD_TOP)
    text:SetWidth(c:GetWidth() - 2 * N.CARD_PAD)
    text:SetJustifyH("LEFT")
    text:SetSpacing(3)
    text:SetText(table.concat(lines, "\n"))
    c:SetHeight(N.CARD_TOP + text:GetStringHeight() + N.CARD_PAD)
    p:AddCard(c)
end

local function BuildStub(p, name)
    local c = N.MakeCard(p, name)
    local t = N.FontString(c, 12)
    t:SetPoint("TOPLEFT", N.CARD_PAD, -N.CARD_TOP)
    t:SetWidth(c:GetWidth() - 2 * N.CARD_PAD)
    t:SetJustifyH("LEFT")
    t:SetTextColor(uc(M.color.textDim))
    t:SetText(L["STUB_BODY"])
    t:SetHeight(t:GetStringHeight() + 4)
    c:SetHeight(N.CARD_TOP + t:GetHeight() + N.CARD_PAD)
    p:AddCard(c)
end

-- Spotlight page: global (not per party/raid) - which units the Spotlight frames show.
-- Looks and layout of those frames are edited with the "Spotlight" mode switch below.
local SP_TEXT = { target = "SP_target", targettarget = "SP_targettarget", focus = "SP_focus" }
local function SpotlightText(e)
    if e.type == "role" then return L[e.value == "HEALER" and "SP_healers" or "SP_tanks"] end
    if e.type == "name" then return L["SP_name"] .. ": " .. tostring(e.value) end
    return L[SP_TEXT[e.type] or "SP_target"]
end

local function BuildSpotlight(p)
    for _, child in ipairs({ p:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end
    p._y = -4

    local cfg = N.db.spotlight
    local function rebuild()
        BuildSpotlight(p)
        if scrollChild then scrollChild:SetHeight(math.max(p:GetHeight(), 10) + 8) end
    end
    local function copyList()
        local t = {}
        for i, e in ipairs(cfg.units or {}) do t[i] = N.DeepCopy(e) end
        return t
    end
    local function save(list)
        list._list = true
        N:Set("spotlight.units", list)
        rebuild()
    end
    local function add(entry)
        local list = copyList()
        if #list >= N.SPOTLIGHT_MAX then return end
        list[#list + 1] = entry
        save(list)
    end

    local c = N.MakeCard(p, L["Spotlight Frame"])
    c:AddRow(N.MakeCheckbox(c, L["Enabled"],
        function() return cfg.enabled end, function(v) N:Set("spotlight.enabled", v) end))
    local hint = N.FontString(c, 11)
    hint:SetPoint("TOPLEFT", c, "TOPLEFT", N.CARD_PAD, c._y)
    hint:SetWidth(c:GetWidth() - 2 * N.CARD_PAD)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(uc(M.color.textDim))
    hint:SetText(L["SPOTLIGHT_HINT"])
    hint:SetHeight(hint:GetStringHeight() + 4)
    c:SetHeight(-c._y + hint:GetHeight() + N.CARD_PAD)
    p:AddCard(c)

    local lc = N.MakeCard(p, L["Spotlight units"])
    for i, e in ipairs(cfg.units or {}) do
        local row = CreateFrame("Frame", nil, lc)
        row._rowHeight = 26
        local fs = N.FontString(row, 12)
        fs:SetPoint("LEFT", row, "LEFT", 0, 0)
        fs:SetText(i .. ".  " .. SpotlightText(e))
        local del = CreateFrame("Button", nil, row)
        del:SetSize(24, 22)
        del:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        N.SkinRound(del, M.color.base, M.color.line, true)
        local tint = N.MakeCross(del, 9, 2)
        tint(uc(M.color.textDim))
        del:SetScript("OnEnter", function()
            del._nucFill:SetColorTexture(0.80, 0.22, 0.22, 1)
            tint(1, 1, 1, 1)
        end)
        del:SetScript("OnLeave", function()
            del._nucFill:SetColorTexture(uc(M.color.base))
            tint(uc(M.color.textDim))
        end)
        del:SetScript("OnClick", function()
            local list = copyList()
            table.remove(list, i)
            save(list)
        end)
        lc:AddRow(row)
    end
    if #(cfg.units or {}) == 0 then
        local none = N.FontString(lc, 11)
        none:SetPoint("TOPLEFT", lc, "TOPLEFT", N.CARD_PAD, lc._y)
        none:SetTextColor(uc(M.color.textDim))
        none:SetText(L["SP_none"])
        lc:SetHeight(-lc._y + none:GetStringHeight() + N.CARD_PAD)
    end
    p:AddCard(lc)

    local ac = N.MakeCard(p, L["Add to spotlight"])
    ac:AddRow(ActionButton(ac, "+  " .. L["SP_tanks"], function() add({ type = "role", value = "TANK" }) end))
    ac:AddRow(ActionButton(ac, "+  " .. L["SP_healers"], function() add({ type = "role", value = "HEALER" }) end))
    ac:AddRow(ActionButton(ac, "+  " .. L["SP_target"], function() add({ type = "target" }) end))
    ac:AddRow(ActionButton(ac, "+  " .. L["SP_targettarget"], function() add({ type = "targettarget" }) end))
    ac:AddRow(ActionButton(ac, "+  " .. L["SP_focus"], function() add({ type = "focus" }) end))
    ac:AddRow(N.MakeTextInput(ac, L["SP_name_add"],
        function() return "" end,
        function(v)
            v = strtrim(v or "")
            if v ~= "" then add({ type = "name", value = v }) end
        end))
    p:AddCard(ac)
end

--------------------------------------------------------------------------------
-- Tab model
--------------------------------------------------------------------------------

local TABS

local function BuildTabModel()
    local indicatorSubs = {}
    for _, meta in ipairs(N.Indicators.builtins) do
        indicatorSubs[#indicatorSubs + 1] = {
            id = meta.name, label = L[meta.label], perMode = true,
            build = function(p, mode) BuildIndicator(p, mode, meta) end,
            enabledCheck = function() return N.db[N:Mode()].indicators[meta.name].enabled end,
        }
    end
    for _, kind in ipairs({ "buffs", "debuffs", "dispels", "defensives", "externals", "offensives", "crowdControls" }) do
        indicatorSubs[#indicatorSubs + 1] = {
            id = kind, label = L[AURA_TITLES[kind]], perMode = true,
            build = function(p, mode) BuildAuras(p, mode, kind) end,
            enabledCheck = function() return N.db[N:Mode()].auras[kind].enabled end,
        }
    end
    indicatorSubs[#indicatorSubs + 1] = {
        id = "targetedSpellBars", label = L["Targeted Spell Bars"],
        build = function(p) BuildTargetedSpellBars(p) end,
        enabledCheck = function() return N.db.targetedSpellBars.enabled end,
    }
    indicatorSubs[#indicatorSubs + 1] = {
        id = "actions", label = L["Actions"],
        build = function(p) BuildActions(p) end,
        enabledCheck = function() return N.db.actions.enabled end,
    }

    local function stub(name)
        return { { id = "overview", label = L["Overview"],
                  build = function(p) BuildStub(p, name) end } }
    end

    TABS = {
        { id = "general", label = L["General"], flow = true, subs = {
            { id = "overview", label = L["Overview"], perMode = true,
              build = function(p, mode) BuildGeneralOverview(p, mode) end },
            { id = "tooltip", label = L["Tooltip"], build = BuildTooltip },
            { id = "position", label = L["Position"], build = BuildPosition },
        } },
        { id = "appearance", label = L["Appearance"], flow = true, subs = {
            { id = "layout", label = L["Layout"], perMode = true,
              build = function(p, mode) BuildLayout(p, mode) end },
            { id = "range", label = L["Range"], perMode = true,
              build = function(p, mode) BuildRange(p, mode) end },
            { id = "color", label = L["Color"], perMode = true,
              build = function(p, mode) BuildColor(p, mode) end },
        } },
        { id = "indicators", label = L["Indicators"], subs = indicatorSubs },
        { id = "clickcasting", label = L["Click-Casting"], flow = "single", subs = {
            { id = "bindings", label = L["Click-Casting"], build = BuildClickCasting },
        } },
        { id = "spotlight", label = L["Spotlight"], flow = "single", subs = {
            { id = "units", label = L["Spotlight"], build = function(p) BuildSpotlight(p) end,
              enabledCheck = function() return N.db.spotlight.enabled end },
        } },
        { id = "utilities", label = L["Utilities"], flow = "single", subs = {
            { id = "readyPull", label = L["Ready & Pull"], build = function(p) BuildTools(p, "readyPull") end,
              enabledCheck = function() return N.db.tools.readyPull.enabled end },
            { id = "battleRes", label = L["Battle Res"], build = function(p) BuildTools(p, "battleRes") end,
              enabledCheck = function() return N.db.tools.battleRes.enabled end },
            { id = "marks", label = L["Marks"], build = function(p) BuildTools(p, "marks") end,
              enabledCheck = function() return N.db.tools.marks.enabled end },
        } },
        { id = "profile", label = L["Profile"], flow = "single", subs = {
            { id = "profile", label = L["Profile"], build = function(p) N.BuildProfilePanel(p) end },
        } },
        { id = "about", label = L["About"], flow = "single", subs = {
            { id = "about", label = L["About"], build = BuildAbout },
            { id = "changelog", label = L["Changelog"], build = BuildChangelog },
        } },
    }
end

local function FindTab(id)
    for _, t in ipairs(TABS) do if t.id == id then return t end end
end

-- The Indicators rail ends with the custom indicators of the group being edited
-- and the "+" entry; rebuilt whenever the list, the group or the profile changes.
local function SyncCustomSubs()
    local tab = FindTab("indicators")
    local subs = tab.subs
    for i = #subs, 1, -1 do
        if subs[i].custom or subs[i].action then table.remove(subs, i) end
    end
    local mode = N:Mode()
    local live = {}
    for _, e in ipairs(N.db[mode].customIndicators or {}) do
        local id = e.id
        live["custom:" .. id] = true
        subs[#subs + 1] = {
            id = "custom:" .. id, label = e.name, custom = true, perMode = true, glyph = e.type,
            build = function(p, m) BuildCustom(p, m, id) end,
            enabledCheck = function()
                local _, en = customEntryIndex(mode, id)
                return en and en.enabled
            end,
        }
    end
    subs[#subs + 1] = {
        id = "__new", label = "+  " .. L["New indicator"], action = true,
        onClick = function() N.ShowNewCustomIndicator() end,
    }
    for key, panel in pairs(panelCache) do
        local cid = key:match("^indicators/(custom:[^/]+)")
        if cid and not live[cid] then
            if panel.previewHost then panel.previewHost:Hide(); panel.previewHost:SetParent(nil) end
            panel:Hide()
            panel:SetParent(nil)
            panelCache[key] = nil
        end
    end
end

local function HasSub(tab, id)
    for _, s in ipairs(tab.subs) do if s.id == id and not s.action then return true end end
end

local function GetPanel(tabId, sub)
    local key = tabId .. "/" .. sub.id .. (sub.perMode and ("/" .. N:Mode()) or "")
    local p = panelCache[key]
    if not p then
        p = NewPanel()
        sub.build(p, N:Mode())
        panelCache[key] = p
    end
    return p
end

local function GetFlowPanel(tab)
    local perMode = false
    for _, s in ipairs(tab.subs) do if s.perMode then perMode = true break end end
    local key = tab.id .. "/flow" .. (perMode and ("/" .. N:Mode()) or "")
    local p = panelCache[key]
    if not p then
        p = NewPanel(tab.flow == true)
        for _, s in ipairs(tab.subs) do s.build(p, N:Mode()) end
        panelCache[key] = p
    end
    return p
end

--------------------------------------------------------------------------------
-- Selection
--------------------------------------------------------------------------------

local function HidePreviews()
    for _, p in pairs(panelCache) do
        if p.previewHost then p.previewHost:Hide() end
    end
end

local function SelectSub(tabId, subId)
    local tab = FindTab(tabId)
    for _, p in pairs(panelCache) do p:Hide() end
    HidePreviews()

    local shown
    for _, sub in ipairs(tab.subs) do
        if not sub.action then
            local p = GetPanel(tabId, sub)
            local on = sub.id == subId
            p:SetShown(on)
            if on then shown = p end
        end
    end
    if not shown then return end
    for _, b in ipairs(subNavPool) do
        if b:IsShown() then b:SetActiveState(b.subId == subId) end
    end
    activeSub = subId
    lastSubOf[tabId] = subId

    -- A page with a preview pins it at the top of the content area and starts
    -- the scrolling settings below it.
    local top = BODY_TOP
    local host = shown.previewHost
    if host then
        host:SetParent(window)
        host:ClearAllPoints()
        host:SetPoint("TOPLEFT", window, "TOPLEFT", RAIL_W + 16 + 2, -BODY_TOP)
        host:SetPoint("TOPRIGHT", window, "TOPRIGHT", -16 - 2, -BODY_TOP)
        host:Show()
        top = BODY_TOP + host:GetHeight() + 10
    end
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", window, "TOPLEFT", RAIL_W + 16, -top)
    scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -16, MODEBAR + 10)

    scrollChild:SetHeight(math.max(shown:GetHeight(), 10) + 8)
    if scroll.SetOffset then scroll.SetOffset(0) end
end

-- Rail item: transparent at rest, soft wash on hover, a rounded accent-tinted pill while active
-- (the text lifts to the bright accent).
-- Shapes of the small type glyphs in the rail: lists of {x, y, w, h, alpha} on a 16x16 grid (y
-- counted from the top).
local GLYPHS = {
    icon    = { {1,1,14,2}, {1,13,14,2}, {1,3,2,10}, {13,3,2,10}, {5,5,6,6} },
    icons   = { {0,4,4,8}, {6,4,4,8}, {12,4,4,8} },
    text    = { {2,2,12,3}, {6,5,4,9} },
    rect    = { {2,2,12,12} },
    color   = { {2,2,12,12, 0.35}, {2,2,6,12}, {2,2,3,12} },
    bar     = { {1,5,14,1}, {1,10,14,1}, {1,5,1,6}, {14,5,1,6}, {3,7,7,2} },
    border  = { {1,1,14,2}, {1,13,14,2}, {1,3,2,10}, {13,3,2,10} },
    overlay = { {2,2,12,12, 0.35}, {2,9,12,5} },
    glow    = { {5,5,6,6}, {7,0,2,3}, {7,13,2,3}, {0,7,3,2}, {13,7,3,2},
                {2,2,2,2, 0.6}, {12,2,2,2, 0.6}, {2,12,2,2, 0.6}, {12,12,2,2, 0.6} },
}

local function SetNavGlyph(b, kind)
    local shape = kind and GLYPHS[kind]
    local glyph = b.glyph
    if not shape then
        glyph:Hide()
        b.label:SetPoint("RIGHT", -6, 0)
        return
    end
    for i, r in ipairs(shape) do
        local t = glyph.parts[i]
        if not t then
            t = glyph:CreateTexture(nil, "ARTWORK")
            t:SetTexture(M.flat)
            glyph.parts[i] = t
        end
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", glyph, "TOPLEFT", r[1], -r[2])
        t:SetSize(r[3], r[4])
        t._alpha = r[5] or 1
        t:Show()
    end
    for i = #shape + 1, #glyph.parts do glyph.parts[i]:Hide() end
    glyph:Show()
    b.label:SetPoint("RIGHT", glyph, "LEFT", -6, 0)
    b.Repaint()
end

local function MakeNavItem(parent)
    local b = CreateFrame("Button", nil, parent)

    local function pill(color)
        local t = b:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(M.tex.roundSm)
        if t.SetTextureSliceMargins then t:SetTextureSliceMargins(5, 5, 5, 5) end
        t:SetPoint("TOPLEFT", 0, -1)
        t:SetPoint("BOTTOMRIGHT", 0, 1)
        t:SetVertexColor(uc(color))
        t:Hide()
        return t
    end
    local wash = pill(M.color.itemHover)
    local tint = pill(M.color.tabTint)
    local accentBg = pill(M.color.accentDim)
    b.accentBg = accentBg

    local glyph = CreateFrame("Frame", nil, b)
    glyph:SetSize(16, 16)
    glyph:SetPoint("RIGHT", b, "RIGHT", -8, 0)
    glyph.parts = {}
    glyph:Hide()
    b.glyph = glyph

    b.label = N.FontString(b, 12)
    b.label:SetPoint("LEFT", 12, 0)
    b.label:SetPoint("RIGHT", -6, 0)
    b.label:SetJustifyH("LEFT")
    b.label:SetWordWrap(false)
    b.label:SetTextColor(uc(M.color.textDim))

    b._active = false
    local function paint()
        tint:SetShown(b._active)
        wash:SetShown(b._hover and not b._active)
        accentBg:SetShown(b.isAction and true or false)
        local c = (b.isAction or b._active) and M.color.accentBright
            or (b._hover and M.color.text or M.color.textDim)
        b.label:SetTextColor(uc(c))
        for _, t in ipairs(glyph.parts) do
            local col = b._active and M.color.accentBright or (b._hover and M.color.text or M.color.textDim)
            t:SetVertexColor(col[1], col[2], col[3], t._alpha or 1)
        end
    end
    b.Repaint = paint
    b:HookScript("OnEnter", function() b._hover = true; paint() end)
    b:HookScript("OnLeave", function() b._hover = false; paint() end)
    function b:SetActiveState(on) b._active = on and true or false; paint() end
    paint()

    N.OnRecolor(function()
        tint:SetVertexColor(uc(M.color.tabTint))
        paint()
    end)

    return b
end

local function refreshNavDim(b)
    b:SetAlpha((not b.enabledCheck or b.enabledCheck()) and 1 or 0.45)
end

local navBuiltFor
local function BuildSubNav(tab)
    for _, b in ipairs(subNavPool) do b:Hide() end
    local y = -8
    local keep = (navBuiltFor == tab.id) and railScroll:GetVerticalScroll() or 0
    navBuiltFor = tab.id
    railChild:SetHeight(#tab.subs * 26 + 16)
    railScroll.SetOffset(keep)
    for i, sub in ipairs(tab.subs) do
        local b = subNavPool[i]
        if not b then
            b = MakeNavItem(railChild)
            b:SetHeight(26)
            subNavPool[i] = b
        end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 6, y)
        b:SetPoint("TOPRIGHT", -6, y)
        b.subId = sub.id
        b.label:SetText(sub.label)
        b.isAction = sub.action and true or false
        SetNavGlyph(b, sub.glyph)
        b.Repaint()
        b.enabledCheck = sub.enabledCheck
        b:SetScript("OnClick", function()
            if sub.action then sub.onClick() else SelectSub(tab.id, sub.id) end
        end)
        b:Show()
        refreshNavDim(b)
        y = y - 26
    end
end

local function RefreshSubNavDim()
    for _, b in ipairs(subNavPool) do
        if b:IsShown() then refreshNavDim(b) end
    end
end
N:On("NUCLEUS_SETTING_CHANGED", function(_, _, path)
    if path and (path:find("%.indicators%.") or path:find("%.auras%.") or path:find("%.customIndicators") or path:find("^targetedSpellBars%.enabled") or path:find("^actions%.enabled")) then
        RefreshSubNavDim()
    end
end)
N:On("NUCLEUS_EDIT_MODE", RefreshSubNavDim)

local function SelectTab(tabId)
    local tab = FindTab(tabId)
    HidePreviews()
    if tabId ~= "about" and N.Supporters then N.Supporters.Hide() end
    activeTab = tabId
    for _, b in ipairs(topTabButtons) do
        b:SetActiveState(b.tabId == tabId)
    end

    local railed = not tab.flow
    N.CONTENT_WIDTH = railed and RAIL_CW or FLOW_CW
    CONTENT_W = N.CONTENT_WIDTH
    if subnavHost then subnavHost:SetShown(railed) end
    if vHair then vHair:SetShown(railed) end
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", window, "TOPLEFT", (railed and RAIL_W or 0) + 16, -BODY_TOP)
    scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -16, MODEBAR + 10)
    scrollChild:SetWidth(N.CONTENT_WIDTH)

    if railed then
        if tabId == "indicators" then SyncCustomSubs() end
        BuildSubNav(tab)
        local want = lastSubOf[tabId]
        if not (want and HasSub(tab, want)) then want = tab.subs[1].id end
        SelectSub(tabId, want)
    else
        for _, b in ipairs(subNavPool) do b:Hide() end
        for _, p in pairs(panelCache) do p:Hide() end
        local p = GetFlowPanel(tab)
        p:Show()
        scrollChild:SetHeight(math.max(p:GetHeight(), 10) + 8)
        if scroll.SetOffset then scroll.SetOffset(0) end
        activeSub = nil
    end
end

function N.RefreshCustomRail()
    local tab = FindTab("indicators")
    SyncCustomSubs()
    if window and window:IsShown() and activeTab == "indicators" then BuildSubNav(tab) end
end

function N.OpenCustomIndicator(id)
    SyncCustomSubs()
    lastSubOf["indicators"] = "custom:" .. id
    SelectTab("indicators")
end

function N.DeleteCustomIndicator(mode, id)
    local list = N.db[mode].customIndicators
    local idx = customEntryIndex(mode, id)
    if not idx then return end
    table.remove(list, idx)
    N:Fire("NUCLEUS_SETTING_CHANGED", mode, mode .. ".customIndicators")
    lastSubOf["indicators"] = nil
    SyncCustomSubs()
    if window and window:IsShown() then SelectTab("indicators") end
end

function N.OptionsResize(p)
    if scrollChild and p:IsShown() then
        scrollChild:SetHeight(math.max(p:GetHeight(), 10) + 8)
    end
end

-- A profile switch replaces every setting table, so every cached panel (they
-- captured the old tables when built) is dropped and rebuilt on demand. The
-- profile tab rebuilds itself.
N:On("NUCLEUS_PROFILE_CHANGED", function()
    for key, p in pairs(panelCache) do
        if not key:find("^profile/") then
            if p.previewHost then p.previewHost:Hide(); p.previewHost:SetParent(nil) end
            p:Hide()
            p:SetParent(nil)
            panelCache[key] = nil
        end
    end
    if window and window:IsShown() and activeTab then SelectTab(activeTab) end
end)

local RefreshMode
RefreshMode = function()
    local mode = N:Mode()
    for _, b in ipairs(modeButtons) do
        b:SetActiveState(b.mode == mode or (b.mode == "pets" and N.PET_KEYS[mode] == true))
    end
    if modeLabel then
        modeLabel:SetText(L[MODE_TITLES[mode] or "Party Frames"])
    end
    if activeTab then SelectTab(activeTab) end
end
N.RefreshMode = RefreshMode

--------------------------------------------------------------------------------
-- Window chrome
--------------------------------------------------------------------------------

-- Segmented tab: a rounded pill that fills with the accent while selected and washes lightly on
-- hover. Holding a tab (instead of clicking) drags the window like the header; a quick click still
-- reaches OnClick.
local function MakeTabButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function() window:StartMoving() end)
    b:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)

    local pill = b:CreateTexture(nil, "ARTWORK")
    pill:SetTexture(M.tex.roundSm)
    if pill.SetTextureSliceMargins then pill:SetTextureSliceMargins(5, 5, 5, 5) end
    pill:SetAllPoints()
    pill:Hide()

    b.label = N.FontString(b, 11)
    b.label:SetPoint("CENTER", 0, 0)
    b.label:SetWordWrap(false)

    local function paint()
        if b._active then
            pill:SetVertexColor(uc(M.color.navActive))
        else
            pill:SetVertexColor(uc(M.color.itemHover))
        end
        pill:SetShown(b._active or b._hover)
        b.label:SetTextColor(uc(b._active and { 1, 1, 1, 1 }
            or (b._hover and M.color.text or M.color.textDim)))
    end
    b:HookScript("OnEnter", function() b._hover = true; paint() end)
    b:HookScript("OnLeave", function() b._hover = false; paint() end)
    function b:SetActiveState(on) b._active = on and true or false; paint() end
    paint()

    N.OnRecolor(paint)
    return b
end

local function BuildTopTabs()
    local strip = CreateFrame("Frame", nil, window)
    strip:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -HEADER)
    strip:SetPoint("TOPRIGHT", window, "TOPRIGHT", -12, -HEADER)
    strip:SetHeight(TAB_H)
    N.SkinRound(strip, M.color.segment, M.color.line, true)

    local inset, gap = 3, 2
    local n = #TABS
    local bw = math.floor((WIN_W - 24 - inset * 2 - gap * (n - 1)) / n)
    local prev
    for i, tab in ipairs(TABS) do
        local b = MakeTabButton(strip)
        b.tabId = tab.id
        b.label:SetText(tab.label)
        b:SetSize(bw, TAB_H - inset * 2)
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", gap, 0)
        else
            b:SetPoint("LEFT", strip, "LEFT", inset, 0)
        end
        b:SetScript("OnClick", function() SelectTab(tab.id) end)
        topTabButtons[#topTabButtons + 1] = b
        prev = b
    end
end

local function BuildModeBar()
    local prefix = N.FontString(window, 11)
    prefix:SetPoint("BOTTOMLEFT", 16, MODEBAR / 2 - 5)
    prefix:SetText(L["Editing"])
    prefix:SetTextColor(uc(M.color.textDim))

    local track = CreateFrame("Frame", nil, window)
    track:SetSize(4 * 76 + 14, 26)
    track:SetPoint("LEFT", prefix, "RIGHT", 10, 0)
    N.SkinRound(track, M.color.segment, M.color.line, true)

    local defs = { { "party", L["Group"] }, { "raid", L["Raid"] }, { "pets", L["Pets / NPCs"] }, { "spotlight", L["Spotlight"] } }
    local prev
    for _, d in ipairs(defs) do
        local b = CreateFrame("Button", nil, track)
        b.mode = d[1]
        b:SetSize(76, 20)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0)
        else b:SetPoint("LEFT", track, "LEFT", 3, 0) end
        local pill = b:CreateTexture(nil, "ARTWORK")
        pill:SetTexture(M.tex.roundSm)
        if pill.SetTextureSliceMargins then pill:SetTextureSliceMargins(5, 5, 5, 5) end
        pill:SetAllPoints()
        pill:Hide()
        local label = N.FontString(b, 12)
        label:SetPoint("CENTER")
        label:SetText(d[2])
        local function paint()
            pill:SetVertexColor(uc(M.color.navActive))
            pill:SetShown(b._active)
            label:SetTextColor(uc(b._active and { 1, 1, 1, 1 }
                or (b._hover and M.color.text or M.color.textDim)))
        end
        function b:SetActiveState(on) b._active = on and true or false; paint() end
        b:HookScript("OnEnter", function() b._hover = true; paint() end)
        b:HookScript("OnLeave", function() b._hover = false; paint() end)
        N.OnRecolor(paint)
        b:SetScript("OnClick", function()
            local target = b.mode
            if target == "pets" then
                if N.PET_KEYS[N:Mode()] then return end
                target = N.db.lastPetMode or "ownPet"
            end
            if N:Mode() ~= target then
                N:SetMode(target)
                RefreshMode()
            end
        end)
        paint()
        modeButtons[#modeButtons + 1] = b
        prev = b
    end

    local test = CreateFrame("Button", nil, window)
    test:SetSize(104, 26)
    test:SetPoint("LEFT", track, "RIGHT", 12, 0)
    N.SkinButton(test)
    local tl = N.FontString(test, 12)
    tl:SetPoint("CENTER")
    tl:SetText(L["Test Mode"])
    test:SetScript("OnClick", function()
        if N.TestMode then N.TestMode.Toggle() end
    end)
    local function syncTest()
        test:SetActiveState(N.TestMode and N.TestMode.IsActive())
    end
    syncTest()
    N:On("NUCLEUS_TEST_MODE", syncTest)
end

-- Resource read-out (bottom right): CPU time this addon spends per frame, what fraction of the
-- frame budget that is, and its memory use. Uses C_AddOnProfiler (always on, no scriptProfiling
-- CVar needed).

local Prof      = _G.C_AddOnProfiler
local CPU_METRIC = Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric.RecentAverageTime
local GetMem    = _G.GetAddOnMemoryUsage    or (C_AddOns and C_AddOns.GetAddOnMemoryUsage)
local UpdMem    = _G.UpdateAddOnMemoryUsage or (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage)

local function UpdateStats()
    if not statsText then return end
    local parts = {}

    if Prof and Prof.GetAddOnMetric and CPU_METRIC then
        local ms = Prof.GetAddOnMetric(ns.ADDON, CPU_METRIC) or 0
        local fps = GetFramerate and GetFramerate() or 0
        local pct = fps > 0 and (ms / (1000 / fps) * 100) or 0
        parts[#parts + 1] = string.format("%.3f ms (%.2f%%)", ms, pct)
    end

    if UpdMem and GetMem then
        UpdMem()
        local kb = GetMem(ns.ADDON) or 0
        parts[#parts + 1] = kb >= 1024 and string.format("%.1f MB", kb / 1024)
            or string.format("%.0f KB", kb)
    end

    statsText:SetText(table.concat(parts, "\n"))
end

local function BuildStats()
    statsText = N.FontString(window, 10)
    statsText:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -16, MODEBAR / 2 - 12)
    statsText:SetJustifyH("RIGHT")
    statsText:SetSpacing(2)
    statsText:SetTextColor(uc(M.color.textDim))
end

-- Round "x" close button shared by the main window and the popups: a grey cross that turns the
-- whole pill red on hover.
local function MakeCloseButton(parent, target)
    local close = CreateFrame("Button", nil, parent)
    close:SetSize(24, 24)
    N.SkinRound(close, M.color.base, M.color.line, true)
    local tint = N.MakeCross(close, 11, 2)
    tint(uc(M.color.textDim))
    close:HookScript("OnEnter", function()
        close._nucFill:SetColorTexture(0.80, 0.22, 0.22, 1)
        tint(1, 1, 1, 1)
    end)
    close:HookScript("OnLeave", function()
        close._nucFill:SetColorTexture(uc(M.color.base))
        tint(uc(M.color.textDim))
    end)
    close:SetScript("OnClick", function() target:Hide() end)
    return close
end

local function BuildHeader(win, titleText)
    local header = CreateFrame("Frame", nil, win)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(HEADER)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() win:StartMoving() end)
    header:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)

    local title = N.FontString(header, 15)
    title:SetPoint("LEFT", header, "LEFT", 16, 0)
    title:SetText(titleText)

    local close = MakeCloseButton(header, win)
    close:SetPoint("RIGHT", header, "RIGHT", -12, 0)
    return header, title, close
end

local function BuildWindow()
    window = CreateFrame("Frame", "NucleusOptionsFrame", UIParent)
    window._nucUI = true
    window:SetSize(WIN_W, WIN_H)
    window:SetPoint("CENTER")
    window:SetScale(N.db.uiScale or 1.0)
    window:SetFrameStrata("HIGH")
    window:EnableMouse(true)
    window:SetMovable(true)
    window:SetClampedToScreen(true)
    window:SetScript("OnShow", function()
        UpdateStats()
        statsTicker = C_Timer.NewTicker(2, UpdateStats)
        if activeTab then SelectTab(activeTab) end
    end)
    window:SetScript("OnHide", function()
        if statsTicker then statsTicker:Cancel(); statsTicker = nil end
    end)
    window:Hide()
    tinsert(UISpecialFrames, "NucleusOptionsFrame")
    N.SkinRound(window, M.color.windowBg, M.color.line)
    N.AddShadow(window, 14, 0.7, -5)

    local header, titleName = BuildHeader(window, "Nucleus")

    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetSize(30, 30)
    logo:SetPoint("LEFT", header, "LEFT", 12, 0)
    logo:SetTexture(M.tex.logo)
    titleName:ClearAllPoints()
    titleName:SetPoint("LEFT", logo, "RIGHT", 8, 0)

    local badge = CreateFrame("Frame", nil, header)
    badge:SetPoint("LEFT", titleName, "RIGHT", 8, 0)
    N.SkinRound(badge, M.color.segment, M.color.line, true)
    local titleVer = N.FontString(badge, 10)
    titleVer:SetPoint("CENTER")
    titleVer:SetTextColor(uc(M.color.textDim))
    titleVer:SetText("v" .. ns.VERSION)
    badge:SetSize(titleVer:GetStringWidth() + 14, 16)

    modeLabel = N.FontString(header, 11)
    modeLabel:SetPoint("LEFT", badge, "RIGHT", 8, 0)
    modeLabel:SetTextColor(uc(M.color.accentBright))
    N.OnRecolor(function() modeLabel:SetTextColor(uc(M.color.accentBright)) end)

    N.Hairline(window, "hb", MODEBAR, M.color.line, 12, 12)

    subnavHost = CreateFrame("Frame", nil, window)
    subnavHost:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -BODY_TOP)
    subnavHost:SetPoint("BOTTOMRIGHT", window, "BOTTOMLEFT", RAIL_W, MODEBAR + 10)
    N.SkinRound(subnavHost, M.color.card, M.color.line)

    railScroll, railChild = N.MakeScroll(subnavHost, -3)
    railScroll:SetPoint("TOPLEFT", subnavHost, "TOPLEFT", 4, -4)
    railScroll:SetPoint("BOTTOMRIGHT", subnavHost, "BOTTOMRIGHT", -9, 4)
    railChild:SetWidth(RAIL_W - 12 - 4 - 9)

    scroll, scrollChild = N.MakeScroll(window)
    scroll:SetPoint("TOPLEFT", window, "TOPLEFT", RAIL_W + 14, -BODY_TOP)
    scroll:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -16, MODEBAR + 10)
    scrollChild:SetWidth(CONTENT_W)

    BuildTabModel()
    BuildTopTabs()
    BuildModeBar()
    BuildStats()
    SelectTab("general")
    RefreshMode()
end

-- Ping settings popup: a small standalone window (not part of the tab system), opened from a
-- button under General > Overview.

local POPUP_W = 340

-- Shared chrome for every small standalone popup (Ping, Shield, ...): header bar with drag and
-- centered title, a working close button (explicitly above the header's frame level, since the
-- header spans the full width and would eat the click) and a scroll area whose child already
-- stacks cards.
local function BuildPopupShell(frameName, titleText, width, height)
    local win = CreateFrame("Frame", frameName, UIParent)
    win._nucUI = true
    win:SetSize(width, height)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:Hide()
    tinsert(UISpecialFrames, frameName)
    N.SkinRound(win, M.color.windowBg, M.color.line)
    N.AddShadow(win, 14, 0.7, -5)

    local _, title = BuildHeader(win, titleText)

    local scroll, child = N.MakeScroll(win)
    scroll:SetPoint("TOPLEFT", win, "TOPLEFT", 14, -(HEADER + 4))
    scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -16, 14)
    local cardW = width - 14 - 16
    child:SetWidth(cardW)
    child._cardW = cardW
    child._y = -4
    function child:AddCard(card)
        card:SetParent(self)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", self, "TOPLEFT", 2, self._y)
        card:SetPoint("TOPRIGHT", self, "TOPRIGHT", -2, self._y)
        self._y = self._y - card:GetHeight() - 12
        self:SetHeight(-self._y + 4)
    end

    return win, child, title
end
N.BuildPopupShell = BuildPopupShell

local function AddPopupHint(child, cardW, text)
    local hint = N.FontString(child, 11)
    hint:SetPoint("TOPLEFT", child, "TOPLEFT", 2, child._y)
    hint:SetWidth(cardW - 4)
    hint:SetJustifyH("LEFT")
    hint:SetTextColor(uc(M.color.textDim))
    hint:SetText(text)
    hint:SetHeight(hint:GetStringHeight() + 4)
    child._y = child._y - hint:GetHeight() - 8
    child:SetHeight(-child._y + 4)
end

local newCustomPopup
local newCustom = { name = "", type = "icon" }

local function BuildNewCustomPopup()
    local win, child = BuildPopupShell("NucleusNewIndicator", L["New indicator"], POPUP_W, 380)
    local card = N.MakeCard(child, L["New indicator"])
    local nameInput = N.MakeTextInput(card, L["Name"], function() return newCustom.name end,
        function(v) newCustom.name = v or "" end)
    card:AddRow(nameInput)
    local opts = {}
    for _, t in ipairs(N.CustomIndicators.TYPES) do
        opts[#opts + 1] = { value = t, text = L["CI_TYPE_" .. t] }
    end
    local desc
    card:AddRow(N.MakeDropdown(card, L["Indicator type"], opts, function() return newCustom.type end,
        function(v) newCustom.type = v; if desc then desc:SetText(L["CI_DESC_" .. v]) end end))
    desc = N.FontString(card, 11)
    desc:SetPoint("TOPLEFT", card, "TOPLEFT", N.CARD_PAD, card._y)
    desc:SetWidth(card:GetWidth() - 2 * N.CARD_PAD)
    desc:SetHeight(48)
    desc:SetJustifyH("LEFT")
    desc:SetJustifyV("TOP")
    desc:SetTextColor(uc(M.color.textDim))
    desc:SetText(L["CI_DESC_" .. newCustom.type])
    card._y = card._y - 56
    card:SetHeight(-card._y + N.CARD_PAD)
    card:AddRow(ActionButton(card, L["Create"], function()
        local mode = N:Mode()
        local name = strtrim(newCustom.name or "")
        if name == "" then name = L["CI_TYPE_" .. newCustom.type] end
        local e = N.CustomIndicators.NewEntry(newCustom.type, name)
        table.insert(N.db[mode].customIndicators, e)
        N:Fire("NUCLEUS_SETTING_CHANGED", mode, mode .. ".customIndicators")
        newCustom.name = ""
        nameInput.Refresh()
        win:Hide()
        N.OpenCustomIndicator(e.id)
    end))
    child:AddCard(card)
    win.nameInput = nameInput
    return win
end

function N.ShowNewCustomIndicator()
    if not newCustomPopup then newCustomPopup = BuildNewCustomPopup() end
    newCustomPopup:SetShown(not newCustomPopup:IsShown())
end

local pingPopup

local function BuildPingPopup()
    local win, child = BuildPopupShell("NucleusPingPopup", L["Ping"], POPUP_W, 260)
    -- A persistent icon on your own frame while this is open, so size/position
    -- can be tuned without actually pinging anyone.
    win:SetScript("OnShow", function() if N.Ping then N.Ping.PreviewOn() end end)
    win:SetScript("OnHide", function() if N.Ping then N.Ping.PreviewOff() end end)
    local cardW = POPUP_W - 14 - 16

    local show = N.MakeCard(child, L["Ping"])
    show:AddRow(N.MakeCheckbox(show, L["Show pings on frames"],
        function() return N.db.ping.enabled end,
        function(v) N:Set("ping.enabled", v) end))
    show:AddRow(N.MakeSlider(show, L["Duration"], 1, 8, 0.5,
        function() return N.db.ping.duration end,
        function(v) N:Set("ping.duration", v) end))
    child:AddCard(show)

    local layout = N.MakeCard(child, L["Size & Position"])
    layout:AddRow(N.MakeSlider(layout, L["Size"], 0.5, 2.5, 0.05,
        function() return N.db.ping.scale end,
        function(v) N:Set("ping.scale", v) end))
    layout:AddRow(N.MakeSlider(layout, L["X offset"], -40, 40, 1,
        function() return N.db.ping.x end,
        function(v) N:Set("ping.x", N.Round(v)) end))
    layout:AddRow(N.MakeSlider(layout, L["Y offset"], -40, 40, 1,
        function() return N.db.ping.y end,
        function(v) N:Set("ping.y", N.Round(v)) end))
    child:AddCard(layout)

    AddPopupHint(child, cardW, L["PING_HINT"])
    return win
end

function N.ShowPingPopup()
    if not pingPopup then pingPopup = BuildPingPopup() end
    pingPopup:SetShown(not pingPopup:IsShown())
end

local previewSettingsPopup

local function BuildPreviewSettingsPopup()
    local win, child = BuildPopupShell("NucleusPreviewSettingsPopup", L["Preview"], POPUP_W, 300)
    local cardW = POPUP_W - 14 - 16

    local c = N.MakeCard(child, L["Preview"])
    c:AddRow(N.MakeCheckbox(c, L["Cycle health"],
        function() return N.db.previewSettings.cycleHealth end,
        function(v) N:Set("previewSettings.cycleHealth", v) end))
    c:AddRow(N.MakeSlider(c, L["Preview Health %"], 0, 100, 1,
        function() return N.db.previewSettings.healthPercent end,
        function(v) N:Set("previewSettings.healthPercent", N.Round(v)) end))
    c:AddRow(N.MakeCheckbox(c, L["Show all enabled indicators"],
        function() return N.db.previewSettings.showAllEnabled end,
        function(v) N:Set("previewSettings.showAllEnabled", v) end))
    child:AddCard(c)

    AddPopupHint(child, cardW, L["PREVIEW_SETTINGS_HINT"])
    return win
end

function N.ShowPreviewSettingsPopup()
    if not previewSettingsPopup then previewSettingsPopup = BuildPreviewSettingsPopup() end
    previewSettingsPopup:SetShown(not previewSettingsPopup:IsShown())
end

function N.ToggleOptions()
    if not window then BuildWindow() end
    window:SetShown(not window:IsShown())
end

N:On("NUCLEUS_DB_READY", function()
    SLASH_NUCLEUS1 = "/nucleus"
    SLASH_NUCLEUS2 = "/nuc"
    SlashCmdList.NUCLEUS = function() N.ToggleOptions() end
end)
