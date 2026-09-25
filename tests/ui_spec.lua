-- Exercise frame construction and user callbacks against a small WoW UI stub.
local objects = {}
local methods = {}
local function object(kind, name, parent)
    local value = setmetatable({kind=kind, name=name, parent=parent, scripts={}, shown=false}, {__index=methods})
    objects[#objects + 1] = value
    if name then _G[name] = value end
    return value
end
for _, name in ipairs({"SetFrameStrata", "SetMovable", "SetClampedToScreen", "EnableMouse", "RegisterForDrag",
    "SetBackdrop", "SetBackdropColor", "SetJustifyH", "SetAllPoints", "SetTexture", "SetTextColor",
    "SetVertexColor", "StartMoving", "StopMovingOrSizing", "SetAutoFocus", "SetNumeric", "SetMaxLetters",
    "SetMultiLine", "SetFontObject", "SetFocus", "HighlightText", "RegisterForClicks", "SetVerticalScroll",
    "RegisterEvent"}) do methods[name] = function() end end
function methods:SetPoint(...) self.point = {...} end
function methods:GetPoint() return unpack(self.point) end
function methods:SetSize(w, h) self.width, self.height = w, h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:SetText(text) self.text = tostring(text) end
function methods:GetText() return self.text end
function methods:SetEnabled(value) self.enabled = value end
function methods:SetScript(name, fn) self.scripts[name] = fn end
function methods:Hide() self.shown = false end
function methods:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
function methods:IsShown() return self.shown end
function methods:GetName() return self.name end
function methods:CreateFontString() return object("FontString", nil, self) end
function methods:CreateTexture() return object("Texture", nil, self) end
function methods:SetScrollChild(child) self.child = child end
CreateFrame = object
UIParent = object("Frame", "UIParent")
UISpecialFrames, StaticPopupDialogs, SlashCmdList = {}, {}, {}
GetTime = function() return 1000 end
time = function() return 1700001000 end
date = os.date
IsInInstance = function() return false, "none" end
GetInstanceInfo = function() return "Unknown", "none" end
IsInGroup = function() return true end
GetNumGroupMembers = function() return 1 end
UnitExists = function(unit) return unit == "player" end
UnitName = function() return "Tester", "Realm" end
UnitClass = function() return "Hunter", "HUNTER" end
UnitGUID = function() return "Player-1" end
UnitIsConnected = function() return true end
UnitIsDeadOrGhost = function() return false end
assert(loadfile("RAT_Core.lua"))("RAT")
local RAT = _G.RAT
RAT.Notify = function() end
RAT:InitDB()
assert(loadfile("RAT_UI.lua"))()
assert(loadfile("RAT.lua"))("RAT")
local frame = RAT:BuildFrame()
RAT:Show()
assert(not frame.csv.enabled and not frame.packDetails.enabled)
frame.toggle.scripts.OnClick()
assert(RAT.activeSession and frame.csv.enabled and frame.packDetails.enabled)

-- Dragging saves an anchor, and a rebuilt frame restores it.
frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 123, -45)
frame.scripts.OnDragStop(frame)
assert(RAT_DB.ui.position.x == 123 and RAT_DB.ui.position.y == -45)
RAT.frame = nil
frame = RAT:BuildFrame()
local point, parent, relative, x, y = frame:GetPoint()
assert(point == "TOPLEFT" and parent == UIParent and relative == "TOPLEFT" and x == 123 and y == -45)

-- Click the actual Player header button twice; direction must reverse and persist.
local playerHeader
for _, value in ipairs(objects) do
    if value.parent == frame and value.kind == "Button" and value.point and value.point[2] == 18
        and value.point[3] == -86 then playerHeader = value end
end
assert(playerHeader)
playerHeader.scripts.OnClick()
assert(RAT_DB.ui.sortBy == "name" and RAT_DB.ui.sortAscending)
playerHeader.scripts.OnClick()
assert(not RAT_DB.ui.sortAscending)

-- Settings save updates defaults, but the current session retains its limits.
frame.settings.scripts.OnClick()
local popup = RAT.settingsPopup
popup.inputs.joinGrace:SetText("20")
local save
for _, value in ipairs(objects) do if value.parent == popup and value.text == "Save" then save = value end end
assert(save)
save.scripts.OnClick()
assert(RAT_DB.settings.joinGrace == 20 and RAT.activeSession.settings.joinGrace == 15)
assert(frame.note.text:find("Join 15s", 1, true))

-- Export buttons and slash commands open the expected report.
frame.csv.scripts.OnClick()
assert(RAT.textPopup.edit.text:find("eligible_seconds", 1, true))
frame.packDetails.scripts.OnClick()
assert(RAT.textPopup.edit.text:find("No pack details", 1, true))
frame.export.scripts.OnClick()
assert(RAT.textPopup.edit.text:find("Join 15s", 1, true))
SlashCmdList.RAT("sort packs")
assert(RAT_DB.ui.sortBy == "packs")
SlashCmdList.RAT("csv")
assert(RAT.textPopup.edit.text:find("eligible_seconds", 1, true))
SlashCmdList.RAT("packs")
assert(RAT.textPopup.edit.text:find("No pack details", 1, true))

-- Reload closes the measured part of a pack before saved variables are written.
RAT:StartTrashPack("Enemy-1")
GetTime = function() return 1004 end
RAT.lastEvidenceAt = 1004
RAT:Accumulate(1004)
RATEventFrame.scripts.OnEvent(RATEventFrame, "PLAYER_LOGOUT")
assert(not RAT.packStartedAt)
assert(RAT.activeSession.trashPacks == 1 and RAT.activeSession.trashCombatSeconds == 4)
frame.toggle.scripts.OnClick()
assert(not RAT.activeSession)
assert(frame.note.text:find("Join 15s", 1, true))
print("RAT UI callback tests passed")
