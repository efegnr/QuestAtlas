-- QuestAtlas - Routing/RoutePlanner.lua
-- Coordinates route planning: quests -> tasks -> strategy -> Route.
-- Depends only on abstractions it receives in the constructor (SOLID - D).
local _, ns = ...

local RoutePlanner = ns.Class("RoutePlanner")

--- clock: function() -> milliseconds (for timing the planning)
function RoutePlanner:init(taskBuilder, strategyFactory, clock)
    self.taskBuilder = taskBuilder
    self.strategyFactory = strategyFactory
    self.clock = clock or function() return os.clock() * 1000 end
end

--- A string that changes only when the route would change: the strategy, the
--- waypoints of every task and the unroutable quests. Objective progress
--- ("3/10 -> 4/10") does not change it.
function RoutePlanner.signatureOf(strategyName, tasks, unroutable)
    local parts = {}
    for i = 1, #tasks do
        parts[#parts + 1] = tasks[i].id .. "=" .. tasks[i]:signature()
    end
    table.sort(parts)
    local missing = {}
    for i = 1, #unroutable do
        missing[i] = tostring(unroutable[i].id)
    end
    table.sort(missing)
    return tostring(strategyName) .. "|" .. table.concat(parts, ";") .. "|" .. table.concat(missing, ",")
end

function RoutePlanner:signature(quests, strategyName)
    local tasks, unroutable = self.taskBuilder:build(quests)
    return RoutePlanner.signatureOf(strategyName, tasks, unroutable)
end

function RoutePlanner:plan(start, quests, strategyName)
    local tasks, unroutable = self.taskBuilder:build(quests)
    local route
    if not start then
        route = ns.Route.empty(strategyName, "NO_POSITION")
    elseif #tasks == 0 then
        route = ns.Route.empty(strategyName, "NO_TASKS")
    else
        local strategy = self.strategyFactory:create(strategyName)
        local began = self.clock()
        route = strategy:plan(start, tasks)
        route.computeTimeMs = self.clock() - began
    end
    route.unroutable = unroutable
    route.signature = RoutePlanner.signatureOf(strategyName, tasks, unroutable)
    return route
end

--- Runs every registered strategy on the same input.
--- Returns a list of { name, distance, timeMs, steps }.
function RoutePlanner:compare(start, quests)
    local results = {}
    if not start then
        return results
    end
    local names = self.strategyFactory:getNames()
    for i = 1, #names do
        local route = self:plan(start, quests, names[i])
        results[#results + 1] = {
            name = names[i], distance = route.totalDistance, timeMs = route.computeTimeMs, steps = #route.steps,
        }
    end
    return results
end

ns.RoutePlanner = RoutePlanner
