-- QuestAtlas - Core/Class.lua
-- Minimal class system for Lua 5.1 (the Lua version used by the WoW client).
-- Lua has no built-in classes, so classes are emulated with metatables:
--   local Dog = ns.Class("Dog", Animal)   -- Dog inherits from Animal
--   function Dog:init(name) ... end       -- constructor
--   local d = Dog.new("Rex")
local _, ns = ...

local function Class(name, parent)
    local cls = {}
    cls.__index = cls
    cls.__name = name
    cls.super = parent

    if parent then
        setmetatable(cls, { __index = parent })
    end

    -- Every class gets its own `new`, so a subclass never builds parent instances.
    function cls.new(...)
        local instance = setmetatable({}, cls)
        if instance.init then
            instance:init(...)
        end
        return instance
    end

    return cls
end

--- Returns true when `obj` is an instance of `cls` or of one of its subclasses.
local function isInstanceOf(obj, cls)
    if type(obj) ~= "table" then
        return false
    end
    local current = getmetatable(obj)
    while current do
        if current == cls then
            return true
        end
        current = current.super
    end
    return false
end

--- Marks a method as abstract: calling it raises a clear error.
local function abstract(className, methodName)
    return function()
        error(className .. ":" .. methodName .. "() is abstract and must be overridden", 2)
    end
end

ns.Class = Class
ns.isInstanceOf = isInstanceOf
ns.abstract = abstract
