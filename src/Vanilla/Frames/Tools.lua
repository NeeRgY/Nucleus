local _, ns = ...
local N = ns.N
local M = N.Media
local L = N.L
local IsSecret = N.IsSecret

-- Utilities: ready & pull, battle res and marks, each with its own settings (N.db.tools.*).

local T = {}
N.Tools = T

local function cfg(name)
    return N.db and N.db.tools and N.db.tools[name]
end

local function unlocked()
    return T.moving == true
end

function T.SetMoving(on)
    T.moving = on and true or false
    if T.Refresh then T.Refresh() end
end

local function canControl()
    if not IsInGroup() then return true end
    return UnitIsGroupLeader("player") or (IsInRaid() and UnitIsGroupAssistant("player")) or false
end

-- Show only on mouseover: a child frame drives the fade so the host keeps its own OnUpdate.
local FADE_TIME = 0.25
local function fadeStep(driver, elapsed)
    local host = driver:GetParent()
    local top = host._maxAlpha or 1
    local want = host:IsMouseOver() and top or 0
    local a = host._fadeAlpha or 0
    if a == want then return end
    local step = elapsed / FADE_TIME * top
    a = want > a and math.min(want, a + step) or math.max(want, a - step)
    host._fadeAlpha = a
    host:SetAlpha(a)
end

-- Show / hide that stays safe next to protected children in combat.
local function setVisible(host, on, hoverOnly)
    if not InCombatLockdown() then host:SetShown(on) end
    local top = host._maxAlpha or 1
    local driver = host._fadeDriver
    if on and hoverOnly and not unlocked() then
        if not driver then
            driver = CreateFrame("Frame", nil, host)
            host._fadeDriver = driver
        end
        if not host._fading then
            host._fading = true
            host._fadeAlpha = host:GetAlpha()
            driver:SetScript("OnUpdate", fadeStep)
        end
        return
    end
    if host._fading then
        host._fading = nil
        driver:SetScript("OnUpdate", nil)
    end
    host._fadeAlpha = on and top or 0
    host:SetAlpha(host._fadeAlpha)
end


local hosts = {}

local function savePosition(host, c)
    local cx, cy = host:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and ux) then return end
    c.point = "CENTER"
    c.x = N.Round(cx - ux)
    c.y = N.Round(cy - uy)
end

local function loadPosition(host, c)
    host:ClearAllPoints()
    host:SetPoint("CENTER", UIParent, "CENTER", c.x or 0, c.y or 0)
end

local function makeHost(key, title)
    local host = CreateFrame("Frame", "NucleusTool_" .. key, UIParent)
    host:SetFrameStrata("MEDIUM")
    host:SetClampedToScreen(true)
    host:SetMovable(true)
    host:SetSize(60, 22)

    local handle = CreateFrame("Frame", nil, host)
    handle:SetPoint("BOTTOM", host, "TOP", 0, 4)
    handle:SetFrameStrata("MEDIUM")
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function()
        if not InCombatLockdown() then host:StartMoving() end
    end)
    handle:SetScript("OnDragStop", function()
        host:StopMovingOrSizing()
        local c = cfg(key)
        if c then savePosition(host, c) end
    end)
    N.SkinRound(handle, M.color.card, M.color.accent, true)
    local label = N.FontString(handle, 11)
    label:SetPoint("CENTER")
    label:SetTextColor(M.color.accentBright[1], M.color.accentBright[2], M.color.accentBright[3])
    label:SetText(title)
    handle:SetSize(label:GetStringWidth() + 24, 20)
    handle:Hide()
    host.handle = handle

    N.OnRecolor(function()
        N.SetPanelBorder(handle, M.color.accent)
        label:SetTextColor(M.color.accentBright[1], M.color.accentBright[2], M.color.accentBright[3])
    end)
    hosts[key] = host
    return host
end


-- Background, border, opacity and strata of a tool. Strata is only touched out of combat.
local function applyLook(host, c)
    if not InCombatLockdown() then host:SetFrameStrata(c.strata or "MEDIUM") end
    host._maxAlpha = c.alpha or 1
    if not host._fill then
        host._fill = host:CreateTexture(nil, "BACKGROUND")
        host._edges = {}
        for i = 1, 4 do host._edges[i] = host:CreateTexture(nil, "BACKGROUND", nil, 1) end
    end
    local fill, edges = host._fill, host._edges
    local show = c.backdrop and true or false
    local bw = math.max(0, c.border or 0)
    fill:SetShown(show)
    if show then
        local bg = c.background or { 0.05, 0.05, 0.07 }
        fill:ClearAllPoints()
        fill:SetPoint("TOPLEFT", host, "TOPLEFT", -3, 3)
        fill:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 3, -3)
        fill:SetColorTexture(bg[1], bg[2], bg[3], 0.85)
    end
    local edgesOn = show and bw > 0
    for i = 1, 4 do edges[i]:SetShown(edgesOn) end
    if not edgesOn then return end
    local bc = c.borderColor or { 0.2, 0.2, 0.25 }
    for i = 1, 4 do edges[i]:SetColorTexture(bc[1], bc[2], bc[3], 1) end
    edges[1]:ClearAllPoints()
    edges[1]:SetPoint("TOPLEFT", fill, "TOPLEFT", -bw, bw)
    edges[1]:SetPoint("TOPRIGHT", fill, "TOPRIGHT", bw, bw)
    edges[1]:SetHeight(bw)
    edges[2]:ClearAllPoints()
    edges[2]:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", -bw, -bw)
    edges[2]:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", bw, -bw)
    edges[2]:SetHeight(bw)
    edges[3]:ClearAllPoints()
    edges[3]:SetPoint("TOPLEFT", fill, "TOPLEFT", -bw, 0)
    edges[3]:SetPoint("BOTTOMLEFT", fill, "BOTTOMLEFT", -bw, 0)
    edges[3]:SetWidth(bw)
    edges[4]:ClearAllPoints()
    edges[4]:SetPoint("TOPRIGHT", fill, "TOPRIGHT", bw, 0)
    edges[4]:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", bw, 0)
    edges[4]:SetWidth(bw)
end

local rp
local pullEnd, pullTotal, finishUntil

local function pullMacros(c)
    local sec = c.pullTime or 10
    local m = c.pullMethod or "default"
    if m == "dbm" then return "/dbm pull " .. sec, "/dbm pull 0" end
    if m == "bw" then return "/pull " .. sec, "/pull 0" end
    if m == "mrt" then return "/ert pull " .. sec, "/ert pull 0" end
    return "/cd " .. sec, "/cd 0"
end

local function styleButton(b, label)
    N.SkinButton(b)
    b.text = N.FontString(b, 12)
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
end

local function buildReadyPull()
    rp = makeHost("readyPull", L["Ready & Pull"])

    local ready = CreateFrame("Button", nil, rp)
    ready:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    styleButton(ready, L["Ready"])
    ready:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            local poll = (C_PartyInfo and C_PartyInfo.InitiateRolePoll) or InitiateRolePoll
            if poll then poll() end
        else
            local check = (C_PartyInfo and C_PartyInfo.DoReadyCheck) or DoReadyCheck
            if check then check() end
        end
    end)
    N.SetTip(ready, L["Ready Check"], L["READY_BUTTON_TIP"])
    rp.ready = ready

    local pull = CreateFrame("Button", nil, rp, "SecureActionButtonTemplate")
    pull:RegisterForClicks("LeftButtonUp", "RightButtonUp", "LeftButtonDown", "RightButtonDown")
    pull:SetAttribute("type1", "macro")
    pull:SetAttribute("type2", "macro")
    styleButton(pull, L["Pull"])
    local bar = CreateFrame("StatusBar", nil, pull)
    bar:SetPoint("TOPLEFT", 2, -2)
    bar:SetPoint("BOTTOMRIGHT", -2, 2)
    bar:SetStatusBarTexture(M.flat)
    bar:SetFrameLevel(pull:GetFrameLevel() + 1)
    bar:Hide()
    pull.bar = bar
    local labelHost = CreateFrame("Frame", nil, pull)
    labelHost:SetAllPoints(pull)
    labelHost:SetFrameLevel(pull:GetFrameLevel() + 5)
    pull.text:SetParent(labelHost)
    N.SetTip(pull, L["Pull Timer"], L["PULL_BUTTON_TIP"])
    rp.pull = pull

    local acc = 0
    rp:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.05 then return end
        acc = 0
        if finishUntil and GetTime() >= finishUntil then
            finishUntil = nil
            pull.text:SetText(L["Pull"])
        end
        if not pullEnd then return end
        local c = cfg("readyPull") or {}
        local left = pullEnd - GetTime()
        if left <= 0 then
            pullEnd = nil
            bar:Hide()
            if c.pullFinishText == "go" then
                pull.text:SetText(L["Go!"])
                finishUntil = GetTime() + 1.5
            elseif c.pullFinishText == "zero" then
                pull.text:SetText("0")
                finishUntil = GetTime() + 1.5
            else
                pull.text:SetText(L["Pull"])
            end
            return
        end
        local total = pullTotal or left
        bar:SetMinMaxValues(0, total)
        bar:SetValue(left)
        local mode = c.pullTimerMode
        if mode == "elapsed" then
            pull.text:SetFormattedText("%.1f", math.max(0, total - left))
        elseif mode == "elapsedTotal" then
            pull.text:SetFormattedText("%.1f / %.0f", math.max(0, total - left), total)
        elseif mode == "remainingTotal" then
            pull.text:SetFormattedText("%.1f / %.0f", left, total)
        else
            pull.text:SetFormattedText("%.1f", left)
        end
    end)
end

local function layoutReadyPull()
    if not rp or InCombatLockdown() then return end
    local c = cfg("readyPull")
    if not c then return end
    local w, h, gap = c.width or 64, c.height or 22, c.gap or 4
    local vertical = c.orientation == "vertical"
    local list = {}
    if c.showReady ~= false then list[#list + 1] = rp.ready end
    if c.showPull ~= false then list[#list + 1] = rp.pull end
    rp.ready:Hide(); rp.pull:Hide()
    local prev
    for _, b in ipairs(list) do
        b:SetSize(w, h)
        b:ClearAllPoints()
        if prev then
            if vertical then b:SetPoint("TOP", prev, "BOTTOM", 0, -gap)
            else b:SetPoint("LEFT", prev, "RIGHT", gap, 0) end
        else
            b:SetPoint("TOPLEFT", rp, "TOPLEFT", 0, 0)
        end
        b:Show()
        prev = b
    end
    local n = math.max(1, #list)
    if vertical then rp:SetSize(w, n * h + (n - 1) * gap)
    else rp:SetSize(n * w + (n - 1) * gap, h) end
    local a, b2 = pullMacros(c)
    rp.pull:SetAttribute("macrotext1", a)
    rp.pull:SetAttribute("macrotext2", b2)
    rp.pull.bar:SetStatusBarColor(M.color.accent[1], M.color.accent[2], M.color.accent[3], 0.55)
    loadPosition(rp, c)
    applyLook(rp, c)
end

local function updateReadyPull()
    if not rp then return end
    local c = cfg("readyPull")
    if not c then return end
    local show = c.enabled and (unlocked() or (IsInGroup() and (c.onlyLeader == false or canControl())))
    setVisible(rp, show and true or false, c.fadeOut)
    rp.handle:SetShown(c.enabled and unlocked() and true or false)
end

local function onCountdown(_, total)
    pullTotal = total
    pullEnd = GetTime() + total
    if rp then rp.pull.bar:Show() end
end


local br
local BR_SPELL = 20484 -- Rebirth: its charge pool is the raid's shared one

local function buildBattleRes()
    br = makeHost("battleRes", L["Battle Res"])

    local icon = CreateFrame("Frame", nil, br)
    N.SkinRound(icon, M.color.base, M.color.line, true)
    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetPoint("TOPLEFT", 2, -2)
    icon.tex:SetPoint("BOTTOMRIGHT", -2, 2)
    icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.tex:SetTexture((N.Compat.Spell and N.Compat.Spell.GetSpellTexture and N.Compat.Spell.GetSpellTexture(BR_SPELL)) or 136080)
    icon.cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cd:SetPoint("TOPLEFT", 2, -2)
    icon.cd:SetPoint("BOTTOMRIGHT", -2, 2)
    icon.cd:SetDrawEdge(false)
    icon.cd:SetHideCountdownNumbers(true)
    br.icon = icon

    br.count = N.FontString(br, 16)
    br.timer = N.FontString(br, 11)
    br.timer:SetTextColor(M.color.textDim[1], M.color.textDim[2], M.color.textDim[3])

    local acc = 0.25
    br:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.25 then return end
        acc = 0
        T.UpdateBattleRes()
    end)
end

local function layoutBattleRes()
    if not br then return end
    local c = cfg("battleRes")
    if not c then return end
    local size = c.iconSize or 30
    br.icon:SetSize(size, size)
    br.icon:ClearAllPoints()
    br.icon:SetPoint("LEFT", br, "LEFT", 0, 0)
    br.count:SetFont(M.font, math.max(10, math.floor(size * 0.6)), "OUTLINE")
    br.count:ClearAllPoints()
    br.timer:SetFont(M.font, math.max(9, math.floor(size * 0.38)), "OUTLINE")
    br.timer:ClearAllPoints()
    if c.showTimer ~= false then
        br.count:SetPoint("TOPLEFT", br.icon, "TOPRIGHT", 6, 0)
        br.timer:SetPoint("BOTTOMLEFT", br.icon, "BOTTOMRIGHT", 6, 0)
        br.timer:Show()
        br:SetSize(size + 6 + math.max(18, size * 1.4), size)
    else
        br.count:SetPoint("LEFT", br.icon, "RIGHT", 6, 0)
        br.timer:Hide()
        br:SetSize(size + 6 + math.max(14, size * 0.7), size)
    end
    loadPosition(br, c)
    applyLook(br, c)
end

function T.UpdateBattleRes()
    if not br then return end
    local c = cfg("battleRes")
    if not c then return end
    local info = N.Compat.Spell and N.Compat.Spell.GetSpellCharges and N.Compat.Spell.GetSpellCharges(BR_SPELL)
    local show = c.enabled and (info ~= nil or unlocked())
    setVisible(br, show and true or false, c.fadeOut)
    br.handle:SetShown(c.enabled and unlocked() and true or false)
    if not show then return end

    local charges, start, dur
    if info then charges, start, dur = info.currentCharges, info.cooldownStartTime, info.cooldownDuration end
    if charges == nil then
        br.count:SetText("1")
        br.count:SetTextColor(0.25, 0.85, 0.35)
        br.timer:SetText("5:00")
        br.icon.cd:Clear()
        return
    end
    if IsSecret(charges) then
        br.count:SetFormattedText("%d", charges)
        br.count:SetTextColor(1, 1, 1)
    else
        br.count:SetText(charges)
        if charges > 0 then br.count:SetTextColor(0.25, 0.85, 0.35)
        else br.count:SetTextColor(0.90, 0.25, 0.25) end
    end
    if start and dur and not IsSecret(start) and not IsSecret(dur) and dur > 0 and start > 0 then
        local left = dur - (GetTime() - start)
        if left < 0 then left = 0 end
        br.timer:SetFormattedText("%d:%02d", math.floor(left / 60), math.floor(left % 60))
        br.icon.cd:SetCooldown(start, dur)
    else
        br.timer:SetText("")
        br.icon.cd:Clear()
    end
end


local mk
local WORLD_TO_ICON = { 6, 4, 3, 7, 1, 2, 5, 8 }

local function setIcon(tex, i)
    local idx = i - 1
    local col, row = idx % 4, math.floor(idx / 4)
    tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    tex:SetTexCoord(col * 0.25, (col + 1) * 0.25, row * 0.25, (row + 1) * 0.25)
end

local function buildMarks()
    mk = makeHost("marks", L["Marks"])
    mk.target, mk.world = {}, {}

    local function newButton(secure)
        local b = CreateFrame("Button", nil, mk, secure and "SecureActionButtonTemplate" or nil)
        N.SkinButton(b)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 3, -3)
        b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
        return b
    end

    for i = 1, 9 do
        local b = newButton(false)
        if i == 9 then
            b.icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
            b:SetScript("OnClick", function() SetRaidTarget("target", 0) end)
        else
            setIcon(b.icon, i)
            b:SetScript("OnClick", function()
                if not UnitExists("target") then return end
                if GetRaidTargetIndex("target") == i then SetRaidTarget("target", 0)
                else SetRaidTarget("target", i) end
            end)
        end
        mk.target[i] = b
    end

    for i = 1, 9 do
        local b = newButton(true)
        b:RegisterForClicks("AnyUp", "AnyDown")
        b:SetAttribute("type", "worldmarker")
        if i == 9 then
            b.icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
            b:SetAttribute("action", "clear")
        else
            setIcon(b.icon, WORLD_TO_ICON[i])
            b:SetAttribute("marker", i)
        end
        mk.world[i] = b
    end
end

local function layoutMarks()
    if not mk or InCombatLockdown() then return end
    local c = cfg("marks")
    if not c then return end
    local size, gap = c.size or 22, c.spacing or 2
    local vertical = c.orientation == "vertical"
    local count = (c.showClear ~= false) and 9 or 8
    local rows = {}
    if c.mode == "world" then rows = { mk.world }
    elseif c.mode == "both" then rows = { mk.target, mk.world }
    else rows = { mk.target } end

    for _, set in ipairs(mk.target) do set:Hide() end
    for _, set in ipairs(mk.world) do set:Hide() end
    for r, set in ipairs(rows) do
        for i = 1, count do
            local b = set[i]
            b:SetSize(size, size)
            b:ClearAllPoints()
            local along = (i - 1) * (size + gap)
            local across = (r - 1) * (size + gap)
            if vertical then b:SetPoint("TOPLEFT", mk, "TOPLEFT", across, -along)
            else b:SetPoint("TOPLEFT", mk, "TOPLEFT", along, -across) end
            b:Show()
        end
    end
    local long = count * size + (count - 1) * gap
    local short = #rows * size + (#rows - 1) * gap
    if vertical then mk:SetSize(short, long) else mk:SetSize(long, short) end
    loadPosition(mk, c)
    applyLook(mk, c)
end

local function updateMarks()
    if not mk then return end
    local c = cfg("marks")
    if not c then return end
    local show = c.enabled and (unlocked() or (c.onlyLeader == false or canControl()))
    setVisible(mk, show and true or false, c.fadeOut)
    mk.handle:SetShown(c.enabled and unlocked() and true or false)
    local has = UnitExists("target") and true or false
    for _, b in ipairs(mk.target) do b:SetAlpha(has and 1 or 0.45) end
end


-- Buff Tracker: who is missing which raid buff. A right click tells the group.
local bt
local btMissing = {} -- buff key -> { { name = ..., class = ... }, ... }
local btTicker, btLast
local updateBuffTracker

local function btScan(c)
    wipe(btMissing)
    local MB = N.Indicators
    if not MB.MissingFor then return end
    local function add(unit)
        local missing = MB.MissingFor(unit, c.buffs, c.trackAll)
        if not missing then return end
        local name = UnitName(unit)
        if not name or IsSecret(name) then return end
        local _, class = UnitClass(unit)
        if IsSecret(class) then class = nil end
        for _, key in ipairs(missing) do
            local list = btMissing[key]
            if not list then list = {}; btMissing[key] = list end
            list[#list + 1] = { name = name, class = class }
        end
    end
    if IsInRaid() then
        for i = 1, 40 do
            if UnitExists("raid" .. i) then add("raid" .. i) end
        end
    else
        add("player")
        for i = 1, 4 do
            if UnitExists("party" .. i) then add("party" .. i) end
        end
    end
end

local function btNames(list)
    local out = {}
    for _, e in ipairs(list) do out[#out + 1] = e.name end
    return out
end

-- Fills the placeholders of a message text and keeps it inside the chat's length limit.
local function btFill(template, players, buffs, count)
    local vars = { players = table.concat(players, ", "), buffs = table.concat(buffs, ", "), count = tostring(count) }
    local text = template:gsub("{(%a+)}", function(key) return vars[key] end)
    if #text > 250 then
        text = text:sub(1, 247)
        while #text > 0 and text:byte(-1) >= 0x80 do text = text:sub(1, -2) end
        text = text .. "..."
    end
    return text
end

-- One message for everything that is missing, or one per buff. Texts come from the settings or the language default.
local function btMessages(c)
    local MB = N.Indicators
    local limit = c.maxNames or 3
    local few = (c.msgFew and c.msgFew ~= "") and c.msgFew or L["BUFFTRACKER_FEW"]
    local many = (c.msgMany and c.msgMany ~= "") and c.msgMany or L["BUFFTRACKER_MANY"]
    local out = {}
    if c.msgMode == "perBuff" then
        for _, buff in ipairs(MB.missingBuffs) do
            local list = btMissing[buff.key]
            if list and #list > 0 then
                out[#out + 1] = btFill(#list <= limit and few or many, btNames(list), { MB.BuffLabel(buff) }, #list)
            end
        end
    else
        local names, buffs, seen = {}, {}, {}
        for _, buff in ipairs(MB.missingBuffs) do
            local list = btMissing[buff.key]
            if list and #list > 0 then
                buffs[#buffs + 1] = MB.BuffLabel(buff)
                for _, e in ipairs(list) do
                    if not seen[e.name] then seen[e.name] = true; names[#names + 1] = e.name end
                end
            end
        end
        if #buffs > 0 then out[1] = btFill(#names <= limit and few or many, names, buffs, #names) end
    end
    return out
end

-- Raid chat in a raid, otherwise the group chat (instance chat in a finder group).
local function btChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

function T.AnnounceBuffs()
    local c = cfg("buffTracker")
    if not c then return end
    local channel = btChannel()
    if not channel then N:Print(L["BUFFTRACKER_NOGROUP"]); return end
    local now = GetTime()
    if btLast and now - btLast < 5 then return end
    local messages = btMessages(c)
    if #messages == 0 then N:Print(L["BUFFTRACKER_NONE"]); return end
    local locked = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
    if locked then
        for _, text in ipairs(messages) do N:Print(text) end
        return
    end
    btLast = now
    for i, text in ipairs(messages) do
        local function send() pcall(SendChatMessage, text, channel) end
        if i == 1 then send() else C_Timer.After((i - 1) * 0.4, send) end
    end
end

local function btIcon(i)
    local ic = bt.icons[i]
    if ic then return ic end
    ic = CreateFrame("Frame", nil, bt)
    ic:EnableMouse(true)
    N.SkinRound(ic, M.color.base, M.color.line, true)
    ic.tex = ic:CreateTexture(nil, "ARTWORK")
    ic.tex:SetPoint("TOPLEFT", 2, -2)
    ic.tex:SetPoint("BOTTOMRIGHT", -2, 2)
    ic.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ic.count = N.FontString(ic, 12)
    ic.count:SetPoint("BOTTOMRIGHT", -2, 2)
    ic:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then T.AnnounceBuffs() end
    end)
    ic:SetScript("OnEnter", function(self)
        if not self.buff then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(N.Indicators.BuffLabel(self.buff))
        for _, e in ipairs(self.names or {}) do
            if type(e) == "table" and e.class then
                GameTooltip:AddLine(e.name, N.ClassRGB(e.class))
            else
                GameTooltip:AddLine(type(e) == "table" and e.name or tostring(e), 1, 1, 1)
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["BUFFTRACKER_CLICK"], 0.55, 0.65, 0.80)
        GameTooltip:Show()
    end)
    ic:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bt.icons[i] = ic
    return ic
end

local function buildBuffTracker()
    bt = makeHost("buffTracker", L["Buff Tracker"])
    bt.icons = {}
    bt.ok = N.FontString(bt, 12)
    bt.ok:SetPoint("LEFT", bt, "LEFT", 6, 0)
    bt.ok:SetTextColor(0.25, 0.85, 0.35)
    bt.ok:SetText(L["BUFFTRACKER_OK"])
    bt.ok:Hide()
    bt:EnableMouse(true)
    bt:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then T.AnnounceBuffs() end
    end)
end

local function layoutBuffTracker()
    if not bt then return end
    local c = cfg("buffTracker")
    if not c then return end
    loadPosition(bt, c)
    applyLook(bt, c)
end

updateBuffTracker = function()
    if not bt then return end
    local c = cfg("buffTracker")
    if not c then return end
    if c.enabled and not btTicker then
        btTicker = C_Timer.NewTicker(2, function() updateBuffTracker() end)
    elseif not c.enabled and btTicker then
        btTicker:Cancel()
        btTicker = nil
    end
    local moving = unlocked()
    local combat = N.InCombat()
    bt.handle:SetShown(c.enabled and moving and true or false)
    if not c.enabled or (combat and c.hideInCombat ~= false and not moving) then
        setVisible(bt, false, c.fadeOut)
        return
    end
    if not combat then btScan(c) end

    local MB = N.Indicators
    local idle = c.idle or "hide"
    local size, spacing = c.iconSize or 30, c.spacing or 4
    local vertical = c.orientation == "vertical"
    local shown = {}
    for _, buff in ipairs(MB.missingBuffs) do
        local list = btMissing[buff.key]
        local missing = list and #list > 0
        if missing then
            shown[#shown + 1] = { buff = buff, names = list }
        elseif idle == "icons" and MB.Trackable(buff, c.buffs, c.trackAll) then
            shown[#shown + 1] = { buff = buff, names = {}, idle = true }
        end
    end
    if #shown == 0 and moving then
        for i = 1, math.min(3, #MB.missingBuffs) do
            shown[#shown + 1] = { buff = MB.missingBuffs[i], names = { "..." } }
        end
    end

    for _, ic in ipairs(bt.icons) do ic:Hide() end
    bt.ok:Hide()
    if #shown == 0 then
        if idle ~= "text" then
            setVisible(bt, false, c.fadeOut)
            return
        end
        bt.ok:Show()
        bt:SetSize(math.max(60, bt.ok:GetStringWidth() + 12), size)
        setVisible(bt, true, c.fadeOut)
        return
    end

    for i, item in ipairs(shown) do
        local ic = btIcon(i)
        ic.buff, ic.names = item.buff, item.names
        ic:SetSize(size, size)
        ic:ClearAllPoints()
        local off = (i - 1) * (size + spacing)
        if vertical then
            ic:SetPoint("TOPLEFT", bt, "TOPLEFT", 0, -off)
        else
            ic:SetPoint("TOPLEFT", bt, "TOPLEFT", off, 0)
        end
        ic.tex:SetTexture(MB.BuffTexture(item.buff))
        ic.tex:SetDesaturated(item.idle and true or false)
        ic:SetAlpha(item.idle and 0.5 or 1)
        ic.count:SetFont(M.font, math.max(10, math.floor(size * 0.45)), "OUTLINE")
        ic.count:SetText(item.idle and "" or #item.names)
        ic.count:SetShown(c.showCount ~= false and not item.idle)
        ic:Show()
    end
    local total = #shown * size + (#shown - 1) * spacing
    if vertical then bt:SetSize(size, total) else bt:SetSize(total, size) end
    setVisible(bt, true, c.fadeOut)
end

function T.Refresh()
    if not N.db or not N.db.tools then return end
    if not rp then buildReadyPull() end
    if not br then buildBattleRes() end
    if not mk then buildMarks() end
    if not bt then buildBuffTracker() end
    layoutReadyPull()
    layoutBattleRes()
    layoutMarks()
    layoutBuffTracker()
    updateReadyPull()
    T.UpdateBattleRes()
    updateMarks()
    updateBuffTracker()
end

local function softRefresh()
    if not rp then return end
    updateReadyPull()
    T.UpdateBattleRes()
    updateMarks()
    updateBuffTracker()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({
    "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "PLAYER_ROLES_ASSIGNED",
    "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD", "SPELL_UPDATE_CHARGES", "PLAYER_REGEN_DISABLED",
}) do N.SafeRegister(ev, e) end
pcall(ev.RegisterEvent, ev, "START_PLAYER_COUNTDOWN")
pcall(ev.RegisterEvent, ev, "CANCEL_PLAYER_COUNTDOWN")
N.SafeRegister(ev, "PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event, ...)
    if event == "START_PLAYER_COUNTDOWN" then
        local _, remaining, total = ...
        if remaining and not IsSecret(remaining) then onCountdown(remaining, total or remaining) end
    elseif event == "CANCEL_PLAYER_COUNTDOWN" then
        pullEnd, finishUntil = nil, nil
        if rp then rp.pull.bar:Hide(); rp.pull.text:SetText(L["Pull"]) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        T.Refresh()
    else
        softRefresh()
    end
end)

N:On("NUCLEUS_DB_READY", function() C_Timer.After(0, T.Refresh) end)
N:On("NUCLEUS_PROFILE_CHANGED", function() C_Timer.After(0, T.Refresh) end)
N:On("NUCLEUS_SETTING_CHANGED", function(_, _, path)
    if path and path:find("^tools") then T.Refresh() end
end)

-- Death Report: announces group member deaths. Nothing is registered while it is off.
local deathState, sent = {}, {}
local deathActive = false
local deathFrame = CreateFrame("Frame")

local function groupChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function inEncounter()
    if IsEncounterInProgress then return IsEncounterInProgress() end
    return UnitAffectingCombat("player")
end

local function announce(name, class, c)
    if c.output == "group" and (not c.leaderOnly or canControl()) then
        local now = GetTime()
        while sent[1] and now - sent[1] > 10 do table.remove(sent, 1) end
        if #sent >= 5 then return end
        local locked = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
        local channel = groupChannel()
        if channel and not locked and pcall(SendChatMessage, L["DEATH_MSG"]:format(name), channel) then
            sent[#sent + 1] = now
            return
        end
    end
    local r, g, b = N.ClassRGB(class)
    N:Print(L["DEATH_MSG"]:format(("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), name)))
end

local function observeDeath(unit)
    if type(unit) ~= "string" then return end
    if not (unit == "player" or unit:find("^party%d") or unit:find("^raid%d")) then return end
    local guid = UnitGUID(unit)
    if not guid or IsSecret(guid) then return end
    local dead = UnitIsDeadOrGhost(unit)
    if dead == nil or IsSecret(dead) then return end
    local feign = UnitIsFeignDeath and UnitIsFeignDeath(unit)
    if IsSecret(feign) then return end
    if feign then dead = false end
    dead = dead and true or false
    local previous = deathState[guid]
    deathState[guid] = dead
    if not (dead and previous == false) then return end

    local c = cfg("deathReport")
    if not (c and c.enabled) then return end
    if c.encounterOnly and not inEncounter() then return end
    if c.rolesOnly then
        local role = UnitGroupRolesAssigned(unit)
        if IsSecret(role) or (role ~= "TANK" and role ~= "HEALER") then return end
    end
    local name = UnitName(unit)
    if not name or IsSecret(name) then return end
    local _, class = UnitClass(unit)
    if IsSecret(class) then class = nil end
    announce(name, class, c)
end

local function rescanDeaths()
    wipe(deathState)
    observeDeath("player")
    for i = 1, 4 do if UnitExists("party" .. i) then observeDeath("party" .. i) end end
    for i = 1, 40 do if UnitExists("raid" .. i) then observeDeath("raid" .. i) end end
end

deathFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_HEALTH" or event == "UNIT_FLAGS" then
        observeDeath(unit)
    else
        rescanDeaths()
    end
end)

local function configureDeath()
    local c = cfg("deathReport")
    local want = (c and c.enabled) and true or false
    if want == deathActive then return end
    deathActive = want
    if want then
        for _, e in ipairs({ "UNIT_HEALTH", "UNIT_FLAGS", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }) do
            deathFrame:RegisterEvent(e)
        end
        rescanDeaths()
    else
        deathFrame:UnregisterAllEvents()
        wipe(deathState)
        wipe(sent)
    end
end

N:On("NUCLEUS_DB_READY", function() C_Timer.After(0, configureDeath) end)
N:On("NUCLEUS_SETTING_CHANGED", function(_, _, path)
    if path and path:find("^tools") then configureDeath() end
end)
