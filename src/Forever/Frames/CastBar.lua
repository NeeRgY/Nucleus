local _, ns = ...
local N = ns.N
local M = N.Media
local L = N.L
local Indicators = N.Indicators
local IsSecret = N.IsSecret

local UnitCastingInfo, UnitChannelInfo = UnitCastingInfo, UnitChannelInfo
local UnitCastingDuration, UnitChannelDuration = UnitCastingDuration, UnitChannelDuration
local UnitEmpoweredChannelDuration = UnitEmpoweredChannelDuration

local Enum_ = _G.Enum
local INTERP_IMMEDIATE = Enum_ and Enum_.StatusBarInterpolation and Enum_.StatusBarInterpolation.Immediate
local DIR_ELAPSED = Enum_ and Enum_.StatusBarTimerDirection and Enum_.StatusBarTimerDirection.ElapsedTime
local DIR_REMAINING = Enum_ and Enum_.StatusBarTimerDirection and Enum_.StatusBarTimerDirection.RemainingTime

local SAMPLE_SPELL = 2061
local FLASH_TIME = 0.8
local START_EVENTS = {
    UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_EMPOWER_START = true,
}

local DEFAULT_COLOR = { 1.00, 0.80, 0.20 }
local DEFAULT_CHANNEL = { 0.35, 0.65, 1.00 }
local DEFAULT_EMPOWER = { 0.65, 0.45, 1.00 }
local DEFAULT_INTERRUPT = { 1.00, 0.20, 0.20 }
local DEFAULT_LOCKED = { 0.60, 0.60, 0.60 }

local function create(b)
    local parent = b.overlay or b
    local host = CreateFrame("Frame", nil, parent)
    host:SetFrameLevel(parent:GetFrameLevel() + 6)
    host:EnableMouse(false)
    host:Hide()

    host.bg = host:CreateTexture(nil, "BACKGROUND")
    host.bg:SetAllPoints()
    host.bg:SetColorTexture(0, 0, 0, 0.6)

    host.border = {}
    for i = 1, 4 do
        host.border[i] = host:CreateTexture(nil, "BORDER")
        host.border[i]:Hide()
    end

    host.icon = host:CreateTexture(nil, "ARTWORK")
    host.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Plain StatusBar: SetTimerDuration with a secret duration breaks on a backdrop template.
    host.bar = CreateFrame("StatusBar", nil, host)
    host.bar:SetStatusBarTexture(M.flat)
    host.bar:SetMinMaxValues(0, 1)
    host.bar:SetValue(0)
    host.bar:EnableMouse(false)

    host.flash = host.bar:CreateTexture(nil, "ARTWORK", nil, 7)
    host.flash:SetAllPoints(host.bar)
    host.flash:Hide()

    host.spark = host.bar:CreateTexture(nil, "OVERLAY", nil, 3)
    host.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    host.spark:SetBlendMode("ADD")
    host.spark:Hide()

    host.name = N.FontString(host.bar, 9)
    host.name:SetJustifyH("LEFT")
    host.name:SetWordWrap(false)
    host.target = N.FontString(host.bar, 9)
    host.target:SetJustifyH("RIGHT")
    host.target:SetWordWrap(false)
    host.timer = N.FontString(host.bar, 9)
    host.timer:SetJustifyH("RIGHT")

    host:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        self.flash:Hide()
        self._flashUntil = nil
    end)
    return host
end

local function place(host, rel, selfPoint, relPoint, width, ox, oy)
    if width then
        host:SetWidth(width)
        host:SetPoint(selfPoint, rel, relPoint, ox, oy)
    else
        host:SetWidth(0)
        host:SetPoint(selfPoint .. "LEFT", rel, relPoint .. "LEFT", ox, oy)
        host:SetPoint(selfPoint .. "RIGHT", rel, relPoint .. "RIGHT", ox, oy)
    end
end

local function barTexturePath(b, o)
    local key = o.texture
    if key == nil or key == "same" then
        local a = N.db[b.groupKey].appearance
        key = a and a.barTexture
    end
    return M.BarTexturePath(key)
end

local function layout(b, host, o)
    local anchor = b.health or b
    local h = o.height or 10
    local ox, oy = o.x or 0, o.y or 0
    local width = (o.width or 0) > 0 and o.width or nil
    local bs = o.borderSize or 0
    local bc = o.borderColor or { 0, 0, 0 }
    local texPath = barTexturePath(b, o)
    local sig = table.concat({ tostring(h), tostring(o.position), tostring(ox), tostring(oy), tostring(width),
        tostring(o.showIcon), tostring(o.iconSide), tostring(o.bgAlpha), tostring(o.textSize), tostring(o.showTime),
        tostring(o.showTarget), tostring(o.showSpark), tostring(bs), tostring(bc[1]), tostring(bc[2]), tostring(bc[3]),
        tostring(texPath), tostring(anchor), tostring(b:GetWidth()) }, "|")
    if host._sig == sig then return end
    host._sig = sig

    host:ClearAllPoints()
    local pos = o.position
    if pos == "below" then
        place(host, b, "TOP", "BOTTOM", width, ox, oy)
    elseif pos == "above" then
        place(host, b, "BOTTOM", "TOP", width, ox, oy)
    elseif pos == "top" then
        place(host, anchor, "TOP", "TOP", width, ox, oy)
    else
        place(host, anchor, "BOTTOM", "BOTTOM", width, ox, oy)
    end
    host:SetHeight(h)
    host.bg:SetColorTexture(0, 0, 0, o.bgAlpha or 0.6)

    local t = host.border
    if bs > 0 then
        for i = 1, 4 do t[i]:SetColorTexture(bc[1], bc[2], bc[3], 1) end
        t[1]:ClearAllPoints(); t[1]:SetPoint("TOPLEFT", host); t[1]:SetPoint("TOPRIGHT", host); t[1]:SetHeight(bs)
        t[2]:ClearAllPoints(); t[2]:SetPoint("BOTTOMLEFT", host); t[2]:SetPoint("BOTTOMRIGHT", host); t[2]:SetHeight(bs)
        t[3]:ClearAllPoints(); t[3]:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -bs); t[3]:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, bs); t[3]:SetWidth(bs)
        t[4]:ClearAllPoints(); t[4]:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -bs); t[4]:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, bs); t[4]:SetWidth(bs)
        for i = 1, 4 do t[i]:Show() end
    else
        for i = 1, 4 do t[i]:Hide() end
    end

    local inner = math.max(1, h - 2 * bs)
    host.bar:ClearAllPoints()
    host.icon:ClearAllPoints()
    if o.showIcon then
        host.icon:SetSize(inner, inner)
        if o.iconSide == "right" then
            host.icon:SetPoint("TOPRIGHT", host, "TOPRIGHT", -bs, -bs)
            host.bar:SetPoint("TOPLEFT", host, "TOPLEFT", bs, -bs)
            host.bar:SetPoint("BOTTOMRIGHT", host.icon, "BOTTOMLEFT", -1, 0)
        else
            host.icon:SetPoint("TOPLEFT", host, "TOPLEFT", bs, -bs)
            host.bar:SetPoint("TOPLEFT", host.icon, "TOPRIGHT", 1, 0)
            host.bar:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -bs, bs)
        end
        host.icon:Show()
    else
        host.icon:Hide()
        host.bar:SetPoint("TOPLEFT", host, "TOPLEFT", bs, -bs)
        host.bar:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -bs, bs)
    end

    host.bar:SetStatusBarTexture(texPath)

    host.spark:ClearAllPoints()
    host.spark:SetPoint("CENTER", host.bar:GetStatusBarTexture(), "RIGHT", 0, 0)
    host.spark:SetSize(14, math.max(8, inner * 2.4))

    local size = o.textSize or 9
    host.name:SetFont(M.font, size, "OUTLINE")
    host.target:SetFont(M.font, size, "OUTLINE")
    host.timer:SetFont(M.font, size, "OUTLINE")
    host.timer:ClearAllPoints()
    host.timer:SetPoint("RIGHT", host.bar, "RIGHT", -3, 0)
    host.target:ClearAllPoints()
    if o.showTime ~= false then
        host.target:SetPoint("RIGHT", host.timer, "LEFT", -4, 0)
    else
        host.target:SetPoint("RIGHT", host.bar, "RIGHT", -3, 0)
    end
    host.target:SetWidth(math.max(24, (width or b:GetWidth() or 60) * 0.3))
    host.name:ClearAllPoints()
    host.name:SetPoint("LEFT", host.bar, "LEFT", 3, 0)
    if o.showTarget then
        host.name:SetPoint("RIGHT", host.target, "LEFT", -3, 0)
    elseif o.showTime ~= false then
        host.name:SetPoint("RIGHT", host.timer, "LEFT", -2, 0)
    else
        host.name:SetPoint("RIGHT", host.bar, "RIGHT", -3, 0)
    end
end

-- Values here can be secret, so they only go to sinks.
local function currentCast(unit)
    local isChannel
    if type((UnitCastingInfo(unit))) ~= "nil" then
        isChannel = false
    elseif type((UnitChannelInfo(unit))) ~= "nil" then
        isChannel = true
    else
        return nil
    end
    local duration, empowered
    if isChannel and UnitEmpoweredChannelDuration then
        duration = UnitEmpoweredChannelDuration(unit, true)
        if duration then empowered = true end
    end
    if not duration then
        if isChannel then
            duration = UnitChannelDuration and UnitChannelDuration(unit)
        else
            duration = UnitCastingDuration and UnitCastingDuration(unit)
        end
    end
    local spellId, locked
    if isChannel then
        locked = select(7, UnitChannelInfo(unit))
        spellId = select(8, UnitChannelInfo(unit))
    else
        locked = select(8, UnitCastingInfo(unit))
        spellId = select(9, UnitCastingInfo(unit))
    end
    return isChannel, duration, empowered, spellId, locked
end

local function tick(self, elapsed)
    self._t = (self._t or 0) + elapsed
    if self._t < 0.1 then return end
    self._t = 0
    local d = self.duration
    local remaining = d and d.GetRemainingDuration and d:GetRemainingDuration()
    if type(remaining) == "number" or IsSecret(remaining) then
        if self._both and d.GetTotalDuration then
            local total = d:GetTotalDuration()
            if type(total) == "number" or IsSecret(total) then
                self.timer:SetFormattedText("%.1f / %.1f", remaining, total)
                return
            end
        end
        self.timer:SetFormattedText("%.1f", remaining)
    else
        self.timer:SetText("")
    end
end


local function paintTarget(host, unit, o)
    if o.showTarget and UnitShouldDisplaySpellTargetName and UnitShouldDisplaySpellTargetName(unit) then
        local targetName = UnitSpellTargetName and UnitSpellTargetName(unit)
        if type(targetName) ~= "nil" then
            host.target:SetText(targetName)
            local color
            if UnitSpellTargetClass and C_ClassColor and C_ClassColor.GetClassColor then
                color = C_ClassColor.GetClassColor(UnitSpellTargetClass(unit))
            end
            if color then
                host.target:SetTextColor(color.r, color.g, color.b, 1)
            else
                host.target:SetTextColor(1, 1, 1, 1)
            end
            return
        end
    end
    host.target:SetText("")
end

local function castColor(b, o, isChannel, empowered)
    if o.classColor and b.class and not IsSecret(b.class) then
        local r, g, bl = N.ClassRGB(b.class)
        return { r, g, bl }
    end
    if isChannel then
        if empowered then return o.empowerColor or DEFAULT_EMPOWER end
        return o.channelColor or DEFAULT_CHANNEL
    end
    return o.color or DEFAULT_COLOR
end

local function showFlash(host, o, keepTick)
    local c = o.interruptColor or DEFAULT_INTERRUPT
    host.flash:SetColorTexture(c[1], c[2], c[3], 0.9)
    host.flash:Show()
    host.name:SetText(L["Interrupted"])
    host.target:SetText("")
    host.timer:SetText("")
    host.spark:Hide()
    -- The test loop needs its OnUpdate to survive the flash.
    if not keepTick then host:SetScript("OnUpdate", nil) end
    host:Show()
end

local function interrupted(host, o)
    showFlash(host, o)
    host._flashUntil = GetTime() + FLASH_TIME
    local token = (host._flashToken or 0) + 1
    host._flashToken = token
    C_Timer.After(FLASH_TIME, function()
        if host._flashToken == token and host._flashUntil then
            host._flashUntil = nil
            host:Hide()
        end
    end)
end

-- Preview loop: cast, channel, interrupt.
local MOCK_CAST, MOCK_CHANNEL = 2.5, 2.5
local MOCK_TOTAL = MOCK_CAST + MOCK_CHANNEL + FLASH_TIME

local function mockTick(self)
    local b = self._b
    local o = b and N.db[b.groupKey].indicators.castBar
    if not o then return end
    local t = (GetTime() - self._t0) % MOCK_TOTAL
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(SAMPLE_SPELL) or L["Cast Bar"]
    if t >= MOCK_CAST + MOCK_CHANNEL then
        if not self.flash:IsShown() then showFlash(self, o, true) end
        return
    end
    self.flash:Hide()
    local channel = t >= MOCK_CAST
    local span = channel and MOCK_CHANNEL or MOCK_CAST
    local into = channel and (t - MOCK_CAST) or t
    self.bar:SetValue(channel and (1 - into / span) or (into / span))
    local c = castColor(b, o, channel, false)
    self.bar:SetStatusBarColor(c[1], c[2], c[3], 1)
    self.spark:SetShown(o.showSpark and true or false)
    self.name:SetText(o.showName ~= false and name or "")
    local remain = span - into
    if o.showTime == false then
        self.timer:SetText("")
    elseif o.timeFormat == "both" then
        self.timer:SetFormattedText("%.1f / %.1f", remain, span)
    else
        self.timer:SetFormattedText("%.1f", remain)
    end
    if o.showTarget then
        self.target:SetText((UnitName("player")))
        self.target:SetTextColor(1, 1, 1, 1)
    else
        self.target:SetText("")
    end
end

local function paintMock(b, host, o)
    host.duration = nil
    host._b = b
    host.icon:SetTexture(C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(SAMPLE_SPELL) or 134400)
    if not host._t0 then host._t0 = GetTime() end
    host.bar:SetMinMaxValues(0, 1)
    host:SetScript("OnUpdate", mockTick)
    mockTick(host)
    host:Show()
end

local function paint(b, host, o)
    local isChannel, duration, empowered, spellId, locked = currentCast(b.unit)
    if isChannel == nil then
        host:Hide()
        return false
    end

    host.flash:Hide()
    host.bar:SetMinMaxValues(0, 1)

    if o.showIcon and spellId ~= nil and C_Spell and C_Spell.GetSpellTexture then
        host.icon:SetTexture(C_Spell.GetSpellTexture(spellId))
    end
    -- Only compare spellId with nil, it can be a secret number.
    if o.showName ~= false and spellId ~= nil and C_Spell and C_Spell.GetSpellName then
        host.name:SetText(C_Spell.GetSpellName(spellId))
    else
        host.name:SetText("")
    end
    paintTarget(host, b.unit, o)

    local c = castColor(b, o, isChannel, empowered)
    host.bar:SetStatusBarColor(c[1], c[2], c[3], 1)
    host.spark:SetShown(o.showSpark and true or false)
    -- locked can be a secret boolean, so it goes to a color sink, not an if.
    if o.markUninterruptible and locked ~= nil then
        local tex = host.bar:GetStatusBarTexture()
        local lc = o.uninterruptColor or DEFAULT_LOCKED
        if tex and tex.SetVertexColorFromBoolean then
            tex:SetVertexColorFromBoolean(locked,
                { r = lc[1], g = lc[2], b = lc[3], a = 1 },
                { r = c[1], g = c[2], b = c[3], a = 1 })
        elseif not IsSecret(locked) and locked == true then
            host.bar:SetStatusBarColor(lc[1], lc[2], lc[3], 1)
        end
    end

    host.duration = duration
    if duration and host.bar.SetTimerDuration then
        local direction = (isChannel and not empowered) and DIR_REMAINING or DIR_ELAPSED
        host.bar:SetTimerDuration(duration, INTERP_IMMEDIATE, direction)
    else
        host.bar:SetValue(0)
    end

    if o.showTime ~= false then
        host._both = (o.timeFormat == "both")
        host:SetScript("OnUpdate", tick)
    else
        host.timer:SetText("")
        host:SetScript("OnUpdate", nil)
    end
    host:Show()
    return true
end

Indicators.Register("castBar", {
    events = {
        "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET",
        "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
        "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
        "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP",
    },
    create = create,
    update = function(b, host, event, _, _, interruptedBy)
        local o = N.db[b.groupKey].indicators.castBar
        layout(b, host, o)

        if b._mock then
            paintMock(b, host, o)
            return
        end

        -- Only someone else interrupting gets the red flash, walking away just ends the bar.
        -- interruptedBy can be secret, ~= nil is safe.
        if event == "UNIT_SPELLCAST_INTERRUPTED" and host:IsShown() then
            if interruptedBy ~= nil and o.showInterrupt ~= false then
                interrupted(host, o)
            else
                host:Hide()
            end
            return
        end
        if host._flashUntil then
            if GetTime() < host._flashUntil and not START_EVENTS[event or ""] then return end
            host._flashUntil = nil
            host.flash:Hide()
        end

        if paint(b, host, o) then
            host._second = nil
            return
        end
        -- On the start event the cast data can still be empty, so check once more shortly after.
        if host._second then
            host._second = nil
            return
        end
        host._second = true
        C_Timer.After(0.2, function()
            if b:IsShown() then Indicators.UpdateOne(b, "castBar") end
        end)
    end,
})
