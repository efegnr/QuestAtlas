-- QuestAtlas - Routing/RouteStrategies.lua
-- Strategy pattern: interchangeable route planning algorithms.
-- IRouteStrategy:
--   getName()                  -> "atlas" | "nearest" | "bruteforce"
--   plan(start, tasks)         -> Route
-- All of them return their result through RouteAssembler, so a caller can
-- swap one for another without noticing (SOLID - L).
local _, ns = ...

----------------------------------------------------------------------------
-- AtlasRouteStrategy (default): maps the tasks onto a graph and lets ATLAS
-- find a walk that covers every quest edge (see QuestGraphBuilder).
-- Multi-start: ATLAS runs once per exploration order (DFS neighbour order)
-- and the shortest resulting route wins. With one order it is plain ATLAS.
----------------------------------------------------------------------------
local AtlasRouteStrategy = ns.Class("AtlasRouteStrategy")

AtlasRouteStrategy.DEFAULT_ORDERS = {
    "requiredFirstNearest", "requiredFirstFarthest", "travelFirstFarthest", "travelFirstNearest",
}
-- Above this many tasks only the first order is used, so a re-plan stays fast
-- in the game (the graph grows quadratically with the number of places).
AtlasRouteStrategy.MULTI_START_LIMIT = 12

--- options = { orders = {orderName...}, multiStartLimit = n, graphBuilder = ..., atlas = ... } (all optional)
function AtlasRouteStrategy:init(distanceCalculator, options)
    options = options or {}
    self.distanceCalculator = distanceCalculator
    self.orders = options.orders or AtlasRouteStrategy.DEFAULT_ORDERS
    self.multiStartLimit = options.multiStartLimit or AtlasRouteStrategy.MULTI_START_LIMIT
    self.graphBuilder = options.graphBuilder or ns.QuestGraphBuilder.new(distanceCalculator)
    self.atlas = options.atlas or ns.Atlas.new({ costPolicy = ns.DistanceAwareCostPolicy.new(), keepLastEdge = true })
end

function AtlasRouteStrategy:getName()
    return "atlas"
end

--- Returns the walk (edge labels) ATLAS computes plus the built graph.
function AtlasRouteStrategy:computeWalk(start, tasks, orderName)
    local built = self.graphBuilder:build(start, tasks, orderName or self.orders[1])
    local walk = self.atlas:longestPath(built.graph, built.startLabel)
    return walk, built
end

--- The order in which a walk covers the quest edges = the task order.
function AtlasRouteStrategy.taskOrderFromWalk(graph, walk, tasks)
    local order, seen = {}, {}
    for i = 1, #walk do
        local edge = graph:getEdge(walk[i])
        if edge.required and not seen[edge.label] then
            seen[edge.label] = true
            order[#order + 1] = edge.data.task
        end
    end
    -- Safety net: ATLAS covers every reachable required edge, and every quest
    -- edge is reachable (travel edges form a complete graph). Keep any missing
    -- task anyway so a quest can never silently disappear from the route.
    if #order < #tasks then
        for i = 1, #tasks do
            if not ns.Util.contains(order, tasks[i]) then
                order[#order + 1] = tasks[i]
            end
        end
    end
    return order
end

function AtlasRouteStrategy:plan(start, tasks)
    if #tasks == 0 then
        return ns.Route.empty(self:getName())
    end
    local built = self.graphBuilder:build(start, tasks, self.orders[1])
    local best = nil
    local orderCount = #tasks <= self.multiStartLimit and #self.orders or 1
    for i = 1, orderCount do
        ns.QuestGraphBuilder.applyOrder(built.graph, self.orders[i])
        local walk = self.atlas:longestPath(built.graph, built.startLabel)
        local order = AtlasRouteStrategy.taskOrderFromWalk(built.graph, walk, tasks)
        local route = ns.RouteAssembler.fromTaskOrder(self:getName(), start, order, self.distanceCalculator)
        if not best or route.totalDistance < best.totalDistance - 1e-9 then
            best = route
            best.atlasOrder = self.orders[i]
            best.atlasWalkLength = #walk
        end
    end
    return best
end

----------------------------------------------------------------------------
-- NearestNeighborRouteStrategy: greedy baseline - always go to the closest
-- unfinished task next.
----------------------------------------------------------------------------
local NearestNeighborRouteStrategy = ns.Class("NearestNeighborRouteStrategy")

function NearestNeighborRouteStrategy:init(distanceCalculator)
    self.distanceCalculator = distanceCalculator
end

function NearestNeighborRouteStrategy:getName()
    return "nearest"
end

function NearestNeighborRouteStrategy:order(start, tasks)
    local remaining = ns.Util.shallowCopy(tasks)
    local order, current = {}, start
    while #remaining > 0 do
        local bestIndex, bestDistance = 1, math.huge
        for i = 1, #remaining do
            local d = self.distanceCalculator:distance(current, remaining[i]:startLocation())
            if d < bestDistance then
                bestIndex, bestDistance = i, d
            end
        end
        local task = table.remove(remaining, bestIndex)
        order[#order + 1] = task
        current = task:endLocation()
    end
    return order
end

function NearestNeighborRouteStrategy:plan(start, tasks)
    return ns.RouteAssembler.fromTaskOrder(self:getName(), start, self:order(start, tasks), self.distanceCalculator)
end

----------------------------------------------------------------------------
-- BruteForceRouteStrategy: tries every order (branch and bound) and returns
-- the optimum. Exponential, so above `maxTasks` it delegates to a fallback
-- strategy. Used as the yardstick for ATLAS in the tests.
----------------------------------------------------------------------------
local BruteForceRouteStrategy = ns.Class("BruteForceRouteStrategy")

function BruteForceRouteStrategy:init(distanceCalculator, maxTasks, fallback)
    self.distanceCalculator = distanceCalculator
    self.maxTasks = maxTasks or 8
    self.fallback = fallback or NearestNeighborRouteStrategy.new(distanceCalculator)
end

function BruteForceRouteStrategy:getName()
    return "bruteforce"
end

function BruteForceRouteStrategy:plan(start, tasks)
    if #tasks > self.maxTasks then
        local route = self.fallback:plan(start, tasks)
        route.strategyName = self:getName() .. ">" .. self.fallback:getName()
        return route
    end
    local calc = self.distanceCalculator
    local internal = {}
    for i = 1, #tasks do
        internal[i] = tasks[i]:internalDistance(calc)
    end

    local used, current = {}, {}
    local bestOrder, bestDistance = nil, math.huge

    local function search(location, depth, travelled)
        if travelled >= bestDistance then
            return -- bound: cannot beat the best order found so far
        end
        if depth > #tasks then
            bestDistance = travelled
            bestOrder = ns.Util.shallowCopy(current)
            return
        end
        for i = 1, #tasks do
            if not used[i] then
                used[i] = true
                current[depth] = tasks[i]
                search(tasks[i]:endLocation(), depth + 1,
                    travelled + calc:distance(location, tasks[i]:startLocation()) + internal[i])
                current[depth] = nil
                used[i] = false
            end
        end
    end

    search(start, 1, 0)
    return ns.RouteAssembler.fromTaskOrder(self:getName(), start, bestOrder or {}, calc)
end

ns.AtlasRouteStrategy = AtlasRouteStrategy
ns.NearestNeighborRouteStrategy = NearestNeighborRouteStrategy
ns.BruteForceRouteStrategy = BruteForceRouteStrategy
