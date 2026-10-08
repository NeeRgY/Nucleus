local _, ns = ...
local N = ns.N
local M = N.Media
local L = N.L

local function uc(c) return c[1], c[2], c[3], c[4] or 1 end

-- Nucleus' own message dialog in the options window's look. Replaces the game's StaticPopup for
-- every question or notice (reload, delete confirmations, name prompts, the copy-link box). One
-- dialog is up at a time, the next waits in a queue.
--
--   N.Dialog.Show{ title, text, input = { text, maxLetters, readOnly },
--                  buttons = { { text, onClick(inputText), primary }, ... } }
--   N.Dialog.Confirm(text, onYes [, { title, yes, no }])
--   N.Dialog.Prompt(text, default, onAccept(text))
--   N.Dialog.Reload(text)

local D = {}
N.Dialog = D

local WIDTH, PAD = 400, 18
local BTN_H, BTN_W = 26, 112

local frame
local queue = {}
local current

local function build()
    local f = CreateFrame("Frame", "NucleusDialog", UIParent)
    f._nucFace = true
    f:SetAllPoints(UIParent)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(200)
    f:EnableMouse(true)
    f:EnableKeyboard(true)
    f:Hide()

    local dim = f:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints()
    dim:SetColorTexture(0, 0, 0, 0.55)

    local box = CreateFrame("Frame", nil, f)
    box:SetWidth(WIDTH)
    box:SetPoint("CENTER", 0, 60)
    box:EnableMouse(true)
    N.SkinRound(box, M.color.windowBg, M.color.line)
    N.AddShadow(box, 14, 0.7, -5)
    f.box = box

    f.bar = box:CreateTexture(nil, "ARTWORK")
    f.bar:SetSize(3, 14)
    f.bar:SetPoint("TOPLEFT", box, "TOPLEFT", PAD, -PAD)
    f.bar:SetColorTexture(uc(M.color.accent))

    f.title = N.FontString(box, 14)
    f.title:SetPoint("LEFT", f.bar, "RIGHT", 8, 0)
    f.title:SetTextColor(uc(M.color.text))

    f.msg = N.FontString(box, 12)
    f.msg:SetPoint("TOPLEFT", box, "TOPLEFT", PAD, -(PAD + 28))
    f.msg:SetWidth(WIDTH - 2 * PAD)
    f.msg:SetJustifyH("LEFT")
    f.msg:SetJustifyV("TOP")
    f.msg:SetWordWrap(true)
    f.msg:SetTextColor(uc(M.color.text))

    local inbox = CreateFrame("Frame", nil, box)
    inbox:SetHeight(24)
    inbox:SetPoint("LEFT", box, "LEFT", PAD, 0)
    inbox:SetPoint("RIGHT", box, "RIGHT", -PAD, 0)
    N.SkinRound(inbox, M.color.base, M.color.line, true)
    local edit = CreateFrame("EditBox", nil, inbox)
    edit:SetPoint("TOPLEFT", 6, 0)
    edit:SetPoint("BOTTOMRIGHT", -6, 0)
    edit:SetFont(M.fontUI, 12, "")
    N.RegisterFont(edit, 12, "")
    edit:SetTextColor(uc(M.color.text))
    edit:SetAutoFocus(false)
    edit:SetScript("OnEditFocusGained", function() N.SetPanelBorder(inbox, M.color.accent) end)
    edit:SetScript("OnEditFocusLost", function() N.SetPanelBorder(inbox, M.color.line) end)
    f.inbox, f.edit = inbox, edit

    f.buttons = {}
    return f
end

local function makeButton(f, i)
    local b = CreateFrame("Button", nil, f.box)
    b:SetSize(BTN_W, BTN_H)
    N.SkinButton(b)
    b.label = N.FontString(b, 12)
    b.label:SetPoint("CENTER")
    f.buttons[i] = b
    return b
end

local close

local function press(spec, btn)
    local text = spec.input and frame.edit:GetText() or nil
    close()
    if btn and btn.onClick then
        local ok, err = pcall(btn.onClick, text)
        if not ok then N:Print("|cffff5555dialog error:|r " .. tostring(err)) end
    end
end

local function open(spec)
    frame = frame or build()
    current = spec
    local f = frame

    f.title:SetText(spec.title or L["Nucleus"])
    f.msg:SetText(spec.text or "")
    local h = PAD + 28 + math.max(14, f.msg:GetStringHeight()) + 14

    if spec.input then
        f.inbox:ClearAllPoints()
        f.inbox:SetPoint("TOPLEFT", f.box, "TOPLEFT", PAD, -h)
        f.inbox:SetPoint("TOPRIGHT", f.box, "TOPRIGHT", -PAD, -h)
        f.edit:SetMaxLetters(spec.input.maxLetters or 0)
        f.edit:SetText(spec.input.text or "")
        f.inbox:Show()
        h = h + 24 + 14
    else
        f.inbox:Hide()
        f.edit:SetText("")
    end

    local list = spec.buttons
    if not list or #list == 0 then list = { { text = L["Close"], primary = true } } end
    for i, def in ipairs(list) do
        local b = f.buttons[i] or makeButton(f, i)
        b.onClick = def.onClick
        b.label:SetText(def.text or "")
        b:SetWidth(math.max(BTN_W, b.label:GetStringWidth() + 28))
        N.SetPanelBorder(b, def.primary and M.color.accent or M.color.line)
        b:ClearAllPoints()
        b:SetScript("OnClick", function() press(spec, b) end)
        b:Show()
    end
    for i = #list + 1, #f.buttons do f.buttons[i]:Hide() end
    local x = -PAD
    for i = #list, 1, -1 do
        local b = f.buttons[i]
        b:ClearAllPoints()
        b:SetPoint("TOPRIGHT", f.box, "TOPRIGHT", x, -h)
        x = x - b:GetWidth() - 8
    end
    h = h + BTN_H + PAD

    f.box:SetHeight(h)
    f.primary = list[#list]
    f.cancel = list[1]
    f.spec = spec

    f.edit:SetScript("OnEnterPressed", function()
        if spec.input and spec.input.readOnly then press(spec, f.cancel) else press(spec, f.buttons[#list]) end
    end)
    f.edit:SetScript("OnEscapePressed", function() press(spec, #list > 1 and f.buttons[1] or f.buttons[#list]) end)
    if spec.input and spec.input.readOnly then
        local fixed = spec.input.text or ""
        f.edit:SetScript("OnTextChanged", function(self)
            if self:GetText() ~= fixed then self:SetText(fixed); self:HighlightText() end
        end)
    else
        f.edit:SetScript("OnTextChanged", nil)
    end

    f:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            press(spec, #list > 1 and self.buttons[1] or self.buttons[#list])
        elseif key == "ENTER" and not spec.input then
            self:SetPropagateKeyboardInput(false)
            press(spec, self.buttons[#list])
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    f:Show()
    if spec.input then
        f.edit:SetFocus()
        f.edit:HighlightText()
    end
end

close = function()
    if not frame then return end
    frame:Hide()
    frame.edit:ClearFocus()
    current = nil
    local nextSpec = table.remove(queue, 1)
    if nextSpec then open(nextSpec) end
end

function D.Show(spec)
    if current then
        queue[#queue + 1] = spec
    else
        open(spec)
    end
end

function D.Confirm(text, onYes, opts)
    opts = opts or {}
    D.Show({
        title = opts.title or L["Confirm"],
        text = text,
        buttons = {
            { text = opts.no or L["No"] },
            { text = opts.yes or L["Yes"], primary = true, onClick = function() if onYes then onYes() end end },
        },
    })
end

function D.Prompt(text, default, onAccept, title)
    D.Show({
        title = title or L["Nucleus"],
        text = text,
        input = { text = default or "", maxLetters = 32 },
        buttons = {
            { text = L["Cancel"] },
            { text = L["Accept"], primary = true, onClick = function(v) if onAccept then onAccept(v) end end },
        },
    })
end

function D.Reload(text)
    D.Show({
        title = L["Nucleus"],
        text = text,
        buttons = {
            { text = L["Later"] },
            { text = L["Reload now"], primary = true, onClick = function() ReloadUI() end },
        },
    })
end

-- The client cannot open web links: show the address in a field to copy.
function D.Link(label, url)
    D.Show({
        title = L["Nucleus"],
        text = label,
        input = { text = url or "", readOnly = true },
        buttons = { { text = L["Close"], primary = true } },
    })
end
