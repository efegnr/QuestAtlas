-- QuestAtlas - Algorithm/Graph.lua
-- Lua port of Graph.java from the original ATLAS implementation.
-- A directed multigraph whose edges have integer labels. For every node the
-- labels of its outgoing edges are kept in insertion order (Java used a
-- HashSet; for small integer labels that iterates in ascending order, which is
-- what insertion order gives for parsed FSM files).
local _, ns = ...

local EMPTY = {}

local Graph = ns.Class("Graph")

function Graph:init()
    self.nodes = {}       -- node -> ordered list of outgoing edge labels
    self.nodeList = {}    -- nodes in insertion order
    self.edges = {}       -- label -> Edge
    self.edgeLabelList = {}
    self.starts = {}
    self.finishes = {}
end

function Graph:addVertex(node)
    if not self.nodes[node] then
        self.nodes[node] = {}
        self.nodeList[#self.nodeList + 1] = node
    end
end

function Graph:addEdge(label, source, destination, input, output, weight, required, data)
    if self.edges[label] then
        error("Graph:addEdge - duplicate edge label " .. tostring(label), 2)
    end
    self:addVertex(source)
    self:addVertex(destination)
    local edge = ns.Edge.new(label, source, destination, input, output, weight, required, data)
    local outgoing = self.nodes[source]
    outgoing[#outgoing + 1] = label
    self.edges[label] = edge
    self.edgeLabelList[#self.edgeLabelList + 1] = label
    return edge
end

function Graph:getEdge(label)
    return self.edges[label]
end

--- All edge labels in insertion order (a copy).
function Graph:getEdgeLabels()
    return ns.Util.shallowCopy(self.edgeLabelList)
end

--- Labels of the edges leaving `node`. The returned list must not be modified.
function Graph:edgeLabels(node)
    return self.nodes[node] or EMPTY
end

function Graph:getEdgeCount()
    return #self.edgeLabelList
end

function Graph:getNodes()
    return self.nodeList
end

function Graph:getStarts()
    return self.starts
end

function Graph:addStart(label)
    if not ns.Util.contains(self.starts, label) then
        self.starts[#self.starts + 1] = label
    end
end

function Graph:getFinishes()
    return self.finishes
end

function Graph:addFinish(label)
    if not ns.Util.contains(self.finishes, label) then
        self.finishes[#self.finishes + 1] = label
    end
end

function Graph:getRequiredEdgeCount()
    local count = 0
    for i = 1, #self.edgeLabelList do
        if self.edges[self.edgeLabelList[i]].required then
            count = count + 1
        end
    end
    return count
end

--- Re-orders every adjacency list with `comparator(edgeA, edgeB)`.
--- ATLAS explores neighbours in this order, so it acts as a heuristic hint.
function Graph:sortAdjacency(comparator)
    local edges = self.edges
    for i = 1, #self.nodeList do
        table.sort(self.nodes[self.nodeList[i]], function(a, b)
            return comparator(edges[a], edges[b])
        end)
    end
end

ns.Graph = Graph
