local RAT = assert(_G.RAT, "RAT_Core.lua must load first")

local WIDTH, HEIGHT = 720, 520
local ROW_HEIGHT = 24

local function Duration(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours, minutes = math.floor(seconds / 3600), math.floor((seconds % 3600) / 60)
    if hours > 0 then return string.format("%dh %02dm", hours, minutes) end
    return string.format("%dm %02ds", minutes, seconds % 60)
end

local function Date(value)
    return date and value and date("%Y-%m-%d %H:%M", value) or tostring(value or "?")
end

local function SettingsText(session)
    local settings = session and session.settings
    if not settings then return "Original limits not recorded (older session)." end
    local text = string.format("Join %ds | action gap %ds | resurrection %ds",
        settings.joinGrace, settings.activeGap, settings.reviveGrace)
    if session.warnings and session.warnings.settingsUnknown then text = text .. " | Earlier limits unknown" end
    return text
end

function RAT:GetSortedMembers(session)
    local members = {}
    for _, member in pairs(session.members or {}) do members[#members + 1] = member end
    local key = self.sortBy or "percent"
    local ascending = RAT_DB.ui.sortAscending == true
    local function Value(member)
        local eligible, idle, percent, longest = RAT:GetMetrics(member)
        return ({name=member.key or member.name or "", eligible=eligible, idle=idle,
            percent=percent, longest=longest, packs=member.packs or 0})[key] or percent
    end
    table.sort(members, function(a, b)
        local av, bv = Value(a), Value(b)
        if av ~= bv then
            if ascending then return av < bv end
            return av > bv
        end
        return (a.key or a.name or "") < (b.key or b.name or "")
    end)
    return members
end

local function ColorForPercent(percent)
    if percent <= 5 then return 0.25, 1, 0.35 end
    if percent <= 30 then return 1, 0.82, 0.15 end
    return 1, 0.2, 0.2
end

local function SetShown(frame, shown)
    if shown then frame:Show() else frame:Hide() end
end

local function SkinButton(skins, button)
    if skins and skins.HandleButton then pcall(skins.HandleButton, skins, button) end
end

function RAT:TrySkinElvUI()
    local frame = self.frame
    if not frame or frame.elvuiSkinned or not ElvUI or not ElvUI[1] then return end
    local E = ElvUI[1]
    if not frame.SetTemplate or not pcall(frame.SetTemplate, frame, "Transparent") then return end
    frame.elvuiSkinned = true
    local skins
    if E.GetModule then
        local ok, module = pcall(E.GetModule, E, "Skins")
        if ok then skins = module end
    end
    for _, button in ipairs(frame.buttons or {}) do SkinButton(skins, button) end
    local bar = frame.scroll and (frame.scroll.ScrollBar or _G[frame.scroll:GetName() .. "ScrollBar"])
    if skins and skins.HandleScrollBar and bar then pcall(skins.HandleScrollBar, skins, bar) end
end

local function NewCell(row, width, point, relative, offset)
    local cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell:SetWidth(width)
    cell:SetJustifyH(point == "LEFT" and "LEFT" or "CENTER")
    cell:SetPoint(point == "LEFT" and "LEFT" or "LEFT", relative or row, relative and "RIGHT" or "LEFT", offset or 0, 0)
    return cell
end

function RAT:BuildFrame()
    if self.frame then return self.frame end
    local frame = CreateFrame("Frame", "RATMainFrame", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    local position = RAT_DB.ui.position
    local anchors = {CENTER=true, TOP=true, BOTTOM=true, LEFT=true, RIGHT=true,
        TOPLEFT=true, TOPRIGHT=true, BOTTOMLEFT=true, BOTTOMRIGHT=true}
    if type(position) == "table" and anchors[position.point] and anchors[position.relativePoint]
        and type(position.x) == "number" and type(position.y) == "number" then
        frame:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
    else frame:SetPoint("CENTER") end
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        RAT_DB.ui.position = {point=point, relativePoint=relativePoint, x=x, y=y}
    end)
    frame:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize=24, insets={left=6,right=6,top=6,bottom=6} })
    frame:SetBackdropColor(0, 0, 0, 0.92)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 18, -16)
    frame.title:SetText("RAT - Raid Activity Tracker")
    frame.summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.summary:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -8)
    frame.summary:SetWidth(WIDTH - 70)
    frame.summary:SetJustifyH("LEFT")
    frame.note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.note:SetPoint("TOPLEFT", frame.summary, "BOTTOMLEFT", 0, -5)
    frame.note:SetWidth(WIDTH - 50)
    frame.note:SetJustifyH("LEFT")
    frame.note:SetText("")

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", -4, -4)

    local headers = {
        { "Player", 18, 170, "LEFT", "name" }, { "Trash time", 188, 90, "CENTER", "eligible" },
        { "Idle", 278, 75, "CENTER", "idle" }, { "Idle %", 353, 65, "CENTER", "percent" },
        { "Longest", 418, 80, "CENTER", "longest" }, { "Packs", 498, 50, "CENTER", "packs" },
        { "Current", 548, 140 },
    }
    frame.headers = {}
    for _, data in ipairs(headers) do
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", data[2], -92)
        label:SetWidth(data[3])
        label:SetJustifyH(data[4] or "CENTER")
        label:SetText(data[1])
        frame.headers[#frame.headers + 1] = label
        if data[5] then
            local sortKey = data[5]
            local button = CreateFrame("Button", nil, frame)
            button:SetPoint("TOPLEFT", data[2], -86)
            button:SetSize(data[3], 24)
            button:SetScript("OnClick", function() RAT:SetSort(sortKey, true) end)
            button:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine("Click to sort; click again to reverse")
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", function() GameTooltip:Hide() end)
            label.sortKey = sortKey
        end
    end

    frame.scroll = CreateFrame("ScrollFrame", "RATRosterScrollFrame", frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", 14, -112)
    frame.scroll:SetPoint("BOTTOMRIGHT", -34, 86)
    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.content:SetSize(WIDTH - 55, 1)
    frame.scroll:SetScrollChild(frame.content)
    frame.rows = {}

    frame.toggle = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.toggle:SetSize(120, 22)
    frame.toggle:SetPoint("BOTTOMLEFT", 16, 18)
    frame.toggle:SetScript("OnClick", function()
        if RAT.activeSession then RAT:EndSession("manual") else RAT:StartSession(true) end
    end)
    frame.reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.reset:SetSize(120, 22)
    frame.reset:SetPoint("LEFT", frame.toggle, "RIGHT", 8, 0)
    frame.reset:SetText("Reset Current")
    if StaticPopupDialogs then
        StaticPopupDialogs.RAT_RESET_SESSION = {
            text = "Reset all activity totals in the current RAT session?",
            button1 = YES or "Yes", button2 = CANCEL or "Cancel", timeout = 0,
            whileDead = true, hideOnEscape = true, preferredIndex = 3,
            OnAccept = function() RAT:ResetCurrentSession() end,
        }
    end
    frame.reset:SetScript("OnClick", function()
        if StaticPopup_Show and StaticPopupDialogs and StaticPopupDialogs.RAT_RESET_SESSION then
            StaticPopup_Show("RAT_RESET_SESSION")
        else
            RAT:ResetCurrentSession()
        end
    end)
    frame.previous = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.previous:SetSize(90, 22)
    frame.previous:SetPoint("LEFT", frame.reset, "RIGHT", 28, 0)
    frame.previous:SetText("Previous")
    frame.previous:SetScript("OnClick", function()
        frame.historyIndex = math.min(#RAT:GetSessions(), (frame.historyIndex or 1) + 1)
        RAT:RefreshUI()
    end)
    frame.next = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.next:SetSize(90, 22)
    frame.next:SetPoint("LEFT", frame.previous, "RIGHT", 8, 0)
    frame.next:SetText("Next")
    frame.next:SetScript("OnClick", function()
        frame.historyIndex = math.max(1, (frame.historyIndex or 1) - 1)
        RAT:RefreshUI()
    end)
    frame.position = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.position:SetPoint("LEFT", frame.next, "RIGHT", 12, 0)
    frame.position:SetWidth(40)
    frame.position:SetJustifyH("CENTER")
    frame.settings = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.settings:SetSize(75, 22)
    frame.settings:SetPoint("BOTTOMLEFT", 16, 48)
    frame.settings:SetText("Settings")
    frame.settings:SetScript("OnClick", function() RAT:ShowSettings() end)
    frame.export = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.export:SetSize(85, 22)
    frame.export:SetPoint("BOTTOMRIGHT", -16, 48)
    frame.export:SetText("Export")
    frame.export:SetScript("OnClick", function() RAT:ShowExport() end)
    frame.csv = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.csv:SetSize(85, 22)
    frame.csv:SetPoint("RIGHT", frame.export, "LEFT", -8, 0)
    frame.csv:SetText("CSV")
    frame.csv:SetScript("OnClick", function() RAT:ShowCSV() end)
    frame.packDetails = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.packDetails:SetSize(100, 22)
    frame.packDetails:SetPoint("LEFT", frame.settings, "RIGHT", 8, 0)
    frame.packDetails:SetText("Pack details")
    frame.packDetails:SetScript("OnClick", function() RAT:ShowPackDetails() end)
    frame.buttons = { frame.toggle, frame.reset, frame.previous, frame.next, frame.settings, frame.export, frame.csv, frame.packDetails }
    frame.historyIndex = 1
    frame:SetScript("OnShow", function() RAT:TrySkinElvUI(); RAT:RefreshUI() end)
    if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "RATMainFrame" end
    frame:Hide()
    self.frame = frame
    self:TrySkinElvUI()
    return frame
end

local function EnsureRow(frame, index)
    local row = frame.rows[index]
    if row then return row end
    row = CreateFrame("Frame", nil, frame.content)
    row:SetSize(WIDTH - 58, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetTexture(1, 1, 1, index % 2 == 0 and 0.045 or 0.015)
    row.name = NewCell(row, 165, "LEFT", nil, 4)
    row.trash = NewCell(row, 90, "CENTER", row.name, 0)
    row.idle = NewCell(row, 75, "CENTER", row.trash, 0)
    row.percent = NewCell(row, 65, "CENTER", row.idle, 0)
    row.longest = NewCell(row, 80, "CENTER", row.percent, 0)
    row.packs = NewCell(row, 50, "CENTER", row.longest, 0)
    row.current = NewCell(row, 125, "CENTER", row.packs, 0)
    row:EnableMouse(true)
    row:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and self.member then RAT:ShowMemberDetails(self.member) end
    end)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Click for idle intervals")
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.rows[index] = row
    return row
end

local function CurrentState(member, selected)
    if selected ~= RAT.activeSession then return "-", 0.65, 0.65, 0.65 end
    if member.online == false then return "Offline", 0.45, 0.45, 0.45 end
    if member.dead then return "Dead", 0.75, 0.2, 0.2 end
    if not RAT.packStartedAt then return "Waiting", 0.65, 0.65, 0.65 end
    local now = math.min(GetTime(), RAT.lastEvidenceAt or GetTime())
    local reviveUntil = RAT.reviveGraceUntil and RAT.reviveGraceUntil[member.key]
    if reviveUntil and now < reviveUntil then
        return "Res grace " .. math.ceil(reviveUntil - now) .. "s", 0.35, 0.75, 1
    end
    local started = RAT.activityAt[member.key] or now
    if reviveUntil then started = math.max(started, reviveUntil) end
    local elapsed = math.max(0, now - started)
    local threshold = RAT.hasParticipated[member.key] and RAT:GetSessionSetting("activeGap") or RAT:GetSessionSetting("joinGrace")
    if elapsed >= threshold then return "IDLE " .. math.floor(elapsed) .. "s", 1, 0.2, 0.2 end
    if elapsed > 3 then return "Grace " .. math.ceil(threshold - elapsed) .. "s", 1, 0.82, 0.15 end
    return "Active", 0.25, 1, 0.35
end

function RAT:RefreshUI(preferred)
    local frame = self.frame
    if not frame then return end
    local sessions = self:GetSessions()
    if preferred then
        for index, session in ipairs(sessions) do if session == preferred then frame.historyIndex = index end end
    end
    frame.historyIndex = math.max(1, math.min(frame.historyIndex or 1, math.max(1, #sessions)))
    local session = sessions[frame.historyIndex]
    frame.note:SetText(session and SettingsText(session) .. ". Click headers to sort; players for intervals." or "")
    for _, label in ipairs(frame.headers) do
        if label.sortKey then
            if label.sortKey == self.sortBy then label:SetTextColor(0.3, 1, 0.5)
            else label:SetTextColor(1, 0.82, 0) end
        end
    end
    frame.position:SetText(#sessions > 0 and (frame.historyIndex .. " / " .. #sessions) or "0 / 0")
    frame.previous:SetEnabled(frame.historyIndex < #sessions)
    frame.next:SetEnabled(frame.historyIndex > 1)
    frame.toggle:SetText(self.activeSession and "End Session" or "Start Session")
    frame.reset:SetEnabled(self.activeSession ~= nil and session == self.activeSession)
    frame.export:SetEnabled(session ~= nil)
    frame.csv:SetEnabled(session ~= nil)
    frame.packDetails:SetEnabled(session ~= nil)
    if not session then
        frame.summary:SetText("No raid activity session recorded yet.")
        for _, row in ipairs(frame.rows) do row:Hide() end
        return
    end
    local state = session == self.activeSession and "ACTIVE" or "FINISHED"
    local warnings = session.warnings or {}
    local warningText = warnings.reload and " | Resumed" or ""
    if (warnings.logGaps or 0) > 0 then warningText = warningText .. " | Log gaps " .. warnings.logGaps end
    local packs, seconds, running = self:GetSessionTotals(session)
    frame.summary:SetText(string.format("%s | %s | %s | %d packs | %s trash%s%s",
        session.instance or "Unknown", state,
        date("%m-%d %H:%M", session.startedAt or self.WallTime()),
        packs, Duration(seconds), running and " (includes current)" or "", warningText))
    local members = self:GetSortedMembers(session)
    for index, member in ipairs(members) do
        local row = EnsureRow(frame, index)
        row.member = member
        local eligible, idle, percent, longest = self:GetMetrics(member)
        row.name:SetText(member.name or member.key)
        local color = RAID_CLASS_COLORS and member.class and RAID_CLASS_COLORS[member.class]
        row.name:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
        row.trash:SetText(Duration(eligible))
        row.idle:SetText(Duration(idle))
        row.percent:SetText(percent .. "%")
        row.percent:SetTextColor(ColorForPercent(percent))
        row.longest:SetText(Duration(longest))
        row.packs:SetText(tostring(member.packs or 0))
        local text, r, g, b = CurrentState(member, session)
        row.current:SetText(text)
        row.current:SetTextColor(r, g, b)
        row.bg:SetVertexColor(percent > 30 and 0.7 or 1, percent > 30 and 0.12 or 1, percent > 30 and 0.12 or 1, percent > 30 and 0.16 or (index % 2 == 0 and 0.045 or 0.015))
        row:Show()
    end
    for index = #members + 1, #frame.rows do frame.rows[index]:Hide() end
    frame.content:SetHeight(math.max(1, #members * ROW_HEIGHT))
end

local function SelectedSession()
    local sessions = RAT:GetSessions()
    local frame = RAT.frame
    return sessions[frame and frame.historyIndex or 1]
end

function RAT:ShowSettings()
    local popup = self.settingsPopup
    if not popup then
        popup = CreateFrame("Frame", "RATSettingsFrame", UIParent)
        popup:SetSize(340, 250)
        popup:SetPoint("CENTER")
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:EnableMouse(true)
        popup:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize=24,
            insets={left=6,right=6,top=6,bottom=6} })
        popup:SetBackdropColor(0, 0, 0, 0.96)
        local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 20, -18)
        title:SetText("RAT settings (seconds)")
        local note = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        note:SetPoint("TOPLEFT", 22, -42)
        note:SetText("Applied when starting or resetting a session.")
        local close = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
        popup.inputs = {}
        local fields = {
            { "joinGrace", "Join grace", -65 },
            { "activeGap", "Action gap", -105 },
            { "reviveGrace", "Resurrection grace", -145 },
        }
        for _, field in ipairs(fields) do
            local label = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            label:SetPoint("TOPLEFT", 22, field[3])
            label:SetText(field[2])
            local input = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
            input:SetSize(50, 20)
            input:SetPoint("TOPRIGHT", -30, field[3] + 5)
            input:SetAutoFocus(false)
            input:SetNumeric(true)
            input:SetMaxLetters(3)
            popup.inputs[field[1]] = input
        end
        local save = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        save:SetSize(85, 22)
        save:SetPoint("BOTTOMRIGHT", -22, 20)
        save:SetText("Save")
        save:SetScript("OnClick", function()
            local values = {}
            for key, input in pairs(popup.inputs) do
                local value = tonumber(input:GetText())
                if not value or value < 1 or value > 120 or value ~= math.floor(value) then
                    RAT:Notify("Settings must be whole seconds from 1 to 120.")
                    return
                end
                values[key] = value
            end
            for key, value in pairs(values) do RAT:SetSetting(key, value) end
            popup:Hide()
            RAT:Notify("Settings saved for the next session or reset.")
        end)
        popup:Hide()
        if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "RATSettingsFrame" end
        self.settingsPopup = popup
    end
    for key, input in pairs(popup.inputs) do input:SetText(tostring(self:GetSetting(key))) end
    popup:Show()
end

function RAT:ShowText(title, value)
    local popup = self.textPopup
    if not popup then
        popup = CreateFrame("Frame", "RATTextFrame", UIParent)
        popup:SetSize(560, 400)
        popup:SetPoint("CENTER")
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetMovable(true)
        popup:EnableMouse(true)
        popup:RegisterForDrag("LeftButton")
        popup:SetScript("OnDragStart", function(self) self:StartMoving() end)
        popup:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        popup:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize=24,
            insets={left=6,right=6,top=6,bottom=6} })
        popup:SetBackdropColor(0, 0, 0, 0.96)
        popup.title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        popup.title:SetPoint("TOPLEFT", 20, -18)
        local close = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
        popup.scroll = CreateFrame("ScrollFrame", "RATTextScrollFrame", popup, "UIPanelScrollFrameTemplate")
        popup.scroll:SetPoint("TOPLEFT", 20, -50)
        popup.scroll:SetPoint("BOTTOMRIGHT", -35, 20)
        popup.edit = CreateFrame("EditBox", nil, popup.scroll)
        popup.edit:SetMultiLine(true)
        popup.edit:SetAutoFocus(false)
        popup.edit:SetFontObject(GameFontHighlightSmall)
        popup.edit:SetTextColor(1, 1, 1)
        popup.edit:SetWidth(490)
        popup.edit:SetHeight(320)
        popup.edit:SetScript("OnEscapePressed", function() popup:Hide() end)
        popup.scroll:SetScrollChild(popup.edit)
        popup:Hide()
        if UISpecialFrames then UISpecialFrames[#UISpecialFrames + 1] = "RATTextFrame" end
        self.textPopup = popup
    end
    popup.title:SetText(title)
    popup.edit:SetText(value)
    local _, lines = value:gsub("\n", "\n")
    popup.edit:SetHeight(math.max(320, (lines + 2) * 15))
    popup.scroll:SetVerticalScroll(0)
    popup:Show()
    popup.edit:SetFocus()
    popup.edit:HighlightText()
end

function RAT:ShowMemberDetails(member)
    if not member then return end
    local lines = { (member.name or member.key) .. " - inactivity intervals" }
    local eligible, idle, percent = self:GetMetrics(member)
    lines[#lines + 1] = string.format("Eligible %s | idle %s (%d%%) | packs %d",
        Duration(eligible), Duration(idle), percent, member.packs or 0)
    lines[#lines + 1] = "Intervals are estimated from this client's combat log."
    if (member.omittedSegments or 0) > 0 then
        lines[#lines + 1] = string.format("%d oldest intervals omitted to limit saved data.", member.omittedSegments)
    end
    local segments = member.idleSegments or {}
    if #segments == 0 then lines[#lines + 1] = "No qualifying intervals recorded." end
    for index, segment in ipairs(segments) do
        lines[#lines + 1] = string.format("%d. %s | pack %d | %s", index,
            date("%Y-%m-%d %H:%M:%S", math.floor(segment.startedAt or self.WallTime())),
            segment.pack or 0, Duration(segment.seconds))
    end
    self:ShowText("RAT - " .. (member.name or member.key), table.concat(lines, "\n"))
end

function RAT:ShowExport()
    local session = SelectedSession()
    if not session then self:Notify("No session to export."); return end
    local lines = { "RAT - " .. (session.instance or "Unknown") .. " (" .. Date(session.startedAt) .. ")" }
    local packs, seconds, running = self:GetSessionTotals(session)
    lines[#lines + 1] = string.format("Trash packs: %d | combat: %s%s", packs,
        Duration(seconds), running and " (includes current pack)" or "")
    lines[#lines + 1] = SettingsText(session)
    local warnings = session.warnings or {}
    if warnings.reload then lines[#lines + 1] = "Caution: session resumed after reload; combat during reload was not observed." end
    if (warnings.logGaps or 0) > 0 then
        lines[#lines + 1] = string.format("Caution: %d pack(s) ended with a combat-log gap.", warnings.logGaps)
    end
    lines[#lines + 1] = "Estimate from this client's combat-log visibility."
    lines[#lines + 1] = "Player | eligible | idle | idle % | longest | packs"
    local members = {}
    for _, member in pairs(session.members or {}) do members[#members + 1] = member end
    table.sort(members, function(a, b)
        local _, _, ap = RAT:GetMetrics(a)
        local _, _, bp = RAT:GetMetrics(b)
        if ap ~= bp then return ap > bp end
        return (a.name or a.key) < (b.name or b.key)
    end)
    for _, member in ipairs(members) do
        local eligible, idle, percent, longest = self:GetMetrics(member)
        lines[#lines + 1] = string.format("%s | %s | %s | %d%% | %s | %d",
            member.key or member.name or "?", Duration(eligible), Duration(idle), percent,
            Duration(longest), member.packs or 0)
    end
    self:ShowText("RAT - copy report", table.concat(lines, "\n"))
end

local function CSVCell(value)
    local text = tostring(value or "")
    if type(value) == "string" and text:match("^%s*[=+@%-]") then text = "'" .. text end
    return '"' .. text:gsub('"', '""') .. '"'
end

function RAT:BuildCSV(session)
    local lines = { "instance,session_started,session_state,includes_current_pack,trash_packs,combat_seconds,join_grace,action_gap,resurrection_grace,limits_status,resumed,log_gaps,player,eligible_seconds,idle_seconds,idle_percent,longest_idle_seconds,player_packs" }
    local packs, seconds, running = self:GetSessionTotals(session)
    local settings, warnings = session.settings or {}, session.warnings or {}
    for _, member in ipairs(self:GetSortedMembers(session)) do
        local eligible, idle, percent, longest = self:GetMetrics(member)
        local values = { session.instance or "Unknown", Date(session.startedAt),
            session == self.activeSession and "ACTIVE" or "FINISHED", running and "yes" or "no",
            packs, seconds, settings.joinGrace or "", settings.activeGap or "", settings.reviveGrace or "",
            not session.settings and "unknown" or (warnings.settingsUnknown and "earlier limits unknown" or "recorded"),
            warnings.reload and "yes" or "no", warnings.logGaps or 0, member.key or member.name or "?",
            eligible, idle, percent, longest, member.packs or 0 }
        for index, value in ipairs(values) do values[index] = CSVCell(value) end
        lines[#lines + 1] = table.concat(values, ",")
    end
    return table.concat(lines, "\r\n")
end

function RAT:ShowCSV()
    local session = SelectedSession()
    if not session then self:Notify("No session to export."); return end
    self:ShowText("RAT - copy CSV (combat-log estimate)", self:BuildCSV(session))
end

function RAT:ShowPackDetails()
    local session = SelectedSession()
    if not session then self:Notify("No session selected."); return end
    local lines = { "RAT - " .. (session.instance or "Unknown") .. " - pack details", SettingsText(session),
        "Snapshot estimated from this client's combat log." }
    local packs = {}
    for _, pack in ipairs(session.packDetails or {}) do packs[#packs + 1] = pack end
    local current = session == self.activeSession and self:GetCurrentPack()
    if current then packs[#packs + 1] = current end
    if (session.omittedPacks or 0) > 0 then
        lines[#lines + 1] = string.format("%d oldest pack details omitted; session totals are retained.", session.omittedPacks)
    end
    if #packs == 0 then lines[#lines + 1] = "No pack details recorded. Older sessions have summary totals only." end
    for _, pack in ipairs(packs) do
        lines[#lines + 1] = string.format("\nPack %d | %s | %s | %s", pack.number, Date(pack.startedAt),
            Duration(pack.seconds), pack == current and "IN PROGRESS" or pack.reason or "ended")
        local keys = {}
        for key in pairs(pack.members) do keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do
            local member = pack.members[key]
            local idle = math.min(member.eligible, member.idle)
            lines[#lines + 1] = string.format("%s | eligible %s | idle %s (%d%%)", key,
                Duration(member.eligible), Duration(idle), member.eligible > 0 and math.floor(idle / member.eligible * 100 + 0.5) or 0)
        end
    end
    self:ShowText("RAT - pack details", table.concat(lines, "\n"))
end

function RAT:Show()
    local frame = self:BuildFrame()
    frame.historyIndex = 1
    frame:Show()
    self:RefreshUI()
end

function RAT:Toggle()
    local frame = self:BuildFrame()
    if frame:IsShown() then frame:Hide() else self:Show() end
end

function RAT:CreateMinimapButton()
    if self.minimapButton then return end
    local button = CreateFrame("Button", "RATMinimapButton", Minimap)
    button:SetSize(32, 32)
    button:SetFrameStrata("MEDIUM")
    button:SetMovable(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    local texture = button:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    texture:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", 0, 1)
    label:SetText("RAT")
    local function Position()
        local angle = math.rad(RAT_DB.minimap.angle or 225)
        button:ClearAllPoints()
        button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
    end
    button:SetScript("OnDragStart", function() button.dragging = true end)
    button:SetScript("OnDragStop", function() button.dragging = false end)
    button:SetScript("OnUpdate", function()
        if not button.dragging then return end
        local mx, my = Minimap:GetCenter()
        local scale = Minimap:GetEffectiveScale()
        local x, y = GetCursorPosition()
        RAT_DB.minimap.angle = math.deg(math.atan2(y / scale - my, x / scale - mx))
        Position()
    end)
    button:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then
            RAT_DB.minimap.hide = true
            button:Hide()
            RAT:Notify("Minimap button hidden. Use /rat minimap to restore it.")
        else RAT:Toggle() end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("RAT - Raid Activity Tracker")
        GameTooltip:AddLine("Left-click: open report", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: hide button", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Drag: move button", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Position()
    SetShown(button, not RAT_DB.minimap.hide)
    self.minimapButton = button
end
