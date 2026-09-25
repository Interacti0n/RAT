-- Run from the addon root with Lua 5.1: lua tests/core_spec.lua
local clock = 1000
local inRaid = true
local bossVisible = false

GetTime = function() return clock end
time = function() return 1700000000 + math.floor(clock) end
IsInInstance = function() return inRaid, inRaid and "raid" or "none" end
GetInstanceInfo = function() return "Test Raid", inRaid and "raid" or "none", 3, nil, nil, nil, nil, 123 end
IsInRaid = function() return true end
IsInGroup = function() return true end
GetNumGroupMembers = function() return 1 end
UnitExists = function(unit) return unit == "raid1" or (unit == "boss1" and bossVisible) end
UnitIsPlayer = function(unit) return unit == "raid1" end
UnitName = function(unit) if unit == "raid1" then return "Tester", "Realm" end end
GetRealmName = function() return "Realm" end
UnitClass = function() return "Mage", "MAGE" end
UnitGUID = function(unit)
    if unit == "raid1" then return "Player-1" end
    if unit == "boss1" and bossVisible then return "Creature-Boss" end
end
UnitIsConnected = function() return true end
UnitIsDeadOrGhost = function() return false end
UnitAffectingCombat = function() return true end
IsEncounterInProgress = function() return false end

assert(loadfile("RAT_Core.lua"))("RAT")
local RAT = assert(_G.RAT)
RAT:InitDB()
assert(RAT:StartSession(false))

local function enemyHit(guid)
    RAT:CombatLog(0, "SWING_DAMAGE", false, guid, "Enemy", 0, 0, "Player-1", "Tester")
end

enemyHit("Creature-1")
for _, seconds in ipairs({ 4, 8, 12, 16 }) do
    clock = 1000 + seconds
    enemyHit("Creature-1")
end
RAT:EndTrashPack(clock)
local member = assert(RAT.activeSession.members["Tester-Realm"])
assert(math.abs(member.trashEligibleSeconds - 16) < 0.01)
assert(math.abs(member.trashIdleSeconds - 16) < 0.01)
assert(#member.idleSegments == 1 and member.idleSegments[1].pack == 1)

assert(RAT:EndSession("manual"))
RAT:UpdateAutomaticSession()
assert(not RAT.activeSession, "manual stop must pause automatic restart")
inRaid = false
clock = 1040
RAT:UpdateAutomaticSession()
clock = 1071
RAT:UpdateAutomaticSession()
inRaid = true
RAT:UpdateAutomaticSession()
assert(RAT.activeSession, "automatic recording must resume after leaving raid")

RAT:EncounterStart()
enemyHit("Creature-Boss")
assert(not RAT.packStartedAt, "encounter must not create a trash pack")
RAT:EncounterEnd()
bossVisible = true
enemyHit("Creature-Boss")
assert(not RAT.packStartedAt, "visible boss unit must not create a trash pack")
bossVisible = false
clock = clock + 11
assert(RAT:SetSetting("joinGrace", 10))
assert(not RAT:SetSetting("joinGrace", 0))
assert(RAT:GetSessionSetting("joinGrace") == 15, "running session keeps its original limits")
RAT:ResetCurrentSession()
enemyHit("Creature-2")
local secondPackStart = clock
for _, seconds in ipairs({ 4, 8, 12 }) do
    clock = secondPackStart + seconds
    enemyHit("Creature-2")
end
RAT:EndTrashPack(clock)
member = assert(RAT.activeSession.members["Tester-Realm"])
assert(math.abs(member.trashIdleSeconds - 12) < 0.01)
assert(member.packs == 1)
print("RAT core tests passed")
