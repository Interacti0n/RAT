local ADDON_NAME = ...
local RAT = { VERSION = "1.0.1", NAME = "Raid Activity Tracker" }
_G.RAT = RAT

RAT.PACK_IDLE_END_AFTER = 6
RAT.PACK_DEAD_END_AFTER = 1
RAT.AUTO_EXIT_GRACE = 30
RAT.RETENTION_SECONDS = 14 * 24 * 60 * 60
RAT.DEFAULT_SETTINGS = { joinGrace = 15, activeGap = 7, reviveGrace = 30 }
RAT.MAX_IDLE_SEGMENTS = 250
RAT.MAX_PACK_DETAILS = 200

function RAT:GetSetting(key)
    local settings = RAT_DB and RAT_DB.settings
    return settings and settings[key] or self.DEFAULT_SETTINGS[key]
end

function RAT:CaptureSettings()
    local settings = {}
    for key in pairs(self.DEFAULT_SETTINGS) do settings[key] = self:GetSetting(key) end
    return settings
end

function RAT:GetSessionSetting(key)
    local settings = self.activeSession and self.activeSession.settings
    return settings and settings[key] or self:GetSetting(key)
end

function RAT:SetSort(key, toggle)
    if not ({name=true, eligible=true, idle=true, percent=true, longest=true, packs=true})[key] then return false end
    local ui = RAT_DB.ui
    if toggle and ui.sortBy == key then ui.sortAscending = not ui.sortAscending
    else ui.sortAscending = key == "name" end
    ui.sortBy, self.sortBy = key, key
    if self.RefreshUI then self:RefreshUI() end
    return true
end

function RAT:SetSetting(key, value)
    if not self.DEFAULT_SETTINGS[key] then return false end
    value = tonumber(value)
    if not value or value < 1 or value > 120 or value ~= math.floor(value) then return false end
    RAT_DB.settings[key] = value
    if self.RefreshUI then self:RefreshUI() end
    return true
end

local function WallTime()
    return time and time() or math.floor(GetTime())
end

local function SafeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d, e, f, g, h
end

local function UnitIdentity(unit)
    local name, realm = SafeCall(UnitName, unit)
    if not name then return nil end
    realm = type(realm) == "string" and realm:gsub("%s+", "") or ""
    if realm == "" then
        realm = GetRealmName and ((SafeCall(GetRealmName) or ""):gsub("%s+", "")) or ""
    end
    return realm ~= "" and (name .. "-" .. realm) or name, name
end

local function GroupUnits()
    local units = {}
    if IsInRaid and IsInRaid() then
        local count = math.min(40, tonumber(GetNumGroupMembers and GetNumGroupMembers()) or 0)
        for index = 1, count do units[#units + 1] = "raid" .. index end
    elseif IsInGroup and IsInGroup() then
        local count = math.max(1, tonumber(GetNumGroupMembers and GetNumGroupMembers()) or 1)
        for index = 1, count - 1 do units[#units + 1] = "party" .. index end
        units[#units + 1] = "player"
    else
        units[1] = "player"
    end
    return units
end

local function PetUnitFor(unit)
    if unit == "player" then return "pet" end
    local party = type(unit) == "string" and unit:match("^party(%d+)$")
    if party then return "partypet" .. party end
    local raid = type(unit) == "string" and unit:match("^raid(%d+)$")
    if raid then return "raidpet" .. raid end
end

local function RaidLocation()
    local inInstance, instanceType = SafeCall(IsInInstance)
    local name, infoType, difficulty, _, _, _, _, instanceID = SafeCall(GetInstanceInfo)
    instanceType = instanceType or infoType
    if inInstance == nil then inInstance = instanceType == "raid" end
    local isRaid = inInstance == true and instanceType == "raid"
    local key = instanceID and tostring(instanceID) or ((name or "Unknown") .. ":" .. tostring(difficulty or 0))
    return isRaid, key, name or "Unknown", tonumber(difficulty) or 0
end

local function EnsureMember(session, fullName, shortName, unit)
    local member = session.members[fullName]
    if not member then
        local _, class = SafeCall(UnitClass, unit)
        member = {
            key = fullName, name = shortName or fullName, class = class,
            trashEligibleSeconds = 0, trashIdleSeconds = 0,
            longestIdleSeconds = 0, packs = 0,
        }
        session.members[fullName] = member
    end
    member.unit = unit
    local _, class = SafeCall(UnitClass, unit)
    if class then member.class = class end
    return member
end

function RAT:InitDB()
    RAT_DB = type(RAT_DB) == "table" and RAT_DB or {}
    RAT_DB.sessions = type(RAT_DB.sessions) == "table" and RAT_DB.sessions or {}
    RAT_DB.minimap = type(RAT_DB.minimap) == "table" and RAT_DB.minimap or { angle = 225, hide = false }
    if type(RAT_DB.minimap.angle) ~= "number" then RAT_DB.minimap.angle = 225 end
    RAT_DB.minimap.hide = RAT_DB.minimap.hide == true
    RAT_DB.settings = type(RAT_DB.settings) == "table" and RAT_DB.settings or {}
    RAT_DB.ui = type(RAT_DB.ui) == "table" and RAT_DB.ui or {}
    self.sortBy = RAT_DB.ui.sortBy or "percent"
    for key, default in pairs(self.DEFAULT_SETTINGS) do
        local value = tonumber(RAT_DB.settings[key])
        RAT_DB.settings[key] = value and value >= 1 and value <= 120 and value == math.floor(value) and value or default
    end
    local cutoff = WallTime() - self.RETENTION_SECONDS
    for index = #RAT_DB.sessions, 1, -1 do
        local session = RAT_DB.sessions[index]
        if type(session) ~= "table" or (session.endedAt and session.endedAt < cutoff) then
            table.remove(RAT_DB.sessions, index)
        end
    end
    if type(RAT_DB.activeSession) == "table" and not RAT_DB.activeSession.endedAt then
        self.activeSession = RAT_DB.activeSession
        self.activeSession.members = type(self.activeSession.members) == "table" and self.activeSession.members or {}
        self.activeSession.warnings = type(self.activeSession.warnings) == "table" and self.activeSession.warnings or {}
        self.activeSession.warnings.reload = true
        if not self.activeSession.settings then
            self.activeSession.settings = self:CaptureSettings()
            self.activeSession.warnings.settingsUnknown = true
        end
        self:ResetRuntimePack()
    else
        RAT_DB.activeSession = nil
    end
end

function RAT:RefreshRoster()
    local session = self.activeSession
    if not session then return end
    if self.packStartedAt then self:Accumulate(GetTime()) end
    local seen = {}
    self.knownPetOwners = {}
    for _, unit in ipairs(GroupUnits()) do
        if UnitExists and UnitExists(unit) and (not UnitIsPlayer or UnitIsPlayer(unit)) then
            local fullName, shortName = UnitIdentity(unit)
            if fullName then
                local member = EnsureMember(session, fullName, shortName, unit)
                local wasDead = member.dead == true
                local wasEligible = self:MemberEligible(member)
                seen[fullName] = true
                member.online = not UnitIsConnected or SafeCall(UnitIsConnected, unit) ~= false
                member.dead = UnitIsDeadOrGhost and SafeCall(UnitIsDeadOrGhost, unit) == true or false
                member.lastSeenAt = WallTime()
                if self:MemberEligible(member) and not wasEligible then
                    member.eligibleSince = GetTime()
                    if self.packStartedAt then
                        self.activityAt[fullName], self.idleCredited[fullName] = GetTime(), nil
                        self.activeIdleSegment[fullName] = nil
                    end
                end
                if wasDead and not member.dead then
                    local now = GetTime()
                    self.revivedAt = self.revivedAt or {}
                    self.revivedAt[fullName] = now
                    if self.packStartedAt then
                        self.reviveGraceUntil[fullName] = now + self:GetSessionSetting("reviveGrace")
                        self.hasParticipated[fullName] = true
                        self.activityAt[fullName], self.idleCredited[fullName] = now, nil
                        self.activeIdleSegment[fullName] = nil
                    end
                end
                if self.packStartedAt and self.activityAt and not self.activityAt[fullName] then
                    self.activityAt[fullName] = GetTime()
                end
                if self.packStartedAt and self.packInitialized and not self.packMembers[fullName] then
                    self:SavePackBaseline(fullName, member)
                    member.eligibleSince = GetTime()
                    self.packMembers[fullName] = true
                    member.packs = (member.packs or 0) + 1
                end
                local petUnit = PetUnitFor(unit)
                local petGUID = petUnit and UnitExists and UnitExists(petUnit) and SafeCall(UnitGUID, petUnit)
                if petGUID then self.knownPetOwners[petGUID] = fullName end
            end
        end
    end
    for key, member in pairs(session.members) do
        if not seen[key] then member.unit, member.online = nil, false end
    end
end

function RAT:StartSession(manual)
    if self.activeSession then return false, "A session is already active." end
    local isRaid, key, name, difficulty = RaidLocation()
    if not manual and not isRaid then return false, "Enter a raid instance first." end
    if manual and not ((IsInRaid and IsInRaid()) or (IsInGroup and IsInGroup())) then
        return false, "Join a group or raid first."
    end
    local now = WallTime()
    if not isRaid then self.encounterActive = false end
    local session = {
        version = 2, startedAt = now, instanceKey = key, instance = name,
        difficulty = difficulty, automatic = not manual, members = {},
        trashPacks = 0, trashCombatSeconds = 0, warnings = {},
        settings = self:CaptureSettings(), packDetails = {},
    }
    self.activeSession, RAT_DB.activeSession = session, session
    self.revivedAt = {}
    self:ResetRuntimePack()
    self:RefreshRoster()
    if self.frame then self.frame.historyIndex = 1 end
    self:Notify("Session started: " .. session.instance .. ".")
    if self.RefreshUI then self:RefreshUI() end
    return true
end

function RAT:EndSession(reason, endedAt)
    local session = self.activeSession
    if not session then return false end
    if self.packStartedAt then self:EndTrashPack(self.lastEvidenceAt or GetTime()) end
    session.endedAt = tonumber(endedAt) or WallTime()
    session.endReason = reason or "manual"
    if reason == "manual" then RAT_DB.autoPausedFor = session.instanceKey end
    for _, member in pairs(session.members) do member.unit = nil end
    RAT_DB.sessions[#RAT_DB.sessions + 1] = session
    self.activeSession, RAT_DB.activeSession = nil, nil
    self.revivedAt = nil
    self:ResetRuntimePack()
    self:InitDB()
    local inRaid = RaidLocation()
    self:Notify(reason == "manual" and inRaid and
        "Session ended and saved. Automatic recording is paused in this raid." or
        "Session ended and saved.")
    if self.RefreshUI then self:RefreshUI(session) end
    return true
end

function RAT:ResetCurrentSession()
    local session = self.activeSession
    if not session then return false end
    if self.packStartedAt then self:EndTrashPack(self.lastEvidenceAt or GetTime()) end
    session.startedAt = WallTime()
    session.version = 2
    session.trashPacks, session.trashCombatSeconds = 0, 0
    session.warnings = {}
    session.settings, session.packDetails, session.omittedPacks = self:CaptureSettings(), {}, 0
    for _, member in pairs(session.members) do
        member.trashEligibleSeconds, member.trashIdleSeconds = 0, 0
        member.longestIdleSeconds, member.packs = 0, 0
        member.idleSegments, member.omittedSegments = {}, 0
    end
    self:ResetRuntimePack()
    self:RefreshRoster()
    if self.RefreshUI then self:RefreshUI() end
    return true
end

function RAT:ResetRuntimePack()
    local encounterWasActive = self.encounterActive == true
    self.packStartedAt, self.lastTickAt, self.lastEvidenceAt = nil, nil, nil
    self.allEnemiesDeadAt, self.trackedEnemies, self.petOwners = nil, nil, nil
    self.activityAt, self.idleCredited = {}, {}
    self.hasParticipated, self.reviveGraceUntil = {}, {}
    self.activeIdleSegment = {}
    self.packMembers, self.packInitialized = {}, false
    self.packBaseline, self.packWallStartedAt = {}, nil
    self.encounterActive = encounterWasActive or
        (IsEncounterInProgress and SafeCall(IsEncounterInProgress) == true or false)
end

function RAT:StartTrashPack(enemyGUID)
    if not self.activeSession or self.encounterActive or self.packStartedAt then return end
    local now = GetTime()
    self.packBaseline, self.packWallStartedAt = {}, WallTime()
    self.packStartedAt, self.lastTickAt, self.lastEvidenceAt = now, now, now
    self.allEnemiesDeadAt, self.trackedEnemies, self.petOwners = nil, {}, {}
    if enemyGUID then self.trackedEnemies[enemyGUID] = true end
    self.activityAt, self.idleCredited = {}, {}
    self.hasParticipated, self.reviveGraceUntil = {}, {}
    self.activeIdleSegment = {}
    self.packMembers, self.packInitialized = {}, false
    self:RefreshRoster()
    for fullName, member in pairs(self.activeSession.members) do
        if member.unit then
            self:SavePackBaseline(fullName, member)
            member.eligibleSince = now
            self.activityAt[fullName] = now
            local revived = self.revivedAt and self.revivedAt[fullName]
            if revived and now - revived < self:GetSessionSetting("reviveGrace") then
                self.reviveGraceUntil[fullName] = revived + self:GetSessionSetting("reviveGrace")
                self.hasParticipated[fullName] = true
            else
                self.hasParticipated[fullName] = false
            end
            member.packs = (member.packs or 0) + 1
            self.packMembers[fullName] = true
            local petUnit = PetUnitFor(member.unit)
            local petGUID = petUnit and UnitExists and UnitExists(petUnit) and SafeCall(UnitGUID, petUnit)
            if petGUID then self.petOwners[petGUID] = fullName end
        end
    end
    self.packInitialized = true
end

function RAT:MemberEligible(member)
    local unit = member and member.unit
    return unit and member.online ~= false and member.dead ~= true and
        UnitExists and UnitExists(unit)
end

function RAT:CreditIdle(fullName, member, now, requireEligible)
    local lastActivity = self.activityAt and self.activityAt[fullName]
    if not member or not lastActivity then return end
    if requireEligible and not self:MemberEligible(member) then return end
    local graceUntil = self.reviveGraceUntil and self.reviveGraceUntil[fullName]
    if graceUntil and now < graceUntil then return end
    local intervalStart = graceUntil and math.max(lastActivity, graceUntil) or lastActivity
    local interval = math.max(0, now - intervalStart)
    local threshold = self.hasParticipated and self.hasParticipated[fullName] and
        self:GetSessionSetting("activeGap") or self:GetSessionSetting("joinGrace")
    if interval < threshold then return end
    local credited = self.idleCredited[fullName] or 0
    member.trashIdleSeconds = (member.trashIdleSeconds or 0) + math.max(0, interval - credited)
    self.idleCredited[fullName] = math.max(credited, interval)
    member.longestIdleSeconds = math.max(member.longestIdleSeconds or 0, interval)
    local segment = self.activeIdleSegment[fullName]
    if not segment then
        member.idleSegments = type(member.idleSegments) == "table" and member.idleSegments or {}
        if #member.idleSegments >= self.MAX_IDLE_SEGMENTS then
            table.remove(member.idleSegments, 1)
            member.omittedSegments = (member.omittedSegments or 0) + 1
        end
        segment = { startedAt = WallTime() - (GetTime() - now) - interval, seconds = 0,
            pack = (self.activeSession.trashPacks or 0) + 1 }
        member.idleSegments[#member.idleSegments + 1] = segment
        self.activeIdleSegment[fullName] = segment
    end
    segment.seconds = interval
    segment.endedAt = WallTime() - (GetTime() - now)
end

function RAT:Accumulate(now)
    if not self.activeSession or not self.packStartedAt or self.encounterActive then return end
    now = math.min(tonumber(now) or GetTime(), self.lastEvidenceAt or GetTime())
    local previous = self.lastTickAt or now
    self.lastTickAt = now
    for fullName, member in pairs(self.activeSession.members) do
        if self:MemberEligible(member) then
            local delta = math.max(0, now - math.max(previous, member.eligibleSince or previous))
            member.trashEligibleSeconds = (member.trashEligibleSeconds or 0) + delta
            self:CreditIdle(fullName, member, now, false)
        else
            self.activityAt[fullName] = now
            self.idleCredited[fullName] = nil
            self.activeIdleSegment[fullName] = nil
        end
    end
end

function RAT:SavePackBaseline(key, member)
    self.packBaseline[key] = { eligible = member.trashEligibleSeconds or 0, idle = member.trashIdleSeconds or 0 }
end

function RAT:GetCurrentPack(endedAt)
    if not self.packStartedAt then return nil end
    local pack = { number = (self.activeSession.trashPacks or 0) + 1,
        startedAt = self.packWallStartedAt, members = {},
        seconds = math.max(0, (endedAt or self.lastEvidenceAt or self.packStartedAt) - self.packStartedAt) }
    for key, baseline in pairs(self.packBaseline) do
        local member = self.activeSession.members[key]
        if member then
            pack.members[key] = { eligible = math.max(0, (member.trashEligibleSeconds or 0) - baseline.eligible),
                idle = math.max(0, (member.trashIdleSeconds or 0) - baseline.idle) }
        end
    end
    return pack
end

function RAT:GetSessionTotals(session)
    local packs, seconds = session.trashPacks or 0, session.trashCombatSeconds or 0
    local running = session == self.activeSession and self.packStartedAt ~= nil
    if running then
        packs = packs + 1
        seconds = seconds + math.max(0, (self.lastEvidenceAt or self.packStartedAt) - self.packStartedAt)
    end
    return packs, seconds, running
end

function RAT:EndTrashPack(endedAt, reason)
    if not self.activeSession or not self.packStartedAt then return end
    if reason == "gap" and UnitAffectingCombat then
        for _, member in pairs(self.activeSession.members) do
            if member.unit and SafeCall(UnitAffectingCombat, member.unit) then
                self.activeSession.warnings = self.activeSession.warnings or {}
                self.activeSession.warnings.logGaps = (self.activeSession.warnings.logGaps or 0) + 1
                break
            end
        end
    end
    endedAt = math.max(self.packStartedAt, tonumber(endedAt) or self.lastEvidenceAt or GetTime())
    self:Accumulate(endedAt)
    local details = self.activeSession.packDetails or {}
    self.activeSession.packDetails = details
    if #details >= self.MAX_PACK_DETAILS then
        table.remove(details, 1)
        self.activeSession.omittedPacks = (self.activeSession.omittedPacks or 0) + 1
    end
    local pack = self:GetCurrentPack(endedAt)
    pack.reason = reason or "ended"
    details[#details + 1] = pack
    self.activeSession.trashPacks = (self.activeSession.trashPacks or 0) + 1
    self.activeSession.trashCombatSeconds = (self.activeSession.trashCombatSeconds or 0) + (endedAt - self.packStartedAt)
    self.packStartedAt, self.lastTickAt, self.lastEvidenceAt = nil, nil, nil
    self.allEnemiesDeadAt, self.trackedEnemies, self.petOwners = nil, nil, nil
    self.activityAt, self.idleCredited = {}, {}
    self.hasParticipated, self.reviveGraceUntil = {}, {}
    self.activeIdleSegment = {}
    self.packMembers, self.packInitialized = {}, false
end

local ACTIVE_EVENTS = {
    SWING_DAMAGE=true, RANGE_DAMAGE=true, SPELL_DAMAGE=true, SPELL_PERIODIC_DAMAGE=true,
    SWING_MISSED=true, RANGE_MISSED=true, SPELL_MISSED=true,
    SPELL_HEAL=true, SPELL_PERIODIC_HEAL=true,
    SPELL_CAST_START=true, SPELL_CAST_SUCCESS=true,
    SPELL_INTERRUPT=true, SPELL_DISPEL=true, SPELL_STOLEN=true,
}
local EVIDENCE_EVENTS = {
    SWING_DAMAGE=true, RANGE_DAMAGE=true, SPELL_DAMAGE=true, SPELL_PERIODIC_DAMAGE=true,
    DAMAGE_SHIELD=true, SWING_MISSED=true, RANGE_MISSED=true, SPELL_MISSED=true,
    SPELL_INTERRUPT=true, SPELL_DISPEL=true, SPELL_STOLEN=true,
}

local function ResolveMember(session, guid, name)
    for key, member in pairs(session.members or {}) do
        local unitGUID = member.unit and SafeCall(UnitGUID, member.unit)
        if guid and unitGUID == guid then return key, member, false end
    end
    local owner = guid and ((RAT.petOwners and RAT.petOwners[guid]) or
        (RAT.knownPetOwners and RAT.knownPetOwners[guid]))
    if owner and session.members[owner] then return owner, session.members[owner], true end
    for key, member in pairs(session.members or {}) do
        if not guid and name and (member.name == name or key == name or key:match("^[^%-]+") == name) then
            return key, member, false
        end
    end
end

local function HasEnemy(enemies)
    for _ in pairs(enemies or {}) do return true end
    return false
end

function RAT:IsBossCombat(enemyGUID)
    if self.encounterActive or (IsEncounterInProgress and SafeCall(IsEncounterInProgress) == true) then
        return true
    end
    if enemyGUID and UnitExists and UnitGUID then
        for index = 1, 5 do
            local unit = "boss" .. index
            if UnitExists(unit) and SafeCall(UnitGUID, unit) == enemyGUID then
                self.bossSuppressedUntil = GetTime() + 10
                return true
            end
        end
    end
    return self.bossSuppressedUntil and GetTime() < self.bossSuppressedUntil
end

function RAT:CombatLog(...)
    local session = self.activeSession
    if not session then return end
    local _, subevent, _, sourceGUID, sourceName, _, _, destGUID, destName = ...
    local sourceKey, sourceMember, sourceIsPet = ResolveMember(session, sourceGUID, sourceName)
    local destKey, destMember, destIsPet = ResolveMember(session, destGUID, destName)

    if not self.encounterActive and EVIDENCE_EVENTS[subevent] then
        local enemyGUID
        if sourceMember and not destMember then enemyGUID = destGUID
        elseif destMember and not sourceMember then enemyGUID = sourceGUID end
        if enemyGUID then
            if self:IsBossCombat(enemyGUID) then
                if self.packStartedAt then self:EndTrashPack(self.lastEvidenceAt or GetTime()) end
                return
            end
            if not self.packStartedAt then self:StartTrashPack(enemyGUID) end
            if self.packStartedAt then
                self.trackedEnemies[enemyGUID] = true
                self.lastEvidenceAt, self.allEnemiesDeadAt = GetTime(), nil
            end
        end
    end

    if subevent == "UNIT_DIED" and self.packStartedAt and
        (destMember or (destGUID and self.trackedEnemies[destGUID])) then
        self.lastEvidenceAt = GetTime()
    end
    if self.packStartedAt and not self.encounterActive then self:Accumulate(GetTime()) end

    if ACTIVE_EVENTS[subevent] and sourceMember and not sourceIsPet and self.packStartedAt and not self.encounterActive then
        local now = math.min(GetTime(), self.lastEvidenceAt or GetTime())
        self:CreditIdle(sourceKey, sourceMember, now, true)
        self.activityAt[sourceKey] = GetTime()
        self.idleCredited[sourceKey] = nil
        self.activeIdleSegment[sourceKey] = nil
        self.hasParticipated[sourceKey] = true
    end

    if subevent == "UNIT_DIED" and self.packStartedAt then
        if destMember and not destIsPet then
            local deadKey = destKey
            if deadKey then
                self:CreditIdle(deadKey, destMember, math.min(GetTime(), self.lastEvidenceAt or GetTime()), false)
                self.activityAt[deadKey], self.idleCredited[deadKey] = GetTime(), nil
                self.activeIdleSegment[deadKey] = nil
                destMember.dead = true
            end
        end
        if destGUID and self.trackedEnemies[destGUID] then
            self.trackedEnemies[destGUID] = nil
            if not HasEnemy(self.trackedEnemies) then self.allEnemiesDeadAt = GetTime() end
        end
    end
end

function RAT:Tick()
    if IsEncounterInProgress and SafeCall(IsEncounterInProgress) == true and not self.encounterActive then
        self:EncounterStart()
    end
    if self.activeSession then
        if self.packStartedAt and not self.encounterActive then
            local now = GetTime()
            self:Accumulate(now)
        end
        self:RefreshRoster()
        if self.packStartedAt and not self.encounterActive then
            local now = GetTime()
            if self.allEnemiesDeadAt and now - self.allEnemiesDeadAt >= self.PACK_DEAD_END_AFTER then
                self:EndTrashPack(self.allEnemiesDeadAt)
            elseif self.lastEvidenceAt and now - self.lastEvidenceAt >= self.PACK_IDLE_END_AFTER then
                self:EndTrashPack(self.lastEvidenceAt, "gap")
            end
        end
    end
    self:UpdateAutomaticSession()
    if self.RefreshUI and self.frame and self.frame:IsShown() then self:RefreshUI() end
end

function RAT:UpdateAutomaticSession()
    local isRaid, key = RaidLocation()
    local grouped = (IsInRaid and IsInRaid()) or (IsInGroup and IsInGroup())
    local now = GetTime()
    if isRaid and grouped then
        self.outsideSince = nil
        self.pausedOutsideSince = nil
        if RAT_DB.autoPausedFor and RAT_DB.autoPausedFor ~= key then RAT_DB.autoPausedFor = nil end
        if self.activeSession and self.activeSession.instanceKey ~= key then self:EndSession("instance-change") end
        if not self.activeSession and RAT_DB.autoPausedFor ~= key then self:StartSession(false) end
    elseif self.activeSession and self.activeSession.automatic then
        self.outsideSince = self.outsideSince or now
        if now - self.outsideSince >= self.AUTO_EXIT_GRACE then self:EndSession("automatic") end
    else
        self.outsideSince = nil
    end
    if not isRaid or not grouped then
        if RAT_DB.autoPausedFor then
            self.pausedOutsideSince = self.pausedOutsideSince or now
            if now - self.pausedOutsideSince >= self.AUTO_EXIT_GRACE then
                RAT_DB.autoPausedFor, self.pausedOutsideSince = nil, nil
            end
        end
        self.encounterActive, self.bossSuppressedUntil = false, nil
    end
end

function RAT:EncounterStart()
    if self.packStartedAt then self:EndTrashPack(self.lastEvidenceAt or GetTime()) end
    self.encounterActive = true
end

function RAT:EncounterEnd()
    self.encounterActive = false
    self.bossSuppressedUntil = nil
end

function RAT:GetSessions()
    local result = {}
    if self.activeSession then result[#result + 1] = self.activeSession end
    for index = #(RAT_DB.sessions or {}), 1, -1 do result[#result + 1] = RAT_DB.sessions[index] end
    return result
end

function RAT:GetMetrics(member)
    local eligible = math.max(0, member and member.trashEligibleSeconds or 0)
    local idle = math.min(eligible, math.max(0, member and member.trashIdleSeconds or 0))
    local percent = eligible > 0 and math.min(100, math.floor(idle / eligible * 100 + 0.5)) or 0
    return eligible, idle, percent, math.max(0, member and member.longestIdleSeconds or 0)
end

function RAT:Notify(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffcc3333RAT:|r " .. tostring(message))
    elseif print then print("RAT: " .. tostring(message)) end
end

RAT.ADDON_NAME = ADDON_NAME
RAT.WallTime = WallTime
RAT.RaidLocation = RaidLocation
