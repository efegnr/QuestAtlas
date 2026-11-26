-- QuestAtlas - Commands/Commands.lua
-- Concrete command handlers. Each one does exactly one thing (SOLID - S) and
-- talks only to the facade it receives as `context`.
local _, ns = ...

local CommandHandler = ns.CommandHandler
local Util = ns.Util

local function define(className, names, helpKey, execute)
    local cls = ns.Class(className, CommandHandler)
    function cls:init()
        CommandHandler.init(self, names, helpKey)
    end
    cls.execute = execute
    ns[className] = cls
    return cls
end

local Commands = {}

Commands.Help = define("HelpCommand", { "help", "?", "" }, "HELP_HELP", function(_, context)
    context:printLine(context:t("HELP_HEADER"))
    local lines = context:getHelpLines()
    for i = 1, #lines do
        context:printLine(lines[i])
    end
end)

Commands.Toggle = define("ToggleCommand", { "toggle", "ui" }, "HELP_TOGGLE", function(_, context)
    context:toggleUI()
end)

Commands.Show = define("ShowCommand", { "show" }, "HELP_SHOW", function(_, context)
    context:showUI()
end)

Commands.Hide = define("HideCommand", { "hide" }, "HELP_HIDE", function(_, context)
    context:hideUI()
end)

Commands.Refresh = define("RefreshCommand", { "refresh", "r" }, "HELP_REFRESH", function(_, context)
    context:refresh("COMMAND")
    context:print(context:t("MSG_REFRESHED"))
end)

Commands.Route = define("RouteCommand", { "route" }, "HELP_ROUTE", function(_, context)
    local route = context:getRoute()
    if route:isEmpty() then
        context:print(context:describeEmptyRoute(route))
        return
    end
    context:print(context:describeRouteHeader(route))
    for i = 1, #route.steps do
        context:printLine(context:describeStep(route.steps[i], i))
    end
end)

Commands.Next = define("NextCommand", { "next", "way" }, "HELP_NEXT", function(_, context)
    local step, waypointSet = context:goToNextStep()
    if not step then
        context:print(context:describeEmptyRoute(context:getRoute()))
        return
    end
    context:print(context:describeStep(step, 1))
    context:printLine(waypointSet and context:t("MSG_WAYPOINT_SET") or context:t("MSG_WAYPOINT_UNSUPPORTED"))
end)

Commands.Strategy = define("StrategyCommand", { "strategy", "s" }, "HELP_STRATEGY", function(_, context, args)
    local name = Util.trim(args):lower()
    local ok, errorKey
    if name == "" then
        ok, errorKey = context:cycleStrategy()
    else
        ok, errorKey = context:setStrategy(name)
    end
    if ok then
        context:print(context:t("MSG_STRATEGY", context:getStrategyName()))
    else
        context:print(context:t(errorKey, name) .. " " .. table.concat(context:getStrategyNames(), ", "))
    end
end)

Commands.Compare = define("CompareCommand", { "compare" }, "HELP_COMPARE", function(_, context)
    local results = context:compareStrategies()
    if #results == 0 then
        context:print(context:t("ROUTE_NO_POSITION"))
        return
    end
    context:print(context:t("MSG_COMPARE_HEADER"))
    for i = 1, #results do
        local r = results[i]
        context:printLine(context:t("MSG_COMPARE_LINE", r.name, Util.formatYards(r.distance), context:t("YARDS"),
            r.steps, string.format("%.2f", r.timeMs)))
    end
end)

Commands.Available = define("AvailableCommand", { "available", "av" }, "HELP_AVAILABLE", function(_, context)
    local list = context:getAvailableQuests()
    if #list == 0 then
        context:print(context:t("MSG_NONE_AVAILABLE"))
        return
    end
    context:print(context:t("MSG_AVAILABLE_HEADER"))
    for i = 1, math.min(#list, 10) do
        local q = list[i]
        local distance = q.distance < math.huge and (Util.formatYards(q.distance) .. " " .. context:t("YARDS")) or "?"
        context:printLine(string.format("  #%d [%d] %s - %s (%s)%s", q.id, q.level, q.title, q.giverName, distance,
            q.planned and (" " .. context:t("STATUS_PLANNED")) or ""))
    end
end)

Commands.Plan = define("PlanCommand", { "plan", "p" }, "HELP_PLAN", function(_, context, args)
    local action, rest = Util.splitCommand(args)
    if tonumber(action) then -- "/qa plan 7" = "/qa plan add 7"
        action, rest = "add", action
    end
    if action == "list" or action == "" then
        local planned = context:getPlannedQuests()
        if #planned == 0 then
            context:print(context:t("MSG_PLAN_EMPTY"))
        else
            context:print(context:t("MSG_PLAN_HEADER"))
            for i = 1, #planned do
                context:printLine(string.format("  #%d %s", planned[i].id, planned[i].title))
            end
        end
        return
    elseif action == "clear" then
        context:clearPlanned()
        context:print(context:t("MSG_PLAN_CLEARED"))
        return
    end

    local questID = tonumber(Util.trim(rest))
    if (action ~= "add" and action ~= "remove") or not questID then
        context:print(context:t("HELP_PLAN"))
        return
    end
    local ok, errorKey
    if action == "add" then
        ok, errorKey = context:planQuest(questID)
    else
        ok, errorKey = context:unplanQuest(questID)
    end
    if ok then
        context:print(context:t(action == "add" and "MSG_PLAN_ADDED" or "MSG_PLAN_REMOVED", questID))
    else
        context:print(context:t(errorKey, questID))
    end
end)

Commands.Language = define("LanguageCommand", { "lang", "language" }, "HELP_LANG", function(_, context, args)
    local code = ({ tr = "trTR", trtr = "trTR", en = "enUS", enus = "enUS" })[Util.trim(args):lower()]
    if not code then
        context:print(context:t("HELP_LANG"))
        return
    end
    context:setLanguage(code)
    context:print(context:t("MSG_LANGUAGE"))
end)

Commands.Debug = define("DebugCommand", { "debug", "diag" }, "HELP_DEBUG", function(_, context)
    context:print(context:t("DEBUG_HEADER"))
    local lines = context:getDiagnostics()
    for i = 1, #lines do
        context:printLine("  " .. lines[i])
    end
end)

-- Last link of the chain: accepts everything the others rejected.
local UnknownCommand = ns.Class("UnknownCommand", CommandHandler)

function UnknownCommand:init()
    CommandHandler.init(self, {}, nil)
end

function UnknownCommand:canHandle()
    return true
end

function UnknownCommand:execute(context)
    context:print(context:t("MSG_UNKNOWN_COMMAND"))
end

ns.UnknownCommand = UnknownCommand
Commands.Unknown = UnknownCommand

ns.Commands = Commands
