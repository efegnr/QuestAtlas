-- tests/test_core.lua - class system, interfaces, event bus, utilities, locales
return function(T, ctx)
    T.suite("Core")

    T.test("Class: constructor, methods and inheritance", function()
        local ns = ctx.loadAddon()
        local Animal = ns.Class("Animal")
        function Animal:init(name) self.name = name end
        function Animal:speak() return self.name .. " makes a sound" end
        local Dog = ns.Class("Dog", Animal)
        function Dog:speak() return self.name .. " barks" end

        local a, d = Animal.new("cat"), Dog.new("rex")
        T.eq(a:speak(), "cat makes a sound")
        T.eq(d:speak(), "rex barks")
        T.ok(ns.isInstanceOf(d, Dog) and ns.isInstanceOf(d, Animal), "dog is a Dog and an Animal")
        T.ok(not ns.isInstanceOf(a, Dog), "animal is not a Dog")
        T.ok(getmetatable(Dog.new("x")) == Dog, "subclass new() builds subclass instances")
    end)

    T.test("abstract methods raise a clear error", function()
        local ns = ctx.loadAddon()
        local handler = ns.CommandHandler.new({ "x" })
        T.raises(function() handler:execute() end, "abstract")
    end)

    T.test("Interface: assert names the missing methods", function()
        local ns = ctx.loadAddon()
        local I = ns.Interface("IThing", { "a", "b" })
        T.ok(I:isImplementedBy({ a = function() end, b = function() end }))
        T.raises(function() I:assert({ a = function() end }, "test") end, "missing: b")
    end)

    T.test("every strategy / policy / handler implements its interface", function()
        local ns = ctx.loadAddon()
        local calc = ctx.staticDistance(ns)
        local factory = ns.RouteStrategyFactory.new(calc)
        for _, name in ipairs(factory:getNames()) do
            T.ok(ns.Interfaces.IRouteStrategy:isImplementedBy(factory:create(name)), name)
        end
        T.ok(ns.Interfaces.ICostPolicy:isImplementedBy(ns.UnitCostPolicy.new()))
        T.ok(ns.Interfaces.ICostPolicy:isImplementedBy(ns.DistanceAwareCostPolicy.new()))
        local _, handlers = ns.CommandChainFactory.build()
        for _, h in ipairs(handlers) do
            T.ok(ns.Interfaces.ICommandHandler:isImplementedBy(h), h:getPrimaryName())
        end
        T.ok(ns.Interfaces.IMapGeometry:isImplementedBy(ns.StaticMapGeometry.new()))
        T.ok(ns.Interfaces.IDistanceCalculator:isImplementedBy(calc))
    end)

    T.test("EventBus: publish, unsubscribe", function()
        local ns = ctx.loadAddon()
        local bus = ns.EventBus.new()
        local received = {}
        local unsubscribe = bus:subscribe("E", function(value) received[#received + 1] = value end)
        bus:publish("E", 1)
        unsubscribe()
        bus:publish("E", 2)
        T.deepEq(received, { 1 })
        T.eq(bus:listenerCount("E"), 0)
    end)

    T.test("Util.splitCommand", function()
        local ns = ctx.loadAddon()
        local c, rest = ns.Util.splitCommand("  PLAN add 7 ")
        T.eq(c, "plan")
        T.eq(rest, "add 7")
        c, rest = ns.Util.splitCommand("")
        T.eq(c, "")
        T.eq(rest, "")
    end)

    T.test("Locale: fallback to English and formatting", function()
        local ns = ctx.loadAddon()
        local locale = ns.LocaleClass.new()
        locale:register("enUS", { A = "a %d", B = "b" })
        locale:register("trTR", { A = "tr %d" })
        locale:setLanguage("trTR")
        T.eq(locale:get("A", 3), "tr 3")
        T.eq(locale:get("B"), "b", "falls back to English")
        T.eq(locale:get("MISSING"), "MISSING", "unknown key shows the key")
        T.ok(not locale:setLanguage("deDE"), "unknown language rejected")
    end)

    T.test("Locale: both languages have the same keys and format specifiers", function()
        local ns = ctx.loadAddon()
        local en, tr = ns.Locale.tables.enUS, ns.Locale.tables.trTR
        local function specifiers(s)
            local list = {}
            for spec in s:gmatch("%%[%-%d%.]*[sdif]") do list[#list + 1] = spec end
            return table.concat(list, " ")
        end
        for key, text in pairs(en) do
            T.ok(tr[key] ~= nil, "trTR is missing " .. key)
            T.eq(specifiers(tr[key]), specifiers(text), "format specifiers of " .. key)
        end
        for key in pairs(tr) do
            T.ok(en[key] ~= nil, "enUS is missing " .. key)
        end
    end)

    T.test("Locale: no text contains '|' (WoW reads it as an escape: |r, |n, |c...)", function()
        local ns = ctx.loadAddon()
        for code, strings in pairs(ns.Locale.tables) do
            for key, text in pairs(strings) do
                T.ok(not text:find("|", 1, true), code .. "." .. key .. " contains '|'")
            end
        end
    end)

    T.test("Locale: every key used in the code exists", function()
        local ns = ctx.loadAddon()
        local _, files = ctx.Mock.parseToc(ctx.addonDir .. "/QuestAtlas.toc")
        local prefixes = { "HELP_", "MSG_", "ERR_", "STATUS_", "STEP_", "ROUTE_", "BTN_", "DEBUG_" }
        local singles = { TITLE = true, SUBTITLE = true, YARDS = true, QUESTS_HEADER = true, NO_QUESTS = true,
            MORE_STEPS = true, UNROUTABLE = true, FAR_AWAY = true, DISTANCE_UNKNOWN = true }
        local checked = 0
        for _, file in ipairs(files) do
            if not file:find("^Locales/") then
                local handle = assert(io.open(ctx.addonDir .. "/" .. file, "r"))
                local source = handle:read("*a")
                handle:close()
                for key in source:gmatch('"([A-Z][A-Z_]+)"') do
                    local isKey = singles[key]
                    for _, p in ipairs(prefixes) do
                        isKey = isKey or key:sub(1, #p) == p
                    end
                    if isKey and key ~= "ROUTE_" then
                        checked = checked + 1
                        T.ok(ns.Locale:has("enUS", key), file .. ": unknown locale key " .. key)
                        T.ok(ns.Locale:has("trTR", key), file .. ": missing Turkish text for " .. key)
                    end
                end
            end
        end
        T.ok(checked > 40, "scanned locale keys: " .. checked)
    end)
end
