-- StorageOS/tasks.lua
-- Coroutine-based cooperative task scheduler.
--
-- Tasks are functions that run as coroutines.  They must call
-- coroutine.yield() or os.sleep() periodically to yield control.
-- The scheduler runs all tasks in a round-robin loop via parallel.waitForAll.
--
-- Usage:
--   Tasks.add("myTask", function() while true do ... os.sleep(1) end end, priority)
--   Tasks.run()   -- blocks forever; returns only if all tasks exit

local Tasks = {}
Tasks.__index = Tasks

local Config = require("StorageOS.config")
local Logger = require("StorageOS.logger")
local Utils  = require("StorageOS.utils")

-- ── Internal state ────────────────────────────────────────────────────────────

-- List of task records: { id, name, fn, priority, status, co, addedAt }
local taskList = {}
local taskMap  = {}   -- id → record
local nextId   = 1

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function makeRecord(name, fn, priority)
    local id  = nextId
    nextId    = nextId + 1
    local rec = {
        id        = id,
        name      = name,
        fn        = fn,
        priority  = priority or Config.TASK_PRIORITY.NORMAL,
        status    = "pending",
        addedAt   = os.time(),
        co        = nil,
    }
    return rec
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Add a task.  `fn` is a function (may loop forever with yields).
--- Returns the task id.
function Tasks.add(name, fn, priority)
    local rec = makeRecord(name, fn, priority)
    taskList[#taskList + 1] = rec
    taskMap[rec.id]         = rec
    -- Sort by ascending priority number (lower = more important)
    table.sort(taskList, function(a, b) return a.priority < b.priority end)
    Logger.debug("Tasks.add: '%s' (id=%d, priority=%d)", name, rec.id, rec.priority)
    return rec.id
end

--- Remove a task by id (will be stopped at the next scheduler tick).
function Tasks.remove(id)
    taskMap[id] = nil
    for i, rec in ipairs(taskList) do
        if rec.id == id then
            table.remove(taskList, i)
            Logger.debug("Tasks.remove: id=%d", id)
            return true
        end
    end
    return false
end

--- Return a snapshot of all tasks for the GUI.
function Tasks.list()
    local out = {}
    for _, rec in ipairs(taskList) do
        out[#out + 1] = {
            id       = rec.id,
            name     = rec.name,
            status   = rec.status,
            priority = rec.priority,
            addedAt  = rec.addedAt,
        }
    end
    return out
end

--- Run all registered tasks cooperatively using parallel.waitForAll.
--- This function blocks until ALL tasks have exited.
--- Typically called once from core.lua after all tasks are registered.
function Tasks.run()
    if #taskList == 0 then
        Logger.warn("Tasks.run: no tasks registered")
        return
    end

    -- Build wrapper functions for parallel
    local fns = {}
    for _, rec in ipairs(taskList) do
        local r = rec   -- capture
        fns[#fns + 1] = function()
            r.status = "running"
            local ok, err = pcall(r.fn)
            if not ok then
                Logger.error("Task '%s' crashed: %s", r.name, tostring(err))
                r.status = "crashed"
            else
                r.status = "done"
            end
        end
    end

    parallel.waitForAll(table.unpack(fns))
end

--- One-shot "run a function as a short-lived task" using a coroutine.
--- Returns the coroutine; caller must resume it.
function Tasks.spawn(name, fn)
    local co = coroutine.create(function()
        local ok, err = pcall(fn)
        if not ok then
            Logger.error("Spawned task '%s' error: %s", name, tostring(err))
        end
    end)
    return co
end

return Tasks
