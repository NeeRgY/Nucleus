local _, ns = ...
local N = ns.N
local M = N.Media
local L = N.L

-- Options > Profile: manage profiles, auto-switch rules, export / import and
-- backups. One panel (cards stacked), rebuilt in place whenever the profile
-- list, the active profile or the current situation changes.

local function uc(c) return c[1], c[2], c[3], c[4] or 1 end

local panel -- the profile tab's panel, once built

--------------------------------------------------------------------------------
-- small helpers
--------------------------------------------------------------------------------

local function Hint(card, text, color)
    local fs = N.FontString(card, 11)
    fs:SetPoint("TOPLEFT", card, "TOPLEFT", N.CARD_PAD, card._y)
    fs:SetWidth(card:GetWidth() - 2 * N.CARD_PAD)
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(uc(color or M.color.textDim))
    fs:SetText(text)
    fs:SetHeight(fs:GetStringHeight() + 4)
    card._y = card._y - fs:GetHeight() - 8
    card:SetHeight(-card._y + N.CARD_PAD - 8)
    return fs
end

-- A row of equally wide buttons: specs = { { label, onClick }, ... }
local function ButtonRow(card, specs)
    local row = CreateFrame("Frame", nil, card)
    row._rowHeight = 26
    local gap = 6
    local inner = card:GetWidth() - 2 * N.CARD_PAD
    local w = math.floor((inner - gap * (#specs - 1)) / #specs)
    local prev
    for _, s in ipairs(specs) do
        local b = CreateFrame("Button", nil, row)
        b:SetSize(w, 26)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", gap, 0)
        else b:SetPoint("LEFT", row, "LEFT", 0, 0) end
        N.SkinButton(b)
        local fs = N.FontString(b, 12)
        fs:SetPoint("CENTER")
        fs:SetText(s[1])
        b:SetScript("OnClick", s[2])
        b.fs = fs
        s.button = b
        prev = b
    end
    return row
end

-- Multi-line text box in a rounded frame with its own scroll bar.
local function MakeTextArea(parent, height)
    local box = CreateFrame("Frame", nil, parent)
    box._rowHeight = height
    N.SkinRound(box, M.color.base, M.color.line, true)

    local scroll, child = N.MakeScroll(box, -3)
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -12, 6)
    scroll:HookScript("OnSizeChanged", function(_, w)
        if w and w > 0 then child:SetWidth(w) end
    end)

    local edit = CreateFrame("EditBox", nil, child)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFont(M.font, 11, "")
    N.RegisterFont(edit, 11, "")
    edit:SetTextColor(uc(M.color.text))
    edit:SetPoint("TOPLEFT")
    edit:SetPoint("TOPRIGHT")
    edit:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    edit:SetScript("OnEditFocusGained", function() N.SetPanelBorder(box, M.color.accent) end)
    edit:HookScript("OnEditFocusLost", function() N.SetPanelBorder(box, M.color.line) end)
    local function fit()
        child:SetHeight(math.max(edit:GetHeight(), scroll:GetHeight()))
    end
    edit:HookScript("OnTextChanged", fit)

    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)
    box.edit = edit
    return box
end

--------------------------------------------------------------------------------
-- name prompt / confirm dialogs
--------------------------------------------------------------------------------

local function PromptName(text, default, onAccept)
    N.Dialog.Prompt(text, default, onAccept)
end

--------------------------------------------------------------------------------
-- export / import popups
--------------------------------------------------------------------------------

local exportPopup, importPopup

local function ShowExport()
    local P = N.Profiles
    local name = P.Current()
    local str = P.Export(name)
    if not str then
        N:Print(L["IMPORT_ERR_LIBS"])
        return
    end
    if not exportPopup then
        local win, child = N.BuildPopupShell("NucleusProfileExport", L["Export Profile"], 440, 300)
        local card = N.MakeCard(child, L["Profile"])
        local area = MakeTextArea(card, 150)
        card:AddRow(area)
        win.area = area
        child:AddCard(card)
        local hint = N.FontString(child, 11)
        hint:SetPoint("TOPLEFT", child, "TOPLEFT", 2, child._y)
        hint:SetWidth(400)
        hint:SetJustifyH("LEFT")
        hint:SetTextColor(uc(M.color.textDim))
        hint:SetText(L["EXPORT_HINT"])
        hint:SetHeight(hint:GetStringHeight() + 4)
        child:SetHeight(-child._y + hint:GetHeight() + 8)
        -- read-only: restore the text if anything edits it
        area.edit:SetScript("OnTextChanged", function(self, user)
            if user and win.exportText and self:GetText() ~= win.exportText then
                self:SetText(win.exportText)
                self:HighlightText()
            end
        end)
        exportPopup = win
    end
    exportPopup.exportText = str
    exportPopup.area.edit:SetText(str)
    exportPopup:Show()
    exportPopup.area.edit:SetFocus()
    exportPopup.area.edit:HighlightText()
end

local function ShowImport()
    local P = N.Profiles
    if not importPopup then
        local win, child = N.BuildPopupShell("NucleusProfileImport", L["Import Profile"], 440, 420)
        local card = N.MakeCard(child, L["Import Profile"])

        local area = MakeTextArea(card, 150)
        card:AddRow(area)
        win.area = area

        local status = N.FontString(card, 11)
        status:SetPoint("TOPLEFT", card, "TOPLEFT", N.CARD_PAD, card._y)
        status:SetWidth(card:GetWidth() - 2 * N.CARD_PAD)
        status:SetJustifyH("LEFT")
        status:SetText(L["IMPORT_PASTE"])
        status:SetTextColor(uc(M.color.textDim))
        win.status = status
        card._y = card._y - 22

        local nameInput = N.MakeTextInput(card, L["Profile name"],
            function() return win.nameValue or "" end,
            function(v) win.nameValue = v; win.autoName = false end)
        card:AddRow(nameInput)
        win.nameInput = nameInput

        local importBtn = CreateFrame("Button", nil, card)
        importBtn._rowHeight = 28
        N.SkinButton(importBtn)
        local ifs = N.FontString(importBtn, 12)
        ifs:SetPoint("CENTER")
        ifs:SetText(L["Import"])
        win.importBtn = importBtn
        win.importFS = ifs
        card:AddRow(importBtn)

        child:AddCard(card)

        local function validate()
            local ok, res = P.Decode(area.edit:GetText())
            win.data = nil
            if area.edit:GetText() == "" then
                status:SetText(L["IMPORT_PASTE"])
                status:SetTextColor(uc(M.color.textDim))
            elseif ok then
                win.data = res
                status:SetText(L["IMPORT_OK"]:format(res.name))
                status:SetTextColor(0.55, 0.90, 0.55)
                if not win.nameValue or win.nameValue == "" or win.autoName then
                    win.nameValue = P.UniqueName(res.name)
                    win.autoName = true
                    nameInput.Refresh()
                end
            else
                status:SetText(L[res])
                status:SetTextColor(1.0, 0.45, 0.45)
            end
            importBtn:SetAlpha(win.data and 1 or 0.4)
        end
        area.edit:HookScript("OnTextChanged", validate)
        win.validate = validate

        importBtn:SetScript("OnClick", function()
            if not win.data then return end
            local name = P.CleanName(win.nameValue) or P.UniqueName(win.data.name)
            local function doImport()
                local final = P.Import(win.data, name)
                N:Print(L["IMPORT_DONE"]:format(final))
                win:Hide()
            end
            if P.Exists(name) then
                N.Dialog.Confirm(L["IMPORT_REPLACE"]:format(name), doImport)
            else
                doImport()
            end
        end)
        importPopup = win
    end
    importPopup.nameValue, importPopup.autoName, importPopup.data = "", true, nil
    importPopup.area.edit:SetText("")
    importPopup.nameInput.Refresh()
    importPopup.importBtn:SetAlpha(0.4)
    importPopup:Show()
    importPopup.area.edit:SetFocus()
end

--------------------------------------------------------------------------------
-- Import from Cell: a Cell "Profile" export string becomes a new Nucleus profile
-- (the mapping lives in Core/CellImport.lua).
--------------------------------------------------------------------------------

local cellPopup

-- A button that steps through `names` on click: "label: value".
local function CycleRow(card, label, onChange)
    local b = CreateFrame("Button", nil, card)
    b._rowHeight = 26
    N.SkinButton(b)
    local fs = N.FontString(b, 12)
    fs:SetPoint("CENTER")
    b.names, b.index = {}, 1
    function b.Refresh()
        fs:SetText(label .. ": " .. tostring(b.names[b.index] or "-"))
    end
    b:SetScript("OnClick", function()
        if #b.names == 0 then return end
        b.index = b.index % #b.names + 1
        b.Refresh()
        if onChange then onChange() end
    end)
    b.Refresh()
    return b
end

local function pick(names, wanted)
    for i, n in ipairs(names) do if n == wanted then return i end end
    return nil
end

local function ShowCellImport()
    local P, CI = N.Profiles, N.CellImport
    if not CI then N:Print("Cell import: new file not loaded yet - restart the game once."); return end
    if not cellPopup then
        local win, child = N.BuildPopupShell("NucleusCellImport", L["Import from Cell"], 440, 560)
        local card = N.MakeCard(child, L["Import from Cell"])
        local area = MakeTextArea(card, 120)
        card:AddRow(area)
        win.area = area

        local status = N.FontString(card, 11)
        status:SetPoint("TOPLEFT", card, "TOPLEFT", N.CARD_PAD, card._y)
        status:SetWidth(card:GetWidth() - 2 * N.CARD_PAD)
        status:SetJustifyH("LEFT")
        status:SetTextColor(uc(M.color.textDim))
        status:SetText(L["CELL_PASTE"])
        win.status = status
        card._y = card._y - 22

        win.partyRow = CycleRow(card, L["Layout for party"])
        win.raidRow = CycleRow(card, L["Layout for raid"])
        card:AddRow(win.partyRow)
        card:AddRow(win.raidRow)

        local nameInput = N.MakeTextInput(card, L["Profile name"],
            function() return win.nameValue or "" end,
            function(v) win.nameValue = v end)
        card:AddRow(nameInput)
        win.nameInput = nameInput

        local btn = CreateFrame("Button", nil, card)
        btn._rowHeight = 28
        N.SkinButton(btn)
        local bfs = N.FontString(btn, 12)
        bfs:SetPoint("CENTER")
        bfs:SetText(L["Import"])
        card:AddRow(btn)
        win.importBtn = btn

        local report = N.FontString(card, 11)
        report:SetPoint("TOPLEFT", card, "TOPLEFT", N.CARD_PAD, card._y - 4)
        report:SetWidth(card:GetWidth() - 2 * N.CARD_PAD)
        report:SetJustifyH("LEFT")
        report:SetJustifyV("TOP")
        report:SetHeight(150)
        win.report = report
        card._y = card._y - 160
        card:SetHeight(-card._y + N.CARD_PAD)
        child:AddCard(card)

        local function setRows(show)
            win.partyRow:SetShown(show); win.raidRow:SetShown(show)
            win.nameInput:SetShown(show); btn:SetShown(show)
        end
        win.setRows = setRows

        local function validate()
            win.data = nil
            report:SetText("")
            local text = area.edit:GetText()
            if text == "" then
                status:SetText(L["CELL_PASTE"]); status:SetTextColor(uc(M.color.textDim))
                setRows(false)
                return
            end
            local ok, data, version = CI.Decode(text)
            if not ok then
                status:SetText(L[data]); status:SetTextColor(1.0, 0.45, 0.45)
                setRows(false)
                return
            end
            win.data = data
            local names = CI.Layouts(data)
            win.partyRow.names, win.raidRow.names = names, names
            win.partyRow.index = pick(names, "default") or 1
            win.raidRow.index = pick(names, "Raid") or pick(names, "default") or 1
            win.partyRow.Refresh(); win.raidRow.Refresh()
            status:SetText(L["CELL_OK"]:format(version or 0, #names))
            status:SetTextColor(0.55, 0.90, 0.55)
            if not win.nameValue or win.nameValue == "" then
                win.nameValue = P.UniqueName("Cell")
                nameInput.Refresh()
            end
            setRows(#names > 0)
        end
        area.edit:HookScript("OnTextChanged", validate)

        btn:SetScript("OnClick", function()
            if not win.data then return end
            local party = win.partyRow.names[win.partyRow.index]
            local raid = win.raidRow.names[win.raidRow.index]
            local ok, profile, rep = pcall(CI.Convert, win.data, party, raid)
            if not ok then
                status:SetText(L["CELL_FAIL"]); status:SetTextColor(1.0, 0.45, 0.45)
                N:Print("Cell import: " .. tostring(profile))
                return
            end
            local name = P.CleanName(win.nameValue) or P.UniqueName("Cell")
            local final = P.Import({ name = name, profile = profile }, name)

            local lines = { "|cff8cd98c" .. L["CELLR_DONE"] .. "|r" }
            for _, key in ipairs(rep.done) do lines[#lines + 1] = "  + " .. L[key] end
            if rep.ccCount then
                lines[#lines + 1] = "  + " .. L["CELLR_CLICKS"]:format(rep.ccCount, rep.ccDropped or 0)
            end
            if #rep.skipped > 0 then
                lines[#lines + 1] = "|cffe6b34d" .. L["CELLR_SKIPPED"] .. "|r " .. table.concat(rep.skipped, ", ")
            end
            lines[#lines + 1] = "|cff8f98a8" .. L["CELLR_NOTE"] .. "|r"
            win.report:SetText(table.concat(lines, "\n"))
            N:Print(L["IMPORT_DONE"]:format(final))
        end)
        cellPopup = win
    end
    cellPopup.nameValue, cellPopup.data = "", nil
    cellPopup.area.edit:SetText("")
    cellPopup.nameInput.Refresh()
    cellPopup.setRows(false)
    cellPopup:Show()
    cellPopup.area.edit:SetFocus()
end

----
-- the panel
--------------------------------------------------------------------------------

local function ProfileOptions(withNoChange)
    local out = {}
    if withNoChange then
        out[#out + 1] = { value = "__none", text = L["(no change)"] }
    end
    for _, name in ipairs(N.Profiles.List()) do
        out[#out + 1] = { value = name, text = name }
    end
    if withNoChange then
        out[#out + 1] = { value = N.Profiles.HIDE, text = L["Hide frames"] }
    end
    return out
end

local function BuildProfiles(p)
    local P = N.Profiles

    local c = N.MakeCard(p, L["Profiles"])
    c:AddRow(N.MakeDropdown(c, L["Active profile"], ProfileOptions(false),
        function() return P.Current() end,
        function(v)
            -- Picking one by hand also pauses the automatic switch for a moment:
            -- the next situation change (zone, group, spec) re-evaluates it.
            P.Switch(v)
        end))
    c:AddRow(ButtonRow(c, {
        { L["New"], function()
            PromptName(L["PROFILE_NAME_NEW"], "", function(text)
                local name = P.Create(P.CleanName(text) or "", nil)
                if name then P.Switch(name) else N:Print(L["PROFILE_NAME_TAKEN"]) end
            end)
        end },
        { L["Copy"], function()
            PromptName(L["PROFILE_NAME_COPY"], P.UniqueName(P.Current()), function(text)
                local name = P.Create(P.CleanName(text) or "", P.Current())
                if name then P.Switch(name) else N:Print(L["PROFILE_NAME_TAKEN"]) end
            end)
        end },
        { L["Rename"], function()
            PromptName(L["PROFILE_NAME_RENAME"], P.Current(), function(text)
                if not P.Rename(P.Current(), text) then N:Print(L["PROFILE_NAME_TAKEN"]) end
            end)
        end },
        { L["Delete"], function()
            if #P.List() <= 1 then N:Print(L["PROFILE_LAST"]); return end
            local name = P.Current()
            N.Dialog.Confirm(L["PROFILE_DELETE"]:format(name),
                function() P.Delete(name) end)
        end },
    }))
    p:AddCard(c)
end

local function CurrentSummary()
    local P = N.Profiles
    local situation = P.GetSituation()
    local label = situation
    for _, s in ipairs(P.SITUATIONS) do
        if s.key == situation then label = L[s.label] break end
    end
    local _, role, specName = P.GetSpec()
    local tbl, by = P.GetAssignmentTable()
    local target = tbl and tbl[situation]
    local who = (by == "spec" and specName) or (role and L[role]) or "?"
    local result
    if target == P.HIDE then result = L["Hide frames"]
    elseif target and P.Exists(target) then result = target
    else result = L["(no change)"] end
    return ("%s  |  %s  ->  %s"):format(label, who, result)
end

local function BuildAutoSwitch(p)
    local P = N.Profiles
    local a = P.AutoSwitch()

    local c = N.MakeCard(p, L["Auto Switch"])
    c:AddRow(N.MakeCheckbox(c, L["Switch profiles automatically"],
        function() return a.enabled end,
        function(v) a.enabled = v and true or false; P.Evaluate(); N:Fire("NUCLEUS_PROFILES_CHANGED") end))

    -- Role / Spec: which table the rules below edit.
    local _, by, specID, role = P.GetAssignmentTable()
    local _, _, specName = P.GetSpec()
    local sw = CreateFrame("Frame", nil, c)
    sw._rowHeight = 26
    local lab = N.FontString(sw, 12)
    lab:SetPoint("LEFT", 0, 0)
    lab:SetText(L["Rules apply per"])
    lab:SetTextColor(uc(M.color.textDim))
    local track = CreateFrame("Frame", nil, sw)
    track:SetSize(2 * 120 + 8, 26)
    track:SetPoint("RIGHT", sw, "RIGHT", 0, 0)
    N.SkinRound(track, M.color.segment, M.color.line, true)
    local prev
    for _, d in ipairs({
        { "role", role and (L["Role"] .. ": " .. L[role]) or L["Role"] },
        { "spec", specName and (L["Spec"] .. ": " .. specName) or L["Spec"] },
    }) do
        local b = CreateFrame("Button", nil, track)
        b:SetSize(120, 20)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0)
        else b:SetPoint("LEFT", track, "LEFT", 3, 0) end
        local pill = b:CreateTexture(nil, "ARTWORK")
        pill:SetTexture(M.tex.roundSm)
        if pill.SetTextureSliceMargins then pill:SetTextureSliceMargins(5, 5, 5, 5) end
        pill:SetAllPoints()
        pill:SetVertexColor(uc(M.color.navActive))
        pill:SetShown(by == d[1])
        local fs = N.FontString(b, 11)
        fs:SetPoint("CENTER")
        fs:SetText(d[2])
        fs:SetWordWrap(false)
        fs:SetTextColor(uc(by == d[1] and { 1, 1, 1, 1 } or M.color.textDim))
        b:SetScript("OnClick", function()
            if d[1] == by then return end
            P.SetBySpec(d[1] == "spec")
        end)
        prev = b
    end
    c:AddRow(sw)

    -- Rules: one row per situation.
    local tbl = P.GetAssignmentTable()
    local options = ProfileOptions(true)
    for _, s in ipairs(P.SITUATIONS) do
        local row = CreateFrame("Frame", nil, c)
        row._rowHeight = 24
        local fs = N.FontString(row, 12)
        fs:SetPoint("LEFT", 0, 0)
        fs:SetText(L[s.label])
        local dd = N.MakeDropdown(row, nil, options,
            function() return (tbl and tbl[s.key]) or "__none" end,
            function(v) P.SetAssignment(s.key, v ~= "__none" and v or nil) end)
        dd:SetParent(row)
        dd:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
        dd:SetWidth(230)
        dd:SetHeight(24)
        c:AddRow(row)
    end

    Hint(c, L["Now"] .. ":  " .. CurrentSummary(), M.color.accentBright)
    p:AddCard(c)
end

local function BuildShare(p)
    local P = N.Profiles
    local c = N.MakeCard(p, L["Export / Import"])
    c:AddRow(ButtonRow(c, {
        { L["Export active profile"], ShowExport },
        { L["Import profile"], ShowImport },
        { L["Import from Cell"], ShowCellImport },
    }))
    Hint(c, L["SHARE_HINT"])
    p:AddCard(c)

    local b = N.MakeCard(p, L["Backups"])
    local list = P.Backups()
    if #list == 0 then
        Hint(b, L["BACKUPS_NONE"])
    else
        for i, entry in ipairs(list) do
            local row = CreateFrame("Frame", nil, b)
            row._rowHeight = 24
            local fs = N.FontString(row, 12)
            fs:SetPoint("LEFT", 0, 0)
            fs:SetPoint("RIGHT", row, "RIGHT", -92, 0)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            fs:SetText(("%s   |cff8f98a8%s - %s|r"):format(entry.name, entry.time, L[entry.reason or ""] ))
            local btn = CreateFrame("Button", nil, row)
            btn:SetSize(84, 24)
            btn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            N.SkinButton(btn)
            local bf = N.FontString(btn, 12)
            bf:SetPoint("CENTER")
            bf:SetText(L["Restore"])
            btn:SetScript("OnClick", function()
                N.Dialog.Confirm(L["BACKUP_RESTORE"]:format(entry.name),
                    function()
                        local ok, name = P.RestoreBackup(i)
                        if ok then N:Print(L["BACKUP_RESTORED"]:format(name)) end
                    end)
            end)
            b:AddRow(row)
        end
    end
    p:AddCard(b)
end

local function Build(p)
    for _, child in ipairs({ p:GetChildren() }) do
        child:Hide()
        child:SetParent(nil)
    end
    p._y = -4
    BuildProfiles(p)
    BuildAutoSwitch(p)
    local cc = N.MakeCard(p, L["Copy settings between Party and Raid"])
    cc:AddRow(ButtonRow(cc, { { L["Open copy window"], function() N.ShowCopyPopup() end } }))
    Hint(cc, L["COPY_HINT"])
    p:AddCard(cc)
    BuildShare(p)
    if N.OptionsResize then N.OptionsResize(p) end
end

function N.BuildProfilePanel(p)
    panel = p
    Build(p)
end

local function refresh()
    if panel and panel:IsShown() then Build(panel) end
end

N:On("NUCLEUS_PROFILES_CHANGED", refresh)
N:On("NUCLEUS_PROFILE_CHANGED", refresh)
N:On("NUCLEUS_AUTOSWITCH_EVALUATED", refresh)
