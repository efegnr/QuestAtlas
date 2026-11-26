-- QuestAtlas - Core/EventBus.lua
-- Observer pattern: publishers do not know who listens. The tracker publishes
-- "TRACKER_UPDATED"; the UI subscribes to it. New listeners can be added
-- without touching the tracker (SOLID - O).
local _, ns = ...

local EventBus = ns.Class("EventBus")

function EventBus:init()
    self.listeners = {}
end

--- Subscribes `listener(...)` to `eventName`. Returns an unsubscribe function.
function EventBus:subscribe(eventName, listener)
    assert(type(listener) == "function", "EventBus:subscribe expects a function")
    local list = self.listeners[eventName]
    if not list then
        list = {}
        self.listeners[eventName] = list
    end
    list[#list + 1] = listener
    return function()
        ns.Util.removeValue(list, listener)
    end
end

function EventBus:publish(eventName, ...)
    local list = self.listeners[eventName]
    if not list then
        return 0
    end
    -- Copy first, so listeners may unsubscribe while being notified.
    local snapshot = ns.Util.shallowCopy(list)
    for i = 1, #snapshot do
        snapshot[i](...)
    end
    return #snapshot
end

function EventBus:listenerCount(eventName)
    local list = self.listeners[eventName]
    return list and #list or 0
end

ns.EventBus = EventBus
