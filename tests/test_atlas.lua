-- tests/test_atlas.lua - the Lua port of ATLAS against the original Java code
return function(T, ctx)
    T.suite("ATLAS algorithm (port of github.com/savastakan/atlas)")

    local expected = dofile(ctx.root .. "/tests/fixtures/atlas_java_expected.lua")

    local function sortedNames(tbl)
        local names = {}
        for name in pairs(tbl) do names[#names + 1] = name end
        table.sort(names)
        return names
    end

    T.test("bbtas.kiss2.fsm: identical to the UNMODIFIED Java implementation", function()
        local ns = ctx.loadAddon()
        local graph = ctx.kissGraph(ns, "bbtas.kiss2.fsm")
        local atlas = ns.Atlas.new({ keepLastEdge = false }) -- Java behaviour 1:1
        local path = atlas:longestPath(graph, graph:getStarts()[1])
        T.deepEq(path, expected.hashset["bbtas.kiss2.fsm"].path, "walk")
        T.eq(atlas:getTestSuite(graph, path), expected.hashset["bbtas.kiss2.fsm"].suite, "test suite")
        T.eq(atlas:run(graph), expected.hashset["bbtas.kiss2.fsm"].suite, "run()")
    end)

    T.test("random FSMs: identical to Java (neighbours in ascending order)", function()
        local ns = ctx.loadAddon()
        local names = sortedNames(expected.treeset)
        T.ok(#names >= 9, "fixtures present")
        for _, name in ipairs(names) do
            local graph = ctx.kissGraph(ns, name)
            local atlas = ns.Atlas.new({ keepLastEdge = false })
            local path = atlas:longestPath(graph, graph:getStarts()[1])
            T.deepEq(path, expected.treeset[name].path, name)
            T.eq(atlas:getTestSuite(graph, path), expected.treeset[name].suite, name .. " suite")
        end
    end)

    T.test("Java drops the last edge: bbtas edge 10 is never covered", function()
        local ns = ctx.loadAddon()
        local graph = ctx.kissGraph(ns, "bbtas.kiss2.fsm")
        local path = ns.Atlas.new({ keepLastEdge = false }):longestPath(graph, 0)
        local covered, total, missing = ns.Atlas.coverage(graph, path)
        T.eq(total, 24)
        T.eq(covered, 23)
        T.deepEq(missing, { 10 })
    end)

    T.test("keepLastEdge (default): covers ALL 24 edges of bbtas, walk stays connected", function()
        local ns = ctx.loadAddon()
        local graph = ctx.kissGraph(ns, "bbtas.kiss2.fsm")
        local path = ns.Atlas.new():longestPath(graph, 0)
        local javaPath = expected.hashset["bbtas.kiss2.fsm"].path
        T.eq(#path, #javaPath + 1, "one edge longer than the Java walk")
        for i = 1, #javaPath do
            T.eq(path[i], javaPath[i], "same prefix as Java at " .. i)
        end
        T.eq(path[#path], 10, "the dropped edge is appended")
        local covered, total = ns.Atlas.coverage(graph, path)
        T.eq(covered, total)
        T.ok(ns.Atlas.isContinuous(graph, path), "consecutive edges are connected")
    end)

    T.test("keepLastEdge: every REACHABLE edge is covered on all fixtures", function()
        local ns = ctx.loadAddon()
        for _, name in ipairs(sortedNames(expected.treeset)) do
            local graph = ctx.kissGraph(ns, name)
            local start = graph:getStarts()[1]
            local path = ns.Atlas.new():longestPath(graph, start)
            local reachable = ctx.reachableEdges(graph, start)
            local inPath = {}
            for _, label in ipairs(path) do inPath[label] = true end
            for _, label in ipairs(graph:getEdgeLabels()) do
                T.eq(inPath[label] == true, reachable[label] == true,
                    name .. ": edge " .. label .. " covered iff reachable")
            end
            T.ok(ns.Atlas.isContinuous(graph, path), name .. " continuous")
        end
    end)

    T.test("dead end (no successor at all) terminates instead of crashing like Java", function()
        local ns = ctx.loadAddon()
        local graph = ns.Graph.new()
        graph:addEdge(0, 0, 1, 0, 0, 1) -- node 1 has no outgoing edges
        graph:addStart(0)
        T.deepEq(ns.Atlas.new():longestPath(graph, 0), { 0 })
        T.deepEq(ns.Atlas.new({ keepLastEdge = false }):longestPath(graph, 0), {})
    end)

    T.test("self-loops and parallel edges are covered", function()
        local ns = ctx.loadAddon()
        local graph = ns.Graph.new()
        graph:addEdge(0, 0, 1, "a", 0, 1)
        graph:addEdge(1, 1, 1, "loop", 0, 1)
        graph:addEdge(2, 1, 0, "b", 0, 1)
        graph:addEdge(3, 1, 0, "c", 0, 1)
        graph:addEdge(4, 0, 1, "d", 0, 1)
        local path = ns.Atlas.new():longestPath(graph, 0)
        local covered, total = ns.Atlas.coverage(graph, path)
        T.eq(covered, total)
        T.ok(ns.Atlas.isContinuous(graph, path))
    end)

    T.test("optional edges never count as covered work", function()
        local ns = ctx.loadAddon()
        local graph = ns.Graph.new()
        graph:addEdge(0, 0, 0, "start", nil, 0, false)
        graph:addEdge(1, 0, 1, "travel", nil, 5, false)
        graph:addEdge(2, 1, 2, "quest", nil, 1, true)
        graph:addEdge(3, 2, 0, "travel", nil, 5, false)
        graph:addEdge(4, 0, 3, "travel", nil, 9, false) -- leads nowhere useful
        local atlas = ns.Atlas.new({ costPolicy = ns.DistanceAwareCostPolicy.new() })
        local path = atlas:longestPath(graph, 0)
        T.deepEq(path, { 0, 1, 2 }, "walk stops right after the only required edge")
    end)

    T.test("DistanceAwareCostPolicy: equal coverage -> the shorter extension wins", function()
        local ns = ctx.loadAddon()
        local graph = ns.Graph.new()
        graph:addEdge(0, 0, 0, "start", nil, 0, false)
        graph:addEdge(1, 0, 1, "long way", nil, 100, false)
        graph:addEdge(2, 0, 2, "short way", nil, 10, false)
        graph:addEdge(3, 1, 3, "quest via long", nil, 1, true)
        graph:addEdge(4, 2, 3, "quest via short", nil, 1, true)
        -- Both quest edges are required; any walk covering one of them first
        -- must prefer the short approach.
        local path = ns.Atlas.new({ costPolicy = ns.DistanceAwareCostPolicy.new() }):longestPath(graph, 0)
        T.eq(path[2], 2, "takes the short approach first")
        T.eq(path[3], 4)
    end)

    T.test("DistanceAwareCostPolicy packs (gain, distance) into one comparable number", function()
        local ns = ctx.loadAddon()
        local policy = ns.DistanceAwareCostPolicy.new()
        local edge = function(weight) return { weight = weight } end
        local twoNewLong = policy:extend(policy:extend(policy:initial(), edge(5000), true), edge(5000), true)
        local oneNewShort = policy:extend(policy:initial(), edge(1), true)
        local oneNewLong = policy:extend(policy:initial(), edge(900), true)
        T.ok(policy:isBetter(twoNewLong, oneNewShort), "more coverage always wins")
        T.ok(policy:isBetter(oneNewShort, oneNewLong), "same coverage: shorter wins")
        T.ok(not policy:isBetter(oneNewShort, oneNewShort), "strictly better only")
        T.ok(not policy:hasGain(policy:extend(policy:initial(), edge(10), false)), "travel only = no gain")
        local gain, distance = ns.DistanceAwareCostPolicy.unpack(twoNewLong)
        T.eq(gain, 2)
        T.near(distance, 10000, 1e-6)
    end)

    T.test("CostPolicyFactory creates known policies and rejects unknown ones", function()
        local ns = ctx.loadAddon()
        T.eq(ns.CostPolicyFactory.create("unit"):getName(), "unit")
        T.eq(ns.CostPolicyFactory.create("distance"):getName(), "distance")
        T.raises(function() ns.CostPolicyFactory.create("magic") end, "Unknown cost policy")
    end)

    T.test("large graph (2 000+ edges) runs without stack overflow", function()
        local ns = ctx.loadAddon()
        local graph = ns.Graph.new()
        local label = 0
        local n = 50
        for a = 0, n - 1 do
            for b = 0, n - 1 do
                if a ~= b then
                    graph:addEdge(label, a, b, label, 0, 1)
                    label = label + 1
                end
            end
        end
        local path = ns.Atlas.new():longestPath(graph, 0)
        local covered, total = ns.Atlas.coverage(graph, path)
        T.eq(total, n * (n - 1))
        T.eq(covered, total)
        T.ok(ns.Atlas.isContinuous(graph, path))
    end)
end
