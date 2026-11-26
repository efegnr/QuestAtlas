-- tests/test_routing.lua - tasks, quest graph, strategies, planner
return function(T, ctx)
    T.suite("Routing")

    local function names(list)
        local result = {}
        for i, task in ipairs(list) do result[i] = task.id end
        return result
    end

    --- Checks the invariants every route must satisfy, for any strategy.
    local function assertValidRoute(ns, route, tasks, start, calc, label)
        -- 1. every task exactly once
        T.eq(#route.taskOrder, #tasks, label .. ": all tasks scheduled")
        local seen = {}
        for _, task in ipairs(route.taskOrder) do
            T.ok(not seen[task], label .. ": task scheduled twice " .. task.id)
            seen[task] = true
        end
        -- 2. each quest: accept before objectives before turn-in
        local position = {}
        for i, step in ipairs(route.steps) do
            for _, quest in ipairs(step.quests) do
                position[quest.id] = position[quest.id] or {}
                position[quest.id][step.kind] = position[quest.id][step.kind] or i
                position[quest.id].last = i
            end
        end
        for id, p in pairs(position) do
            T.ok(p.TURN_IN ~= nil, label .. ": quest " .. id .. " is turned in")
            T.eq(p.last, p.TURN_IN, label .. ": quest " .. id .. " turn-in is its last step")
            if p.ACCEPT then
                T.ok(p.ACCEPT <= (p.OBJECTIVE or p.TURN_IN), label .. ": accept first")
            end
        end
        -- 3. distances add up
        local expected = ns.RouteAssembler.orderDistance(start, route.taskOrder, calc)
        T.near(route.totalDistance, expected, 1e-6, label .. ": total distance")
        local sum = 0
        for _, step in ipairs(route.steps) do
            sum = sum + step.legDistance
            T.near(step.cumulativeDistance, sum, 1e-6, label .. ": cumulative distance")
        end
    end

    local function randomTasks(ns, rnd, count)
        local quests = {}
        for i = 1, count do
            local kind = rnd(1, 3)
            local spec = { id = i, turnIn = { x = rnd(10, 90), y = rnd(10, 90) } }
            if kind == 1 then
                spec.status = ns.QuestStatus.READY
            elseif kind == 2 then
                spec.objectives = { { x = rnd(10, 90), y = rnd(10, 90) } }
            else
                spec.status = ns.QuestStatus.PLANNED
                spec.giver = { x = rnd(10, 90), y = rnd(10, 90) }
                spec.objectives = { { x = rnd(10, 90), y = rnd(10, 90) }, { x = rnd(10, 90), y = rnd(10, 90) } }
            end
            quests[i] = ctx.makeQuest(ns, spec)
        end
        return ns.RouteTaskBuilder.new():build(quests)
    end

    T.test("RouteTaskBuilder: waypoints per status", function()
        local ns = ctx.loadAddon()
        local builder = ns.RouteTaskBuilder.new()
        local ready = ctx.makeQuest(ns, { id = 1, status = ns.QuestStatus.READY, turnIn = { x = 10, y = 10 } })
        local progress = ctx.makeQuest(ns, { id = 2, turnIn = { x = 10, y = 10 },
            objectives = { { x = 20, y = 20, done = true }, { x = 30, y = 30 }, { x = 40, y = 40 } } })
        local planned = ctx.makeQuest(ns, { id = 3, status = ns.QuestStatus.PLANNED, giver = { x = 5, y = 5 },
            turnIn = { x = 10, y = 10 }, objectives = { { x = 30, y = 30 } } })
        local tasks = builder:build({ ready, progress, planned })
        T.eq(#tasks, 3)
        T.deepEq(ns.Util.map(tasks[1].waypoints, function(w) return w.kind end), { "TURN_IN" })
        T.deepEq(ns.Util.map(tasks[2].waypoints, function(w) return w.kind end), { "OBJECTIVE", "OBJECTIVE", "TURN_IN" },
            "finished objectives are skipped")
        T.deepEq(ns.Util.map(tasks[3].waypoints, function(w) return w.kind end), { "ACCEPT", "OBJECTIVE", "TURN_IN" })
    end)

    T.test("RouteTaskBuilder: identical itineraries are merged, unknown ones reported", function()
        local ns = ctx.loadAddon()
        local a = ctx.makeQuest(ns, { id = 1, status = ns.QuestStatus.READY, turnIn = { x = 10, y = 10 } })
        local b = ctx.makeQuest(ns, { id = 2, status = ns.QuestStatus.READY, turnIn = { x = 10, y = 10 } })
        local noTurnIn = ctx.makeQuest(ns, { id = 3, objectives = { { x = 1, y = 1 } } })
        local noObjectiveData = ctx.makeQuest(ns, { id = 4, turnIn = { x = 10, y = 10 }, objectives = { {} } })
        local failed = ctx.makeQuest(ns, { id = 5, status = ns.QuestStatus.FAILED, turnIn = { x = 10, y = 10 } })
        local readyNoTurnIn = ctx.makeQuest(ns, { id = 6, status = ns.QuestStatus.READY })
        local tasks, unroutable = ns.RouteTaskBuilder.new():build({ a, b, noTurnIn, noObjectiveData, failed, readyNoTurnIn })
        T.eq(#tasks, 2)
        T.eq(tasks[1].id, "Q1+2")
        T.eq(#tasks[1].quests, 2)
        T.eq(#tasks[1].waypoints[1].quests, 2)
        T.eq(tasks[2].id, "Q3")
        T.deepEq(ns.Util.map(tasks[2].waypoints, function(w) return w.kind end), { "OBJECTIVE" },
            "turn-in unknown (only the game marker of the objective): objective-only task")
        T.deepEq(ns.Util.map(unroutable, function(q) return q.id end), { 4, 5, 6 })
    end)

    T.test("QuestGraphBuilder: start edge, one required edge per task, complete travel graph", function()
        local ns = ctx.loadAddon()
        local calc = ctx.staticDistance(ns)
        local tasks = ns.RouteTaskBuilder.new():build({
            ctx.makeQuest(ns, { id = 1, status = ns.QuestStatus.READY, turnIn = { x = 10, y = 10 } }),
            ctx.makeQuest(ns, { id = 2, turnIn = { x = 30, y = 30 }, objectives = { { x = 20, y = 20 } } }),
        })
        local built = ns.QuestGraphBuilder.new(calc):build(ns.Location.new(1429, 50, 50), tasks)
        local graph = built.graph
        -- nodes: player, (10,10), (20,20), (30,30)
        T.eq(#graph:getNodes(), 4)
        local start = graph:getEdge(built.startLabel)
        T.ok(start:isSelfLoop() and not start.required, "start = optional self-loop")
        T.eq(graph:getRequiredEdgeCount(), 2)
        local selfLoop = graph:getEdge(1)
        T.ok(selfLoop:isSelfLoop() and selfLoop.required and selfLoop.weight == 0, "turn-in only task = self-loop")
        -- travel: 4 nodes, no edges into the player node: 4*3 - 3 = 9
        T.eq(graph:getEdgeCount(), 1 + 2 + 9)
        T.near(graph:getEdge(2).weight, calc:distance(ns.Location.new(1429, 20, 20), ns.Location.new(1429, 30, 30)), 1e-9)
    end)

    T.test("all strategies produce valid routes on 40 random problems (interchangeable)", function()
        local ns = ctx.loadAddon()
        local calc = ctx.staticDistance(ns)
        local factory = ns.RouteStrategyFactory.new(calc)
        local rnd = ctx.random(42)
        for round = 1, 40 do
            local tasks = randomTasks(ns, rnd, rnd(1, 7))
            local start = ns.Location.new(1429, rnd(0, 100), rnd(0, 100))
            for _, name in ipairs(factory:getNames()) do
                local route = factory:create(name):plan(start, tasks)
                T.eq(route.strategyName, name)
                assertValidRoute(ns, route, tasks, start, calc, name .. " round " .. round)
            end
        end
    end)

    T.test("bruteforce is optimal; ATLAS is close to optimal and never worse than its walk", function()
        local ns = ctx.loadAddon()
        local calc = ctx.staticDistance(ns)
        local atlas = ns.AtlasRouteStrategy.new(calc)
        local nearest = ns.NearestNeighborRouteStrategy.new(calc)
        local brute = ns.BruteForceRouteStrategy.new(calc)
        local rnd = ctx.random(7)
        local sumAtlas, sumNearest, sumBest, rounds = 0, 0, 0, 60
        for _ = 1, rounds do
            local tasks = randomTasks(ns, rnd, rnd(3, 7))
            local start = ns.Location.new(1429, rnd(0, 100), rnd(0, 100))
            local best = brute:plan(start, tasks).totalDistance
            local a = atlas:plan(start, tasks).totalDistance
            local n = nearest:plan(start, tasks).totalDistance
            T.ok(best <= a + 1e-6 and best <= n + 1e-6, "brute force is a lower bound")
            -- The task order is read from ATLAS's walk; walking it directly
            -- can only be shorter than (or equal to) the walk itself.
            local walk, built = atlas:computeWalk(start, tasks)
            local walkLength = 0
            for i = 1, #walk do walkLength = walkLength + built.graph:getEdge(walk[i]).weight end
            T.ok(a <= walkLength + 1e-6, "route <= ATLAS walk length")
            sumAtlas, sumNearest, sumBest = sumAtlas + a, sumNearest + n, sumBest + best
        end
        io.write(string.format("         avg distance over %d problems: optimal %.0f | atlas %.0f (+%.1f%%) | nearest %.0f (+%.1f%%)\n",
            rounds, sumBest / rounds, sumAtlas / rounds, 100 * (sumAtlas / sumBest - 1),
            sumNearest / rounds, 100 * (sumNearest / sumBest - 1)))
        T.ok(sumAtlas <= sumBest * 1.10, "ATLAS within 10% of optimal on average")
    end)

    T.test("ATLAS walk covers every quest edge", function()
        local ns = ctx.loadAddon()
        local calc = ctx.staticDistance(ns)
        local atlas = ns.AtlasRouteStrategy.new(calc)
        local rnd = ctx.random(99)
        for _ = 1, 30 do
            local tasks = randomTasks(ns, rnd, rnd(1, 10))
            local walk, built = atlas:computeWalk(ns.Location.new(1429, rnd(0, 100), rnd(0, 100)), tasks)
            local covered, total = ns.Atlas.coverage(built.graph, walk)
            T.eq(covered, total)
            T.eq(total, #tasks)
            T.ok(ns.Atlas.isContinuous(built.graph, walk), "walk is connected")
            T.eq(walk[1], built.startLabel, "walk starts at the player")
        end
    end)

    T.test("BruteForce delegates above its limit; strategies handle zero tasks", function()
        local ns = ctx.loadAddon()
        local calc = ctx.staticDistance(ns)
        local rnd = ctx.random(3)
        local tasks = randomTasks(ns, rnd, 10)
        local route = ns.BruteForceRouteStrategy.new(calc, 8):plan(ns.Location.new(1429, 50, 50), tasks)
        T.eq(route.strategyName, "bruteforce>nearest")
        T.eq(#route.taskOrder, 10)
        for _, name in ipairs({ "atlas", "nearest", "bruteforce" }) do
            local empty = ns.RouteStrategyFactory.new(calc):create(name):plan(ns.Location.new(1429, 1, 1), {})
            T.ok(empty:isEmpty(), name .. " with no tasks")
        end
    end)

    T.test("RouteStrategyFactory: register new strategies, cycle, reject unknown", function()
        local ns = ctx.loadAddon()
        local factory = ns.RouteStrategyFactory.new(ctx.staticDistance(ns))
        T.deepEq(factory:getNames(), { "atlas", "nearest", "bruteforce" })
        T.eq(factory:nextName("atlas"), "nearest")
        T.eq(factory:nextName("bruteforce"), "atlas")
        T.raises(function() factory:create("dijkstra") end, "unknown strategy")
        local Reverse = ns.Class("ReverseStrategy")
        function Reverse:getName() return "reverse" end
        function Reverse:plan(start, tasks) return ns.Route.empty("reverse") end
        factory:register("reverse", function() return Reverse.new() end)
        T.eq(factory:create("reverse"):getName(), "reverse")
        factory:register("broken", function() return {} end)
        T.raises(function() factory:create("broken") end, "IRouteStrategy")
    end)

    T.test("RoutePlanner: empty reasons, unroutable list, compare", function()
        local ns = ctx.loadAddon()
        local calc = ctx.staticDistance(ns)
        local planner = ns.RoutePlanner.new(ns.RouteTaskBuilder.new(), ns.RouteStrategyFactory.new(calc))
        local quest = ctx.makeQuest(ns, { id = 1, status = ns.QuestStatus.READY, turnIn = { x = 10, y = 10 } })
        local lost = ctx.makeQuest(ns, { id = 2, objectives = { {} } }) -- no location at all
        T.eq(planner:plan(nil, { quest }, "atlas").reason, "NO_POSITION")
        T.eq(planner:plan(ns.Location.new(1429, 1, 1), { lost }, "atlas").reason, "NO_TASKS")
        local route = planner:plan(ns.Location.new(1429, 1, 1), { quest, lost }, "atlas")
        T.eq(#route.steps, 1)
        T.eq(route.unroutable[1].id, 2)
        local results = planner:compare(ns.Location.new(1429, 1, 1), { quest })
        T.eq(#results, 3)
        for _, r in ipairs(results) do
            T.near(r.distance, results[1].distance, 1e-6, "one task: same distance for " .. r.name)
        end
    end)

    T.test("RouteAssembler merges consecutive steps at the same place", function()
        local ns = ctx.loadAddon()
        local calc = ctx.staticDistance(ns)
        local tasks = ns.RouteTaskBuilder.new():build({
            ctx.makeQuest(ns, { id = 1, turnIn = { x = 10, y = 10 }, objectives = { { x = 40, y = 40 } } }),
            ctx.makeQuest(ns, { id = 2, status = ns.QuestStatus.READY, turnIn = { x = 10, y = 10 } }),
        })
        local route = ns.RouteAssembler.fromTaskOrder("test", ns.Location.new(1429, 40, 40), tasks, calc)
        T.eq(#route.steps, 2, "objective, then ONE turn-in step for both quests")
        T.eq(#route.steps[2].quests, 2)
        T.deepEq(names(route.taskOrder), { "Q1", "Q2" })
    end)
end
