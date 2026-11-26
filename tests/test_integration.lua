-- tests/test_integration.lua - the whole add-on inside the simulated client
return function(T, ctx)
    T.suite("Add-on in the simulated client")

    local Mock = ctx.Mock

    local function ns_contains(list, value)
        for _, v in ipairs(list) do
            if v == value then return true end
        end
        return false
    end

    T.test(".toc: every listed file exists and every Lua file is listed", function()
        local metadata, files = Mock.parseToc(ctx.addonDir .. "/QuestAtlas.toc")
        T.eq(metadata.SavedVariables, "QuestAtlasDB")
        local interfaces = {}
        for number in metadata.Interface:gmatch("%d+") do
            interfaces[#interfaces + 1] = tonumber(number)
        end
        T.ok(ns_contains(interfaces, 16001), "Interface list contains WoW: Forever (16001)")
        T.ok(ns_contains(interfaces, 120105), "Interface list contains retail 12.1.5 (120105)")
        T.ok(metadata.Interface:match("^%d+[%d, ]*$") ~= nil, "Interface line is a comma separated list")
        local listed = {}
        for _, file in ipairs(files) do
            local handle = io.open(ctx.addonDir .. "/" .. file, "r")
            T.ok(handle ~= nil, "listed file exists: " .. file)
            if handle then handle:close() end
            listed[file] = true
        end
        T.eq(files[#files], "Bootstrap.lua", "composition root is loaded last")
        -- Every .lua file under the add-on folder must be in the .toc.
        local command = package.config:sub(1, 1) == "\\"
            and ('dir /s /b "' .. ctx.addonDir:gsub("/", "\\") .. '\\*.lua"')
            or ('find "' .. ctx.addonDir .. '" -name "*.lua"')
        local pipe = io.popen(command)
        if pipe then
            local count = 0
            for path in pipe:lines() do
                local relative = path:gsub("\\", "/"):match("QuestAtlas/QuestAtlas/(.+)$")
                if relative then
                    count = count + 1
                    T.ok(listed[relative], "file is listed in the .toc: " .. relative)
                end
            end
            pipe:close()
            T.ok(count == 0 or count == #files, "file count " .. count .. " vs toc " .. #files)
        end
    end)

    T.test("loading the add-on creates no unexpected globals", function()
        Mock.reset()
        local before = Mock.globalsSnapshot()
        Mock.loadAddon(ctx.addonDir)
        Mock.login()
        Mock.advanceTime(5)
        T.deepEq(Mock.newGlobalsSince(before),
            { "QuestAtlas", "QuestAtlasDB", "QuestAtlasFrame", "SLASH_QUESTATLAS1", "SLASH_QUESTATLAS2" })
    end)

    T.test("login: window is built and shows an empty quest log", function()
        ctx.startGame()
        local frame = _G.QuestAtlasFrame
        T.ok(frame and frame:IsShown(), "QuestAtlasFrame shown")
        local box = Mock.renderFrame(frame)
        T.contains(box, "QuestAtlas")
        T.contains(box, "Görevler (0)")
        T.contains(box, "Rotaya eklenecek görev yok.")
        T.contains(box, "[X] [Yenile] [Strateji]")
    end)

    T.test("playing through Northshire: the route follows the quest log", function()
        ctx.startGame({ level = 1 })
        Mock.movePlayer(1429, 48.0, 43.5)
        Mock.acceptQuest(783) -- A Threat Within: talk to McBride
        Mock.advanceTime(1)
        local box = Mock.renderFrame("QuestAtlasFrame")
        T.contains(box, "[1] A Threat Within  (teslime hazır)")
        T.contains(box, "1. Teslim et: A Threat Within @ Marshal McBride (48.9, 41.6)")

        Mock.turnInQuest(783)
        Mock.setPlayerLevel(2)
        Mock.acceptQuest(7)  -- Kobold Camp Cleanup
        Mock.acceptQuest(33) -- Wolves Across the Border
        Mock.advanceTime(1)
        box = Mock.renderFrame("QuestAtlasFrame")
        T.contains(box, "Görevler (2)")
        T.contains(box, "Kobold Camp Cleanup  0/1 hedef")
        local route = _G.QuestAtlas:getRoute()
        T.eq(#route.taskOrder, 2)
        T.eq(#route.steps, 4, "2 objectives + 2 turn-ins")

        Mock.completeObjectives(7)
        Mock.advanceTime(1)
        T.contains(Mock.renderFrame("QuestAtlasFrame"), "Kobold Camp Cleanup  (teslime hazır)")
        route = _G.QuestAtlas:getRoute()
        T.eq(#route.steps, 3, "Kobold Camp Cleanup now only needs its turn-in")

        Mock.turnInQuest(7)
        Mock.advanceTime(1)
        T.contains(Mock.renderFrame("QuestAtlasFrame"), "Görevler (1)")
        T.notContains(Mock.renderFrame("QuestAtlasFrame"), "Kobold Camp Cleanup")
    end)

    T.test("quests without location data are listed but not routed", function()
        ctx.startGame({ level = 5 })
        Mock.acceptQuest(90001)
        Mock.acceptQuest(783)
        Mock.advanceTime(1)
        local box = Mock.renderFrame("QuestAtlasFrame")
        T.contains(box, "A Mysterious Note")
        T.contains(box, "Konum verisi yok: A Mysterious Note")
        T.eq(#_G.QuestAtlas:getRoute().steps, 1)
    end)

    T.test("planned quests appear with an Accept step and leave the plan once accepted", function()
        ctx.startGame({ level = 3 })
        Mock.setQuestCompleted(783)
        Mock.slash("/qa plan add 7")
        local route = _G.QuestAtlas:getRoute()
        T.eq(route.steps[1].kind, "ACCEPT")
        T.contains(Mock.renderFrame("QuestAtlasFrame"), "Kobold Camp Cleanup  (planlandı)")
        Mock.acceptQuest(7)
        Mock.advanceTime(1)
        T.eq(#_G.QuestAtlas:getPlannedQuests(), 0, "accepted -> removed from the plan")
        T.eq(_G.QuestAtlas:getRoute().steps[1].kind, "OBJECTIVE")
    end)

    T.test("moving re-plans the route (ticker), small moves do not", function()
        ctx.startGame({ level = 5 })
        Mock.acceptQuest(783)
        Mock.advanceTime(1)
        local first = _G.QuestAtlas:getRoute()
        Mock.movePlayer(1429, 49.0, 43.5) -- about 35 yards
        Mock.advanceTime(4)
        T.ok(_G.QuestAtlas:getRoute() == first, "same route object: no re-plan")
        Mock.movePlayer(1429, 42.0, 66.0) -- Goldshire
        Mock.advanceTime(4)
        local second = _G.QuestAtlas:getRoute()
        T.ok(second ~= first, "re-planned after moving")
        T.ok(second.steps[1].legDistance > 500, "McBride is far from Goldshire now")
    end)

    T.test("inside an instance there is no route", function()
        ctx.startGame()
        Mock.acceptQuest(783)
        Mock.setInInstance(true)
        Mock.advanceTime(1)
        T.contains(Mock.renderFrame("QuestAtlasFrame"), "konumun bilinmiyor")
    end)

    T.test("QUEST_LOG_UPDATE bursts are merged into one refresh", function()
        local ns = ctx.startGame()
        local count = 0
        local tracker = ns.app.tracker
        local original = tracker.refresh
        tracker.refresh = function(self, reason)
            count = count + 1
            return original(self, reason)
        end
        for _ = 1, 10 do
            Mock.fireEvent("QUEST_LOG_UPDATE")
        end
        Mock.advanceTime(1)
        T.eq(count, 1)
    end)

    T.test("buttons: Refresh re-plans, Strategy cycles, X hides", function()
        ctx.startGame()
        local frame = _G.QuestAtlasFrame
        Mock.clickButton(frame, "Strateji")
        T.eq(_G.QuestAtlas:getStrategyName(), "nearest")
        T.contains(Mock.renderFrame(frame), "Strateji: nearest")
        Mock.clickButton(frame, "Yenile")
        Mock.clickButton(frame, "X")
        T.eq(frame:IsShown(), false)
    end)

    T.test("/reload keeps strategy, language, plan, window position and visibility", function()
        ctx.startGame({ level = 2 })
        Mock.slash("/qa strategy bruteforce")
        Mock.slash("/qa lang en")
        Mock.slash("/qa plan add 33")
        Mock.dragFrame(_G.QuestAtlasFrame, 300, 700)
        Mock.slash("/qa hide")
        Mock.reloadUI()
        Mock.advanceTime(1)
        T.eq(_G.QuestAtlas:getStrategyName(), "bruteforce")
        T.eq(_G.QuestAtlas:getLanguage(), "enUS")
        T.eq(_G.QuestAtlas:getPlannedQuests()[1].id, 33)
        T.eq(_G.QuestAtlasFrame:IsShown(), false)
        local point, _, relativePoint, x, y = _G.QuestAtlasFrame:GetPoint(1)
        T.deepEq({ point, relativePoint, x, y }, { "TOPLEFT", "BOTTOMLEFT", 300, 700 })
        Mock.slash("/qa show")
        T.contains(Mock.renderFrame("QuestAtlasFrame"), "Quests (1)")
    end)

    T.test("an invalid saved strategy falls back to atlas", function()
        Mock.reset()
        Mock.world().savedVariables.QuestAtlasDB = { strategy = "removed-in-v2" }
        Mock.loadAddon(ctx.addonDir)
        Mock.login()
        T.eq(_G.QuestAtlas:getStrategyName(), "atlas")
    end)

    T.test("works with the newer C_QuestLog API as well", function()
        ctx.startGame({ apiFlavor = "modern", level = 2 })
        Mock.acceptQuest(33)
        Mock.setObjectiveProgress(33, 1, 3)
        Mock.advanceTime(1)
        local box = Mock.renderFrame("QuestAtlasFrame")
        T.contains(box, "Wolves Across the Border  0/1 hedef")
        T.contains(box, "Hedef: Wolves Across the Border @ Tough Wolf Meat")
    end)

    T.test("long routes are cut in the window and printed fully by /qa route", function()
        ctx.startGame({ level = 10 })
        for _, id in ipairs({ 62, 47, 60, 76, 88, 46, 83, 106 }) do
            Mock.acceptQuest(id)
        end
        Mock.advanceTime(1)
        local route = _G.QuestAtlas:getRoute()
        T.ok(#route.steps > 10, "more steps than lines")
        T.contains(Mock.renderFrame("QuestAtlasFrame"), "adım daha - /qa route")
        Mock.clearChat()
        Mock.slash("/qa route")
        T.contains(Mock.chatText(), tostring(#route.steps) .. ". ")
    end)
end
