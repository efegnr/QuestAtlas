-- QuestAtlas - Commands/CommandChainFactory.lua
-- Builds the Chain of Responsibility for /qa commands. Adding a command =
-- writing one handler class and adding it to ORDER; nothing else changes.
local _, ns = ...

local CommandChainFactory = {}

CommandChainFactory.ORDER = {
    "Help", "Toggle", "Show", "Hide", "Refresh", "Route", "Next",
    "Strategy", "Compare", "Available", "Plan", "Language", "Debug",
}

--- Returns head, handlers (handlers in chain order, without the Unknown handler).
function CommandChainFactory.build()
    local handlers = {}
    for i = 1, #CommandChainFactory.ORDER do
        handlers[i] = ns.Commands[CommandChainFactory.ORDER[i]].new()
    end
    local head = handlers[1]
    local tail = head
    for i = 2, #handlers do
        tail = tail:setNext(handlers[i])
    end
    tail:setNext(ns.Commands.Unknown.new())
    return head, handlers
end

ns.CommandChainFactory = CommandChainFactory
