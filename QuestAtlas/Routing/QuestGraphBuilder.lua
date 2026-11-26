-- QuestAtlas - Routing/QuestGraphBuilder.lua
-- Builds the graph ATLAS walks on. This is how the quest problem is mapped to
-- ATLAS's "traverse all edges with minimum cost" problem:
--
--   node            = a place (player position, quest NPC, objective area)
--   REQUIRED edge   = one RouteTask, from its first to its last waypoint
--                     (weight = distance walked inside the task).
--                     A turn-in-only task is a self-loop on the NPC's node.
--   OPTIONAL edge   = plain travel between two places (weight = distance).
--                     Travel never counts as "covering" anything.
--   start edge      = optional self-loop on the player's node (label 0);
--                     ATLAS starts its walk from an edge, not from a node.
--
-- Covering every required edge = doing every quest task; preferring shorter
-- extensions (DistanceAwareCostPolicy) = walking less.
local _, ns = ...

local QuestGraphBuilder = ns.Class("QuestGraphBuilder")

QuestGraphBuilder.START_LABEL = 0
QuestGraphBuilder.PLAYER_NODE = 1

--- Exploration orders (Strategy): the order in which ATLAS's DFS visits the
--- edges leaving a node. The DFS order decides which walks the dynamic
--- programming step can build, so different orders give different routes.
local function byLabel(e1, e2)
    return e1.label < e2.label
end

QuestGraphBuilder.ORDERS = {
    -- quest edges first, then the nearest travel edges
    requiredFirstNearest = function(e1, e2)
        if e1.required ~= e2.required then return e1.required end
        if e1.weight ~= e2.weight then return e1.weight < e2.weight end
        return byLabel(e1, e2)
    end,
    -- quest edges first, then the farthest travel edges
    requiredFirstFarthest = function(e1, e2)
        if e1.required ~= e2.required then return e1.required end
        if e1.weight ~= e2.weight then return e1.weight > e2.weight end
        return byLabel(e1, e2)
    end,
    -- travel edges first (farthest first), quest edges last
    travelFirstFarthest = function(e1, e2)
        if e1.required ~= e2.required then return e2.required end
        if e1.weight ~= e2.weight then return e1.weight > e2.weight end
        return byLabel(e1, e2)
    end,
    -- travel edges first (nearest first), quest edges last
    travelFirstNearest = function(e1, e2)
        if e1.required ~= e2.required then return e2.required end
        if e1.weight ~= e2.weight then return e1.weight < e2.weight end
        return byLabel(e1, e2)
    end,
}
QuestGraphBuilder.DEFAULT_ORDER = "requiredFirstNearest"

--- Re-orders the adjacency lists of a built graph with a named order.
function QuestGraphBuilder.applyOrder(graph, orderName)
    local comparator = QuestGraphBuilder.ORDERS[orderName]
    if not comparator then
        error("QuestGraphBuilder: unknown exploration order '" .. tostring(orderName) .. "'", 2)
    end
    graph:sortAdjacency(comparator)
end

function QuestGraphBuilder:init(distanceCalculator)
    self.distanceCalculator = ns.Interfaces.IDistanceCalculator:assert(distanceCalculator, "QuestGraphBuilder")
end

--- Returns { graph, startLabel, nodeLocations = {node -> Location} }
function QuestGraphBuilder:build(startLocation, tasks, orderName)
    local graph = ns.Graph.new()
    local nodeByKey, nodeLocations = {}, {}
    local nextNode = QuestGraphBuilder.PLAYER_NODE

    local function nodeFor(location)
        local key = location:key()
        if not nodeByKey[key] then
            nodeByKey[key] = nextNode
            nodeLocations[nextNode] = location
            nextNode = nextNode + 1
        end
        return nodeByKey[key]
    end

    -- The player gets its own node even if it stands exactly on a quest NPC.
    local playerNode = QuestGraphBuilder.PLAYER_NODE
    nodeLocations[playerNode] = startLocation
    nextNode = playerNode + 1
    graph:addVertex(playerNode)

    local label = QuestGraphBuilder.START_LABEL
    graph:addEdge(label, playerNode, playerNode, "start", nil, 0, false)
    graph:addStart(label)

    local distance = self.distanceCalculator
    for i = 1, #tasks do
        local task = tasks[i]
        label = label + 1
        graph:addEdge(label, nodeFor(task:startLocation()), nodeFor(task:endLocation()), task.id, nil,
            task:internalDistance(distance), true, { task = task })
    end

    -- Travel edges: complete directed graph between all places (none back to the player node).
    local nodes = graph:getNodes()
    for a = 1, #nodes do
        for b = 1, #nodes do
            local from, to = nodes[a], nodes[b]
            if from ~= to and to ~= playerNode then
                label = label + 1
                graph:addEdge(label, from, to, "travel", nil,
                    distance:distance(nodeLocations[from], nodeLocations[to]), false)
            end
        end
    end

    QuestGraphBuilder.applyOrder(graph, orderName or QuestGraphBuilder.DEFAULT_ORDER)

    return { graph = graph, startLabel = QuestGraphBuilder.START_LABEL, nodeLocations = nodeLocations }
end

ns.QuestGraphBuilder = QuestGraphBuilder
