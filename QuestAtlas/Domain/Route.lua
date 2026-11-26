-- QuestAtlas - Domain/Route.lua
-- Value objects produced by route planning.
--   RouteTask : one unit of work the router must schedule (one quest, or quests
--               with an identical itinerary), an ordered list of waypoints.
--   RouteStep : one stop of the final route ("go to X and do Y").
--   Route     : the ordered steps + total distance.
local _, ns = ...

local StepKind = {
    ACCEPT = "ACCEPT",       -- pick up a quest from its giver
    OBJECTIVE = "OBJECTIVE", -- complete objectives at a location
    TURN_IN = "TURN_IN",     -- hand in a quest
}

----------------------------------------------------------------------------
local RouteTask = ns.Class("RouteTask")

--- waypoints: list of { location = Location, kind = StepKind, quests = {Quest...} }
function RouteTask:init(id, waypoints, quests)
    assert(#waypoints > 0, "RouteTask needs at least one waypoint")
    self.id = id
    self.waypoints = waypoints
    self.quests = quests
end

function RouteTask:startLocation()
    return self.waypoints[1].location
end

function RouteTask:endLocation()
    return self.waypoints[#self.waypoints].location
end

--- A signature: tasks with the same signature can be merged into one.
function RouteTask:signature()
    local parts = {}
    for i = 1, #self.waypoints do
        parts[i] = self.waypoints[i].kind .. "@" .. self.waypoints[i].location:key()
    end
    return table.concat(parts, ">")
end

--- Distance travelled INSIDE the task (from first to last waypoint).
function RouteTask:internalDistance(distanceCalculator)
    local total = 0
    for i = 2, #self.waypoints do
        total = total + distanceCalculator:distance(self.waypoints[i - 1].location, self.waypoints[i].location)
    end
    return total
end

function RouteTask:questTitles()
    return ns.Util.map(self.quests, function(q) return q.title end)
end

----------------------------------------------------------------------------
local RouteStep = ns.Class("RouteStep")

function RouteStep:init(kind, location, quests, legDistance, cumulativeDistance)
    self.kind = kind
    self.location = location
    self.quests = quests
    self.legDistance = legDistance
    self.cumulativeDistance = cumulativeDistance
end

----------------------------------------------------------------------------
local Route = ns.Class("Route")

function Route:init(strategyName, steps, totalDistance, taskOrder)
    self.strategyName = strategyName
    self.steps = steps or {}
    self.totalDistance = totalDistance or 0
    self.taskOrder = taskOrder or {}
    self.unroutable = {}
    self.computeTimeMs = 0
    self.reason = nil -- why the route is empty (e.g. "NO_POSITION")
end

function Route.empty(strategyName, reason)
    local route = Route.new(strategyName, {}, 0, {})
    route.reason = reason
    return route
end

function Route:isEmpty()
    return #self.steps == 0
end

function Route:getNextStep()
    return self.steps[1]
end

----------------------------------------------------------------------------
-- RouteAssembler: turns an ordered list of tasks into a Route. Every strategy
-- uses it, so all strategies return routes in exactly the same format
-- (makes the strategies interchangeable - SOLID - L).
----------------------------------------------------------------------------
local RouteAssembler = {}

--- Total travel distance of doing `tasks` in the given order, starting at `start`.
function RouteAssembler.orderDistance(start, tasks, distanceCalculator)
    local total, current = 0, start
    for i = 1, #tasks do
        total = total + distanceCalculator:distance(current, tasks[i]:startLocation())
            + tasks[i]:internalDistance(distanceCalculator)
        current = tasks[i]:endLocation()
    end
    return total
end

function RouteAssembler.fromTaskOrder(strategyName, start, tasks, distanceCalculator)
    local steps, total, current = {}, 0, start
    for i = 1, #tasks do
        local waypoints = tasks[i].waypoints
        for w = 1, #waypoints do
            local waypoint = waypoints[w]
            local leg = distanceCalculator:distance(current, waypoint.location)
            total = total + leg
            local last = steps[#steps]
            if last and last.kind == waypoint.kind and last.location:equals(waypoint.location) then
                -- Same place, same action: merge ("turn in A and B at McBride").
                for q = 1, #waypoint.quests do
                    last.quests[#last.quests + 1] = waypoint.quests[q]
                end
            else
                steps[#steps + 1] = RouteStep.new(waypoint.kind, waypoint.location,
                    ns.Util.shallowCopy(waypoint.quests), leg, total)
            end
            current = waypoint.location
        end
    end
    return Route.new(strategyName, steps, total, tasks)
end

ns.StepKind = StepKind
ns.RouteTask = RouteTask
ns.RouteStep = RouteStep
ns.Route = Route
ns.RouteAssembler = RouteAssembler
