-- QuestAtlas - Routing/RouteTaskBuilder.lua
-- Turns quests into RouteTasks - the units the route strategies schedule.
--   PLANNED     : giver (ACCEPT) -> objective locations -> turn-in NPC
--   IN_PROGRESS : unfinished objective locations -> turn-in NPC
--                 (turn-in left out while unknown: the game's map marker only
--                  shows the objective area until the objectives are done)
--   READY       : turn-in NPC
-- The waypoints of one task are always visited in this order, which keeps
-- "objectives before turn-in" true for every route.
-- Quests with an identical itinerary are merged into a single task.
local _, ns = ...

local RouteTaskBuilder = ns.Class("RouteTaskBuilder")

local function addWaypoint(waypoints, location, kind, quest)
    local last = waypoints[#waypoints]
    if last and last.kind == kind and last.location:equals(location) then
        return -- two objectives at the same spot = one stop
    end
    waypoints[#waypoints + 1] = { location = location, kind = kind, quests = { quest } }
end

--- Returns the waypoint list, or nil when the quest cannot be routed because
--- none of its unfinished objectives has a known location.
function RouteTaskBuilder:waypointsFor(quest)
    local waypoints = {}
    if quest:isPlanned() then
        addWaypoint(waypoints, quest.giver, ns.StepKind.ACCEPT, quest)
    end
    if not quest:isReady() then
        local remaining = quest:remainingObjectives()
        local located = 0
        for i = 1, #remaining do
            if remaining[i].location then
                located = located + 1
                addWaypoint(waypoints, remaining[i].location, ns.StepKind.OBJECTIVE, quest)
            end
        end
        if #remaining > 0 and located == 0 then
            return nil
        end
    end
    if quest.turnIn then
        addWaypoint(waypoints, quest.turnIn, ns.StepKind.TURN_IN, quest)
    end
    if #waypoints == 0 then
        return nil
    end
    return waypoints
end

--- Returns tasks, unroutableQuests
function RouteTaskBuilder:build(quests)
    local tasks, unroutable, bySignature = {}, {}, {}
    for i = 1, #quests do
        local quest = quests[i]
        local waypoints = quest:isRoutable() and self:waypointsFor(quest) or nil
        if waypoints then
            local task = ns.RouteTask.new("Q" .. tostring(quest.id), waypoints, { quest })
            local signature = task:signature()
            local existing = bySignature[signature]
            if existing then
                existing.quests[#existing.quests + 1] = quest
                for w = 1, #existing.waypoints do
                    local list = existing.waypoints[w].quests
                    list[#list + 1] = quest
                end
                existing.id = existing.id .. "+" .. tostring(quest.id)
            else
                bySignature[signature] = task
                tasks[#tasks + 1] = task
            end
        else
            unroutable[#unroutable + 1] = quest
        end
    end
    return tasks, unroutable
end

ns.RouteTaskBuilder = RouteTaskBuilder
