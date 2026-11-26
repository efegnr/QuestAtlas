-- QuestAtlas - Algorithm/Edge.lua
-- Lua port of Edge.java from the original ATLAS implementation
-- (https://github.com/savastakan/atlas).
--
-- Two optional fields were added for the quest domain; with their default
-- values the edge behaves exactly like the Java one:
--   required (default true) - the walk must cover this edge (quest task);
--                             false = optional edge (plain travel).
--   data     (default nil)  - payload, e.g. the RouteTask behind a quest edge.
local _, ns = ...

local Edge = ns.Class("Edge")

function Edge:init(label, source, destination, input, output, weight, required, data)
    self.label = label
    self.source = source
    self.destination = destination
    self.input = input
    self.output = output
    self.weight = weight or 1
    self.required = required ~= false
    self.data = data
end

function Edge:getLabel()
    return self.label
end

function Edge:isSelfLoop()
    return self.source == self.destination
end

ns.Edge = Edge
