-- Lua 5.1 regression scenarios; no WoW client required.
local clock, units, RAT
local playerKey = "Tester-Realm"
GetTime = function() return clock end
time = function() return 1700000000 + clock end
date = os.date
IsInInstance = function() return true, "raid" end
GetInstanceInfo = function() return 'Test, "Raid"', "raid", 3, nil, nil, nil, nil, 123 end
IsInRaid = function() return true end
IsInGroup = function() return true end
GetNumGroupMembers = function() return units.raid2 and 2 or 1 end
UnitExists = function(unit) return units[unit] ~= nil end
UnitIsPlayer = function(unit) return unit ~= "raidpet1" end
UnitName = function(unit) return units[unit].name, "Realm" end
GetRealmName = function() return "Realm" end
UnitClass = function() return "Hunter", "HUNTER" end
UnitGUID = function(unit) return units[unit] and units[unit].guid end
UnitIsConnected = function(unit) return units[unit].online end
UnitIsDeadOrGhost = function(unit) return units[unit].dead end
UnitAffectingCombat = function() return true end
IsEncounterInProgress = function() return false end

local function fresh()
    clock = 1000
    units = {
        raid1 = {name="Tester", guid="Player-1", online=true, dead=false},
        raidpet1 = {name="Pet", guid="Pet-1", online=true, dead=false},
    }
    RAT_DB = nil
    assert(loadfile("RAT_Core.lua"))("RAT")
    RAT = _G.RAT
    RAT.Notify = function() end
    RAT:InitDB()
    assert(RAT:StartSession(false))
    return RAT.activeSession.members[playerKey]
end

local function event(at, kind, source, dest)
    clock = 1000 + at
    RAT:CombatLog(0, kind, false, source, source, 0, 0, dest, dest)
end

local function hit(at)
    event(at, "SWING_DAMAGE", "Enemy-1", "Player-1")
end

local function near(actual, expected, message)
    assert(math.abs(actual - expected) < 0.001,
        (message or "unexpected value") .. ": expected " .. expected .. ", got " .. tostring(actual))
end

-- Pet attacks do not mark the owner active; pet death must not kill/resurrect the owner.
local member = fresh()
hit(0)
event(4, "SWING_DAMAGE", "Pet-1", "Enemy-1")
assert(not RAT.hasParticipated[playerKey])
event(5, "UNIT_DIED", nil, "Pet-1")
assert(not member.dead, "pet death marked owner dead")
units.raidpet1 = nil
RAT:RefreshRoster()
assert(not RAT.reviveGraceUntil[playerKey], "pet death granted resurrection grace")
hit(10); hit(16)
near(member.trashIdleSeconds, 16, "pet death must not erase owner's idle interval")

-- Personal actions use the action gap, including the complete qualifying interval.
member = fresh()
hit(0)
event(2, "SPELL_CAST_SUCCESS", "Player-1", "Enemy-1")
hit(8)
near(member.trashIdleSeconds, 0)
hit(9)
near(member.trashIdleSeconds, 7)
event(10, "SPELL_DAMAGE", "Player-1", "Enemy-1")
near(member.trashIdleSeconds, 8)
hit(16)
near(member.trashIdleSeconds, 8)
hit(17)
near(member.trashIdleSeconds, 15)

-- Death excludes eligibility; resurrection between evidence events starts at the observed revival.
member = fresh()
hit(0); hit(4)
units.raid1.dead = true
event(5, "UNIT_DIED", nil, "Player-1")
hit(9)
near(member.trashEligibleSeconds, 5)
clock = 1011
units.raid1.dead = false
RAT:RefreshRoster()
near(RAT.reviveGraceUntil[playerKey], 1041)
hit(13)
near(member.trashEligibleSeconds, 7, "dead time was counted at resurrection")
for at = 17, 45, 4 do hit(at) end
near(member.trashIdleSeconds, 0)
hit(48)
near(member.trashIdleSeconds, 7, "resurrection grace and action gap")

-- Offline gaps cannot be credited to a player returning between evidence events.
member = fresh()
hit(0); hit(4)
units.raid1.online = false
RAT:RefreshRoster()
hit(8); hit(12)
near(member.trashEligibleSeconds, 4)
clock = 1014
units.raid1.online = true
RAT:RefreshRoster()
hit(16)
near(member.trashEligibleSeconds, 6, "offline time was counted on reconnect")
near(member.trashIdleSeconds, 0)

-- Session limits remain immutable, including after reload; reset uses the new defaults.
member = fresh()
hit(0)
assert(RAT:SetSetting("joinGrace", 1))
hit(4)
near(member.trashIdleSeconds, 0)
near(RAT.activeSession.settings.joinGrace, 15)
local saved = RAT_DB
assert(loadfile("RAT_Core.lua"))("RAT")
RAT = _G.RAT
RAT.Notify = function() end
RAT:InitDB()
assert(RAT_DB == saved)
near(RAT:GetSessionSetting("joinGrace"), 15)
assert(RAT.activeSession.warnings.reload)
RAT:ResetCurrentSession()
near(RAT:GetSessionSetting("joinGrace"), 1)
RAT:EndSession("manual")
local history = RAT_DB.sessions[1]
RAT:SetSetting("joinGrace", 20)
near(history.settings.joinGrace, 1)

-- Old records are preserved, and missing historical limits are not invented.
fresh()
RAT_DB.sessions = {{startedAt=time()-50, endedAt=time()-10, members={}}}
RAT.activeSession.settings = nil
RAT:InitDB()
assert(not RAT_DB.sessions[1].settings)
assert(RAT.activeSession.warnings.settingsUnknown)
near(RAT.activeSession.settings.joinGrace, 15)

-- Live totals and pack details agree with finalized totals, including late arrivals.
member = fresh()
hit(0); hit(4)
clock = 1006
units.raid2 = {name="Late", guid="Player-2", online=true, dead=false}
RAT:RefreshRoster()
hit(8); hit(16)
local packs, seconds, running = RAT:GetSessionTotals(RAT.activeSession)
near(packs, 1); near(seconds, 16); assert(running)
local pack = RAT:GetCurrentPack()
near(pack.members[playerKey].eligible, 16)
near(pack.members["Late-Realm"].eligible, 10)
near(pack.members["Late-Realm"].idle, 0)
RAT:EndTrashPack(clock)
packs, seconds, running = RAT:GetSessionTotals(RAT.activeSession)
near(packs, 1); near(seconds, 16); assert(not running)
near(RAT.activeSession.packDetails[1].members[playerKey].idle, 16)
hit(20); hit(24)
near(RAT:GetCurrentPack().members[playerKey].eligible, 4, "pack totals must not include earlier packs")
RAT:EndTrashPack(clock)
RAT.MAX_PACK_DETAILS = 2
hit(30); hit(34); RAT:EndTrashPack(clock)
near(#RAT.activeSession.packDetails, 2)
near(RAT.activeSession.omittedPacks, 1)
near(RAT.activeSession.trashPacks, 3)
near(RAT.activeSession.trashCombatSeconds, 24)
RAT:ResetCurrentSession()
near(#RAT.activeSession.packDetails, 0)
near(RAT.activeSession.omittedPacks, 0)

-- Export and sorting are tested through UI functions without creating WoW frames.
member = fresh()
assert(loadfile("RAT_UI.lua"))()
hit(0); hit(16)
local output
RAT.ShowText = function(_, title, value) output = value end
RAT:ShowExport()
assert(output:find("Trash packs: 1 | combat: 0m 16s (includes current pack)", 1, true))
assert(output:find("Join 15s", 1, true))
local csv = RAT:BuildCSV(RAT.activeSession)
assert(csv:find('"Test, ""Raid"""', 1, true), "CSV quoting")
assert(csv:find('"ACTIVE","yes","1","16","15","7","30","recorded"', 1, true))
assert(csv:find('"Tester-Realm","16","16","100","16","1"', 1, true))
RAT:ShowPackDetails()
assert(output:find("IN PROGRESS", 1, true))
assert(output:find("Tester-Realm | eligible 0m 16s | idle 0m 16s (100%)", 1, true))
RAT:EndTrashPack(clock)
RAT:ShowPackDetails()
assert(not output:find("IN PROGRESS", 1, true))
RAT.activeSession.members["Alpha-Realm"] = {key="Alpha-Realm", name="Alpha", trashEligibleSeconds=20,
    trashIdleSeconds=4, longestIdleSeconds=4, packs=2}
RAT:SetSort("name")
assert(RAT:GetSortedMembers(RAT.activeSession)[1].key == "Alpha-Realm")
RAT:SetSort("name", true)
assert(RAT:GetSortedMembers(RAT.activeSession)[1].key == playerKey)
RAT:SetSort("eligible")
assert(RAT:GetSortedMembers(RAT.activeSession)[1].key == "Alpha-Realm")
RAT:InitDB()
assert(RAT.sortBy == "eligible" and not RAT_DB.ui.sortAscending)
RAT:SetSort("percent")
assert(RAT:GetSortedMembers(RAT.activeSession)[1].key == playerKey)
assert(not RAT:SetSort("unsupported"))
RAT.activeSession.members["=1+1"] = {key="=1+1"}
assert(RAT:BuildCSV(RAT.activeSession):find('"\'=1+1"', 1, true), "CSV formula protection")
print("RAT regression tests passed")
