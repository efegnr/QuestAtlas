-- QuestAtlas - Services/WowApiAdapter.lua
-- Adapter pattern: the ONLY class that calls the global WoW API. Everything
-- else talks to this adapter through plain Lua tables.
--   * Hides the differences between the classic quest log API
--     (GetQuestLogTitle, GetQuestLogLeaderBoard) and the newer C_QuestLog API,
--     so the add-on works whichever one the WoW: Forever client exposes.
--   * Retail WoW (and possibly Forever) shows quest markers on the map; the
--     adapter reads them (getQuestPoiLocations), so quests that are missing
--     from the add-on's database can still be routed.
--   * Makes the rest of the code testable: tests pass a fake environment.
local _, ns = ...

local WowApiAdapter = ns.Class("WowApiAdapter")

--- env: table that holds the WoW globals (defaults to _G).
function WowApiAdapter:init(env)
    self.env = env or _G
end

function WowApiAdapter:getQuestApiFlavor()
    local questLog = self.env.C_QuestLog
    if questLog and questLog.GetInfo and questLog.GetNumQuestLogEntries and questLog.GetQuestObjectives then
        return "modern"
    end
    return "classic"
end

----------------------------------------------------------------------------
-- Quest log
----------------------------------------------------------------------------

--- Returns a list of plain entries:
--- { questID, title, level, isComplete, isFailed, objectives = { {index, text, type, finished} } }
function WowApiAdapter:getQuestLogEntries()
    if self:getQuestApiFlavor() == "modern" then
        return self:readModernQuestLog()
    end
    return self:readClassicQuestLog()
end

function WowApiAdapter:readClassicQuestLog()
    local env = self.env
    local entries = {}
    local numEntries = env.GetNumQuestLogEntries() or 0
    for logIndex = 1, numEntries do
        local title, level, _, isHeader, _, isComplete, _, questID = env.GetQuestLogTitle(logIndex)
        if title and not isHeader and questID then
            local objectives = {}
            local count = env.GetNumQuestLeaderBoards(logIndex) or 0
            for objectiveIndex = 1, count do
                local text, objectiveType, finished = env.GetQuestLogLeaderBoard(objectiveIndex, logIndex)
                objectives[#objectives + 1] = {
                    index = objectiveIndex, text = text, type = objectiveType, finished = finished and true or false,
                }
            end
            entries[#entries + 1] = {
                questID = questID,
                title = title,
                level = level,
                isComplete = isComplete == 1 or isComplete == true,
                isFailed = isComplete == -1,
                objectives = objectives,
            }
        end
    end
    return entries
end

function WowApiAdapter:readModernQuestLog()
    local questLog = self.env.C_QuestLog
    local entries = {}
    local numEntries = questLog.GetNumQuestLogEntries() or 0
    for logIndex = 1, numEntries do
        local info = questLog.GetInfo(logIndex)
        -- isTask = bonus objectives / world quests: area tasks, not NPC quests
        if info and not info.isHeader and not info.isHidden and not info.isTask and info.questID then
            local objectives = {}
            local list = questLog.GetQuestObjectives(info.questID) or {}
            for objectiveIndex = 1, #list do
                local objective = list[objectiveIndex]
                objectives[#objectives + 1] = {
                    index = objectiveIndex, text = objective.text, type = objective.type,
                    finished = objective.finished and true or false,
                }
            end
            entries[#entries + 1] = {
                questID = info.questID,
                title = info.title,
                level = info.level,
                isComplete = questLog.IsComplete and questLog.IsComplete(info.questID) and true or false,
                isFailed = questLog.IsFailed and questLog.IsFailed(info.questID) and true or false,
                objectives = objectives,
            }
        end
    end
    return entries
end

--- True when the client can tell where its quest markers are (retail API).
function WowApiAdapter:hasQuestPoiApi()
    local questLog = self.env.C_QuestLog
    return questLog ~= nil and (questLog.GetQuestsOnMap ~= nil or questLog.GetNextWaypoint ~= nil)
end

--- Quest markers the game itself draws on the map: the objective area of an
--- unfinished quest, or the turn-in NPC of a finished one.
--- Returns { [questID] = { mapID, x, y } } with x/y in percent (0-100).
---   1. C_QuestLog.GetQuestsOnMap(mapID) for the player's map, then its parent
---      maps (zone -> continent); the most specific map wins.
---   2. C_QuestLog.GetNextWaypoint(questID) for quests still missing
---      (e.g. the objective is in another zone).
--- Every call is protected with pcall: if a client lacks or changed an API,
--- the quest simply gets no marker.
function WowApiAdapter:getQuestPoiLocations(questIDs)
    local env = self.env
    local questLog, map = env.C_QuestLog, env.C_Map
    local result = {}
    if not questLog then
        return result
    end
    if questLog.GetQuestsOnMap and map and map.GetBestMapForUnit then
        local mapID = map.GetBestMapForUnit("player")
        local depth = 0
        while mapID and mapID ~= 0 and depth < 4 do
            local ok, list = pcall(questLog.GetQuestsOnMap, mapID)
            if ok and type(list) == "table" then
                for i = 1, #list do
                    local poi = list[i]
                    if type(poi) == "table" and poi.questID and poi.x and poi.y and not result[poi.questID]
                        and not (poi.x == 0 and poi.y == 0) then
                        result[poi.questID] = { mapID = mapID, x = poi.x * 100, y = poi.y * 100 }
                    end
                end
            end
            local info = map.GetMapInfo and map.GetMapInfo(mapID)
            mapID = info and info.parentMapID or nil
            depth = depth + 1
        end
    end
    if questLog.GetNextWaypoint and questIDs then
        for i = 1, #questIDs do
            local questID = questIDs[i]
            if not result[questID] then
                local ok, waypointMap, x, y = pcall(questLog.GetNextWaypoint, questID)
                if ok and type(waypointMap) == "number" and type(x) == "number" and type(y) == "number" then
                    result[questID] = { mapID = waypointMap, x = x * 100, y = y * 100 }
                end
            end
        end
    end
    return result
end

function WowApiAdapter:isQuestCompleted(questID)
    local env = self.env
    if env.C_QuestLog and env.C_QuestLog.IsQuestFlaggedCompleted then
        return env.C_QuestLog.IsQuestFlaggedCompleted(questID) and true or false
    end
    if env.IsQuestFlaggedCompleted then
        return env.IsQuestFlaggedCompleted(questID) and true or false
    end
    return false
end

----------------------------------------------------------------------------
-- Player and map
----------------------------------------------------------------------------

--- { version = "12.1.5", build = "70961", interface = 120105 } (empty when unknown)
function WowApiAdapter:getClientInfo()
    local env = self.env
    if env.GetBuildInfo then
        local version, build, _, interface = env.GetBuildInfo()
        return { version = version, build = build, interface = interface }
    end
    return {}
end

function WowApiAdapter:hasWaypointApi()
    local env = self.env
    return env.C_Map ~= nil and env.C_Map.SetUserWaypoint ~= nil and env.UiMapPoint ~= nil
end

function WowApiAdapter:getPlayerInfo()
    local env = self.env
    return {
        name = env.UnitName and env.UnitName("player") or "?",
        level = env.UnitLevel and env.UnitLevel("player") or 1,
        faction = env.UnitFactionGroup and env.UnitFactionGroup("player") or nil,
    }
end

--- Returns mapID, x, y (x/y in percent 0-100) or nil when unknown (e.g. instances).
--- Map the game puts the player on (may exist even when the position does not,
--- e.g. on ships and in instances). nil when unknown.
function WowApiAdapter:getPlayerMapID()
    local map = self.env.C_Map
    if not (map and map.GetBestMapForUnit) then
        return nil
    end
    local ok, mapID = pcall(map.GetBestMapForUnit, "player")
    if ok and type(mapID) == "number" and mapID ~= 0 then
        return mapID
    end
    return nil
end

function WowApiAdapter:getPlayerMapPosition()
    local map = self.env.C_Map
    if not (map and map.GetBestMapForUnit and map.GetPlayerMapPosition) then
        return nil
    end
    local mapID = map.GetBestMapForUnit("player")
    if not mapID then
        return nil
    end
    local position = map.GetPlayerMapPosition(mapID, "player")
    if not position then
        return nil
    end
    local x, y = position:GetXY()
    if not x or not y or (x == 0 and y == 0) then
        return nil
    end
    return mapID, x * 100, y * 100
end

--- Converts a map position to world coordinates (yards).
--- Returns continentID, worldX, worldY or nil when the API is unavailable.
function WowApiAdapter:getWorldPosition(mapID, x, y)
    local env = self.env
    local map = env.C_Map
    if not (map and map.GetWorldPosFromMapPos and env.CreateVector2D) then
        return nil
    end
    local continentID, worldPos = map.GetWorldPosFromMapPos(mapID, env.CreateVector2D(x / 100, y / 100))
    if not continentID or not worldPos then
        return nil
    end
    local worldX, worldY = worldPos:GetXY()
    return continentID, worldX, worldY
end

function WowApiAdapter:getMapName(mapID)
    local map = self.env.C_Map
    if map and map.GetMapInfo then
        local info = map.GetMapInfo(mapID)
        if info and info.name then
            return info.name
        end
    end
    local data = ns.MapData and ns.MapData[mapID]
    return data and data.name or ("Map " .. tostring(mapID))
end

--- Puts a map pin on the location when the client supports user waypoints.
--- Returns true on success, false when the client has no waypoint API.
function WowApiAdapter:setWaypoint(mapID, x, y)
    local env = self.env
    local map = env.C_Map
    if not (map and map.SetUserWaypoint and env.UiMapPoint and env.UiMapPoint.CreateFromCoordinates) then
        return false
    end
    local ok = pcall(map.SetUserWaypoint, env.UiMapPoint.CreateFromCoordinates(mapID, x / 100, y / 100))
    if ok and env.C_SuperTrack and env.C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(env.C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    return ok
end

----------------------------------------------------------------------------
-- Misc
----------------------------------------------------------------------------

function WowApiAdapter:printMessage(text)
    local env = self.env
    if env.DEFAULT_CHAT_FRAME then
        env.DEFAULT_CHAT_FRAME:AddMessage(text)
    elseif env.print then
        env.print(text)
    end
end

function WowApiAdapter:after(seconds, callback)
    local timer = self.env.C_Timer
    if timer and timer.After then
        timer.After(seconds, callback)
    else
        callback()
    end
end

function WowApiAdapter:newTicker(seconds, callback)
    local timer = self.env.C_Timer
    if timer and timer.NewTicker then
        return timer.NewTicker(seconds, callback)
    end
    return nil
end

--- Milliseconds, for measuring how long route planning takes.
function WowApiAdapter:clockMs()
    local env = self.env
    if env.debugprofilestop then
        return env.debugprofilestop()
    end
    return os.clock() * 1000
end

function WowApiAdapter:createFrame(frameType, name, parent, template)
    return self.env.CreateFrame(frameType, name, parent, template)
end

function WowApiAdapter:getUIParent()
    return self.env.UIParent
end

function WowApiAdapter:hasBackdropTemplate()
    return self.env.BackdropTemplateMixin ~= nil
end

ns.WowApiAdapter = WowApiAdapter
