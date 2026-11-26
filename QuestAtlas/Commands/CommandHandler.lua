-- QuestAtlas - Commands/CommandHandler.lua
-- Chain of Responsibility: every slash command is a separate handler object.
-- A handler either handles the command or passes it to the next one.
--   /qa route  ->  Help? no -> Toggle? no -> Route? YES -> execute
--
-- Template Method: handle() is fixed; subclasses only fill in execute().
local _, ns = ...

local CommandHandler = ns.Class("CommandHandler")

--- names: command words this handler accepts, e.g. { "route", "r" }
--- helpKey: locale key of the one-line help text ("" = not listed)
function CommandHandler:init(names, helpKey)
    self.names = names or {}
    self.helpKey = helpKey
    self.nextHandler = nil
end

--- Links the next handler; returns it so chains can be built fluently.
function CommandHandler:setNext(handler)
    ns.Interfaces.ICommandHandler:assert(handler, "CommandHandler:setNext")
    self.nextHandler = handler
    return handler
end

function CommandHandler:canHandle(command)
    return ns.Util.contains(self.names, command)
end

--- Template method. context: the facade; returns true when handled.
function CommandHandler:handle(context, command, args)
    if self:canHandle(command) then
        self:execute(context, args)
        return true
    end
    if self.nextHandler then
        return self.nextHandler:handle(context, command, args)
    end
    return false
end

CommandHandler.execute = ns.abstract("CommandHandler", "execute")

function CommandHandler:getHelpKey()
    return self.helpKey
end

function CommandHandler:getPrimaryName()
    return self.names[1]
end

ns.CommandHandler = CommandHandler
