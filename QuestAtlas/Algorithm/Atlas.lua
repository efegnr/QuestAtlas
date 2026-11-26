-- QuestAtlas - Algorithm/Atlas.lua
-- Lua port of Atlas.java - "ATLAS: new heuristic algorithm for traversing all
-- edges with minimum cost" (https://github.com/savastakan/atlas).
--
-- How ATLAS works (one iteration of longestPath):
--   1. Take the last edge of the current walk (`currentStart`).
--   2. Run a DFS over EDGES starting from it; the DFS post-order gives an
--      ordering in which every edge comes after the edge it was discovered from
--      (back edges are ignored, so the graph is treated like a DAG).
--   3. Pop the edges in reverse post-order and relax their successors like a
--      longest-path computation on a DAG (dynamic programming):
--          cost[next] = cost[edge] + (next already in the walk ? 0 : 1)
--      `comeFrom` remembers the predecessor of every edge.
--   4. The edge with the highest cost is the end of the best extension; follow
--      `comeFrom` back to `currentStart` and append that chain to the walk.
--   5. Repeat until no extension covers a new edge.
--
-- Differences to the Java code (all optional, defaults noted):
--   * costPolicy  (default UnitCostPolicy = exactly the Java cost).
--   * Edges may be optional (edge.required == false); they never add gain.
--     All edges are required by default, as in Java.
--   * keepLastEdge (default true). The Java loop starts with
--     `path.removeLast()` and returns without adding that edge back, so the
--     returned walk misses its final edge (with bbtas.kiss2.fsm edge 10 is
--     never covered). keepLastEdge = true appends it again;
--     keepLastEdge = false reproduces the Java output 1:1 (see tests).
--   * The recursive DFS is written iteratively (same post-order) so large
--     graphs cannot overflow the Lua call stack.
--   * If no successor can be relaxed at all, Java would index cost[MIN_VALUE]
--     and crash; here the walk simply terminates.
local _, ns = ...

local Atlas = ns.Class("Atlas")

function Atlas:init(options)
    options = options or {}
    self.costPolicy = ns.Interfaces.ICostPolicy:assert(options.costPolicy or ns.UnitCostPolicy.new(), "Atlas")
    self.keepLastEdge = options.keepLastEdge ~= false
end

--- Iterative version of Atlas.dfs(graph, edge, cost, stack).
--- `marked` plays the role of `cost[label] = Integer.MIN_VALUE`.
--- Edges are pushed onto `stack` in DFS post-order.
function Atlas:dfs(graph, startEdge, marked, stack)
    marked[startEdge.label] = true
    local frames = {
        { edge = startEdge, neighbors = graph:edgeLabels(startEdge.destination), index = 0 },
    }
    while #frames > 0 do
        local frame = frames[#frames]
        frame.index = frame.index + 1
        local neighborLabel = frame.neighbors[frame.index]
        if neighborLabel == nil then
            frames[#frames] = nil
            stack[#stack + 1] = frame.edge
        elseif not marked[neighborLabel] then
            marked[neighborLabel] = true
            local neighbor = graph:getEdge(neighborLabel)
            frames[#frames + 1] = { edge = neighbor, neighbors = graph:edgeLabels(neighbor.destination), index = 0 }
        end
    end
end

--- One ATLAS extension step. Returns the chain of edge labels to append
--- (starting with currentStart) or nil when no extension gains anything.
function Atlas:bestExtension(graph, currentStart, coverCount)
    local policy = self.costPolicy
    local stack, marked = {}, {}
    self:dfs(graph, graph:getEdge(currentStart), marked, stack)

    local cost, comeFrom, visited = {}, {}, {}
    cost[currentStart] = policy:initial()
    local current, currentCost = nil, nil

    for i = #stack, 1, -1 do -- Stack.pop() order
        local edge = stack[i]
        visited[edge.label] = true
        local edgeCost = cost[edge.label]
        local neighbors = graph:edgeLabels(edge.destination)
        for j = 1, #neighbors do
            local neighborLabel = neighbors[j]
            if not visited[neighborLabel] then
                local neighbor = graph:getEdge(neighborLabel)
                local isNew = neighbor.required and (coverCount[neighborLabel] or 0) == 0
                local newCost = policy:extend(edgeCost, neighbor, isNew)
                if policy:isBetter(newCost, cost[neighborLabel]) then
                    cost[neighborLabel] = newCost
                    comeFrom[neighborLabel] = edge.label
                    if policy:isBetter(newCost, currentCost) then
                        currentCost = newCost
                        current = neighborLabel
                    end
                end
            end
        end
    end

    if current == nil or not policy:hasGain(currentCost) then
        return nil
    end

    local reversed = {}
    local label = current
    while label ~= nil do
        reversed[#reversed + 1] = label
        label = comeFrom[label]
    end
    local chain = {}
    for k = #reversed, 1, -1 do
        chain[#chain + 1] = reversed[k]
    end
    return chain
end

--- Port of Atlas.longestPath(graph, start): returns the walk as a list of edge labels.
function Atlas:longestPath(graph, startLabel)
    assert(graph:getEdge(startLabel), "Atlas:longestPath - unknown start edge " .. tostring(startLabel))
    local path = { startLabel }
    local coverCount = { [startLabel] = 1 } -- multiset view of `path` (path.contains)

    -- Every productive iteration covers at least one new edge, so this bound is never hit.
    for _ = 1, graph:getEdgeCount() + 1 do
        local currentStart = table.remove(path) -- path.removeLast()
        coverCount[currentStart] = coverCount[currentStart] - 1

        local chain = self:bestExtension(graph, currentStart, coverCount)
        if chain == nil then
            if self.keepLastEdge then
                path[#path + 1] = currentStart
                coverCount[currentStart] = coverCount[currentStart] + 1
            end
            return path
        end
        for k = 1, #chain do
            path[#path + 1] = chain[k]
            coverCount[chain[k]] = (coverCount[chain[k]] or 0) + 1
        end
    end
    error("Atlas:longestPath - iteration limit exceeded")
end

--- Port of Atlas.getTestSuite: the inputs along the walk, comma separated.
function Atlas:getTestSuite(graph, path)
    local inputs = {}
    for i = 1, #path do
        inputs[i] = tostring(graph:getEdge(path[i]).input)
    end
    return table.concat(inputs, ",")
end

--- Port of Atlas.run: walk from the first start edge, returned as a test suite.
function Atlas:run(graph)
    local starts = graph:getStarts()
    assert(#starts > 0, "Atlas:run - graph has no start edge")
    return self:getTestSuite(graph, self:longestPath(graph, starts[1]))
end

--- Helper: which required edges does `path` cover? Returns covered, total, missingLabels.
function Atlas.coverage(graph, path)
    local seen = {}
    for i = 1, #path do
        seen[path[i]] = true
    end
    local covered, total, missing = 0, 0, {}
    local labels = graph:getEdgeLabels()
    for i = 1, #labels do
        if graph:getEdge(labels[i]).required then
            total = total + 1
            if seen[labels[i]] then
                covered = covered + 1
            else
                missing[#missing + 1] = labels[i]
            end
        end
    end
    return covered, total, missing
end

--- Helper: true when consecutive edges of `path` are connected.
function Atlas.isContinuous(graph, path)
    for i = 2, #path do
        if graph:getEdge(path[i - 1]).destination ~= graph:getEdge(path[i]).source then
            return false
        end
    end
    return true
end

ns.Atlas = Atlas
