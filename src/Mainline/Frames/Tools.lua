local _, ns = ...
local N = ns.N
local M = N.Media
local L = N.L
local IsSecret = N.IsSecret

-- Utilities: three small free-standing displays, each with its own movable frame and settings
-- (N.db.tools.*):
--   readyPull  a Ready Check button and a Pull Timer button
--   battleRes  the raid's battle-res charges and recharge timer
--   marks      a bar of target markers and/or world markers
--
-- They can be dragged while "Move tools" is on (Options > Utilities) and are always shown then, so
-- they can be placed without being in a raid.

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

-- Show / hide that stays safe next to protected children in combat.
local function setVisible(host, on)
    if not InCombatLockdown() then host:SetShown(on) end
    host:SetAlpha(on and 1 or 0)
end

--------------------------------------------------------------------------------
-- host frames: position + drag handle
--------------------------------------------------------------------------------

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
    handle:SetFrameStrata("HIGH")
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

--------------------------------------------------------------------------------
-- Ready Check + Pull Timer
--------------------------------------------------------------------------------

local rp
local pullEnd, pullTotal

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
        if not pullEnd then return end
        local left = pullEnd - GetTime()
        if left <= 0 then
            pullEnd = nil
            bar:Hide()
            pull.text:SetText(L["Pull"])
            return
        end
        bar:SetMinMaxValues(0, pullTotal or left)
        bar:SetValue(left)
        pull.text:SetFormattedText("%.1f", left)
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
end

local function updateReadyPull()
    if not rp then return end
    local c = cfg("readyPull")
    if not c then return end
    local show = c.enabled and (unlocked() or (IsInGroup() and (c.onlyLeader == false or canControl())))
    setVisible(rp, show and true or false)
    rp.handle:SetShown(c.enabled and unlocked() and true or false)
end

local function onCountdown(_, total)
    pullTotal = total
    pullEnd = GetTime() + total
    if rp then rp.pull.bar:Show() end
end

--------------------------------------------------------------------------------
-- Battle Res
--------------------------------------------------------------------------------

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
    icon.tex:SetTexture((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(BR_SPELL)) or 136080)
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
end

function T.UpdateBattleRes()
    if not br then return end
    local c = cfg("battleRes")
    if not c then return end
    local info = C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(BR_SPELL)
    local show = c.enabled and (info ~= nil or unlocked())
    setVisible(br, show and true or false)
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

--------------------------------------------------------------------------------
-- Marks bar
--------------------------------------------------------------------------------

local mk
-- World marker button j shows the matching raid-target icon.
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
end

local function updateMarks()
    if not mk then return end
    local c = cfg("marks")
    if not c then return end
    local show = c.enabled and (unlocked() or (c.onlyLeader == false or canControl()))
    setVisible(mk, show and true or false)
    mk.handle:SetShown(c.enabled and unlocked() and true or false)
    local has = UnitExists("target") and true or false
    for _, b in ipairs(mk.target) do b:SetAlpha(has and 1 or 0.45) end
end

--------------------------------------------------------------------------------
-- wiring
--------------------------------------------------------------------------------

function T.Refresh()
    if not N.db or not N.db.tools then return end
    if not rp then buildReadyPull() end
    if not br then buildBattleRes() end
    if not mk then buildMarks() end
    layoutReadyPull()
    layoutBattleRes()
    layoutMarks()
    updateReadyPull()
    T.UpdateBattleRes()
    updateMarks()
end

local function softRefresh()
    if not rp then return end
    updateReadyPull()
    T.UpdateBattleRes()
    updateMarks()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({
    "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED", "PLAYER_ROLES_ASSIGNED",
    "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD", "SPELL_UPDATE_CHARGES",
}) do ev:RegisterEvent(e) end
pcall(ev.RegisterEvent, ev, "START_PLAYER_COUNTDOWN")
pcall(ev.RegisterEvent, ev, "CANCEL_PLAYER_COUNTDOWN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event, ...)
    if event == "START_PLAYER_COUNTDOWN" then
        local _, remaining, total = ...
        if remaining and not IsSecret(remaining) then onCountdown(remaining, total or remaining) end
    elseif event == "CANCEL_PLAYER_COUNTDOWN" then
        pullEnd = nil
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
