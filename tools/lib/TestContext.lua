-- tools/lib/TestContext.lua
-- Shared helpers for the tests: paths, the WoW mock, and small factories.
return function(root)
    local ctx = {}
    ctx.root = root
    ctx.addonDir = root .. "/QuestAtlas"
    ctx.Mock = dofile(root .. "/tools/mock/WowMock.lua")

    --- Fresh simulated game with the add-on loaded (ADDON_LOADED fired).
    --- Returns the add-on's private namespace.
    function ctx.loadAddon(options)
        ctx.Mock.reset(options)
        return (ctx.Mock.loadAddon(ctx.addonDir))
    end

    --- Fresh game, add-on loaded and the player logged in (UI built, first route).
    function ctx.startGame(options)
        local ns = ctx.loadAddon(options)
        ctx.Mock.login()
        ctx.Mock.advanceTime(1) -- let debounced refreshes run
        return ns
    end

    --- Port of Util.toGraph from the Java ATLAS: reads a KISS2 FSM file.
    --- "<state> -- <input> / <output> -> <next state>" ; edges from state 0 are start edges.
    function ctx.kissGraph(ns, fileName)
        local graph = ns.Graph.new()
        local label = 0
        for line in io.lines(root .. "/tests/fixtures/fsm/" .. fileName) do
            local state, input, output, nextState =
                line:match("^(%d*)%s%-%-%s(%d*)%s/%s(%d*)%s%->%s(%d*)")
            if state then
                state, input, output, nextState = tonumber(state), tonumber(input), tonumber(output), tonumber(nextState)
                graph:addEdge(label, state, nextState, input, output, 1)
                if state == 0 then
                    graph:addStart(label)
                end
                label = label + 1
            end
        end
        return graph
    end

    --- Edge labels reachable from `startLabel` (following edge -> edges of its destination).
    function ctx.reachableEdges(graph, startLabel)
        local seen, stack = { [startLabel] = true }, { startLabel }
        while #stack > 0 do
            local label = table.remove(stack)
            local outgoing = graph:edgeLabels(graph:getEdge(label).destination)
            for i = 1, #outgoing do
                if not seen[outgoing[i]] then
                    seen[outgoing[i]] = true
                    stack[#stack + 1] = outgoing[i]
                end
            end
        end
        return seen
    end

    --- Builds a Quest for routing tests. spec = { id, status, giver={x,y}, turnIn={x,y}, objectives={{x,y,done}} }
    function ctx.makeQuest(ns, spec)
        local map = spec.map or 1429
        local objectives = {}
        for i, o in ipairs(spec.objectives or {}) do
            objectives[i] = ns.QuestObjective.new(i, "objective " .. i, o.done,
                o.x and ns.Location.new(o.map or map, o.x, o.y, "obj" .. i) or nil)
        end
        return ns.Quest.new({
            id = spec.id,
            title = spec.title or ("Quest " .. spec.id),
            level = spec.level or 1,
            status = spec.status or ns.QuestStatus.IN_PROGRESS,
            objectives = objectives,
            giver = spec.giver and ns.Location.new(spec.giver.map or map, spec.giver.x, spec.giver.y, "giver") or nil,
            turnIn = spec.turnIn and ns.Location.new(spec.turnIn.map or map, spec.turnIn.x, spec.turnIn.y, "npc") or nil,
            known = true,
        })
    end

    --- Distance calculator using the static map table (no game API needed).
    function ctx.staticDistance(ns)
        return ns.DistanceCalculator.new(ns.StaticMapGeometry.new(ns.MapData))
    end

    --- Deterministic pseudo random numbers (Park-Miller; exact in doubles,
    --- so every Lua version produces the same sequence).
    function ctx.random(seed)
        local state = seed
        return function(low, high)
            state = (state * 16807) % 2147483647
            return low + (state % (high - low + 1))
        end
    end

    return ctx
end
