-- tools/demo.lua
-- Oyun olmadan eklentiyi "oynatır": WoW mock'u başlatır, QuestAtlas'ı .toc
-- dosyasıyla yükler, görev alır / teslim eder, komut yazar ve her adımda
-- takip penceresini terminale çizer.
--   luajit tools/demo.lua           WoW: Forever / Classic senaryosu (Elwynn Forest)
--   luajit tools/demo.lua retail    normal WoW (12.1.5) senaryosu (Exile's Reach)
local scriptDir = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
local ROOT = scriptDir .. "/.."
local Mock = dofile(ROOT .. "/tools/mock/WowMock.lua")

local NL = "\n"
local function say(text)
    io.write(NL .. "=== " .. text .. " ===" .. NL)
end
local function showWindow()
    io.write(Mock.renderFrame("QuestAtlasFrame", 92) .. NL)
end
local function flushChat()
    for _, line in ipairs(Mock.chatLines()) do
        io.write("   [sohbet] " .. Mock.stripColors(line) .. NL)
    end
    Mock.clearChat()
end
local function slash(line)
    io.write("> " .. line .. NL)
    Mock.slash(line)
    flushChat()
end
local function wait()
    Mock.advanceTime(1) -- debounce of QUEST_LOG_UPDATE
end

if arg and arg[1] == "retail" then
    -- Retail: the add-on's database does not know these quests; the route
    -- comes from the quest markers the game draws on the map.
    Mock.reset({ apiFlavor = "retail" })
    say("R1) Retail istemci (12.1.5), Exile's Reach: eklenti yüklenir")
    Mock.loadAddon(ROOT .. "/QuestAtlas")
    Mock.login()
    wait()
    slash("/qa debug")

    say("R2) Altı görev alındı (eklentinin veritabanında YOK, konumlar oyunun harita işaretlerinden)")
    for _, id in ipairs({ 900001, 900002, 900003, 900004, 900005, 900006 }) do
        Mock.acceptQuest(id)
    end
    wait()
    showWindow()
    slash("/qa debug")

    say("R3) İlerleme (2/5) rotayı yeniden hesaplatmaz; hedefler bitince teslim NPC'si rotaya girer")
    Mock.setObjectiveProgress(900002, 1, 2)
    wait()
    Mock.completeObjectives(900001)
    wait()
    showWindow()
    slash("/qa next")
    return
end

Mock.reset({ level = 1, waypoints = true })

say("1) Oyuna giriş: istemci QuestAtlas.toc'taki dosyaları sırayla yükler")
Mock.loadAddon(ROOT .. "/QuestAtlas")
Mock.login()
wait()
showWindow()

say("2) Northshire: Deputy Willem'den 'A Threat Within' alındı")
Mock.movePlayer(1429, 48.2, 43.2)
Mock.acceptQuest(783)
wait()
showWindow()

say("3) Teslim edildi, seviye 2 oldu, dört görev daha alındı")
Mock.movePlayer(1429, 48.9, 41.9)
Mock.turnInQuest(783)
Mock.setPlayerLevel(2)
for _, id in ipairs({ 7, 33, 18, 3904 }) do
    Mock.acceptQuest(id)
end
wait()
showWindow()

say("4) Tüm rota ve algoritmaların karşılaştırması")
slash("/qa route")
slash("/qa compare")

say("5) Kobold'lar temizlendi: rota kendini günceller")
Mock.movePlayer(1429, 47.4, 34.6)
Mock.setObjectiveProgress(7, 1, 6)
Mock.completeObjectives(7)
Mock.advanceTime(4) -- konum kontrolü (3 sn'de bir) + yeniden planlama
showWindow()
slash("/qa next")

say("6) Teslim et, sonra yeni bir görevi plana ekle")
Mock.movePlayer(1429, 48.9, 41.9)
Mock.turnInQuest(7)
wait()
slash("/qa available")
slash("/qa plan add 15")
showWindow()

say("7) Strateji değiştir, dili İngilizce yap")
slash("/qa strategy nearest")
slash("/qa lang en")
showWindow()

say("8) /reload: ayarlar (strateji, dil, plan) SavedVariables ile korunur")
Mock.reloadUI()
wait()
showWindow()
slash("/qa lang tr")
slash("/qa strategy atlas")

say("9) Zindan içinde konum bilinmez, rota çizilmez")
Mock.setInInstance(true)
wait()
showWindow()
