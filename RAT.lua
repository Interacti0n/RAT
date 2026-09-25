local ADDON_NAME = ...
local RAT = assert(_G.RAT, "RAT_Core.lua must load first")

local frame = CreateFrame("Frame", "RATEventFrame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("ENCOUNTER_START")
frame:RegisterEvent("ENCOUNTER_END")
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("PLAYER_UNGHOST")
frame:RegisterEvent("UNIT_CONNECTION")
frame:RegisterEvent("PLAYER_LOGOUT")

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local addon = ...
        if addon == ADDON_NAME then
            RAT:InitDB()
            RAT:BuildFrame()
            RAT:CreateMinimapButton()
        elseif addon == "ElvUI" then RAT:TrySkinElvUI() end
    elseif event == "PLAYER_LOGOUT" then
        if RAT.packStartedAt then RAT:EndTrashPack(RAT.lastEvidenceAt, "logout/reload") end
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        RAT:UpdateAutomaticSession()
        RAT:TrySkinElvUI()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" or event == "UNIT_CONNECTION" then
        RAT:RefreshRoster()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        RAT:CombatLog(...)
    elseif event == "ENCOUNTER_START" then
        RAT:EncounterStart()
    elseif event == "ENCOUNTER_END" then
        RAT:EncounterEnd()
    end
end)

local elapsed = 0
frame:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < 1 then return end
    elapsed = 0
    RAT:Tick()
end)

SLASH_RAT1 = "/rat"
SlashCmdList.RAT = function(raw)
    local command = tostring(raw or ""):lower():match("^%s*(.-)%s*$")
    local key, value = command:match("^(join)%s+(%d+)$")
    if not key then key, value = command:match("^(gap)%s+(%d+)$") end
    if not key then key, value = command:match("^(revive)%s+(%d+)$") end
    if key then
        local setting = ({ join = "joinGrace", gap = "activeGap", revive = "reviveGrace" })[key]
        if RAT:SetSetting(setting, value) then
            RAT:Notify(key .. " grace/limit set to " .. value .. "s for the next session or reset.")
        else
            RAT:Notify("Choose a whole number from 1 to 120 seconds.")
        end
        return
    end
    if command == "start" then
        local ok, reason = RAT:StartSession(true)
        if not ok then RAT:Notify(reason) end
    elseif command == "stop" or command == "end" then
        if not RAT:EndSession("manual") then RAT:Notify("No session is active.") end
    elseif command == "reset" then
        if not RAT:ResetCurrentSession() then RAT:Notify("No session is active.") end
    elseif command == "minimap" then
        RAT_DB.minimap.hide = not RAT_DB.minimap.hide
        if RAT_DB.minimap.hide then RAT.minimapButton:Hide() else RAT.minimapButton:Show() end
    elseif command == "settings" then
        RAT:ShowSettings()
        RAT:Notify(string.format("Join %ds | action gap %ds | resurrection %ds. Change with /rat join N, /rat gap N, /rat revive N (1-120).",
            RAT:GetSetting("joinGrace"), RAT:GetSetting("activeGap"), RAT:GetSetting("reviveGrace")))
    elseif command == "export" then
        RAT:ShowExport()
    elseif command == "csv" then
        RAT:ShowCSV()
    elseif command == "packs" then
        RAT:ShowPackDetails()
    elseif command:match("^sort%s+") then
        local sort = command:match("^sort%s+(%a+)$")
        if RAT:SetSort(sort) then
            RAT:Notify("Sort: " .. sort .. ".")
        else RAT:Notify("Use /rat sort percent, idle, name, eligible, longest or packs.") end
    elseif command == "help" then
        RAT:Notify("/rat | start | stop | reset | minimap | settings | join N | gap N | revive N | sort percent/idle/name/eligible/longest/packs | export | csv | packs")
    else RAT:Toggle() end
end
