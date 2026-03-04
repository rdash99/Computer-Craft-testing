-- StorageOS/logger.lua
-- Simple file-backed logger with level filtering and in-memory ring buffer.

local Logger = {}
Logger.__index = Logger

local Config = require("StorageOS.config")
local Utils  = require("StorageOS.utils")

-- Log levels
Logger.LEVELS = {
    DEBUG   = 1,
    INFO    = 2,
    WARNING = 3,
    ERROR   = 4,
    FATAL   = 5,
}
local LEVEL_NAMES = { [1]="DEBUG", [2]="INFO", [3]="WARN", [4]="ERROR", [5]="FATAL" }

-- In-memory ring buffer (last N log lines for GUI display)
local RING_SIZE = 200
local ring      = {}
local ringHead  = 1
local ringCount = 0

-- Minimum level that gets written to disk / displayed
local minLevel = Logger.LEVELS.INFO

-- File handle (opened lazily)
local logFile = nil

local function openLogFile()
    if logFile then return end
    Utils.ensureDir(Config.DATA_DIR)
    logFile = fs.open(Config.LOG_FILE, "a")
end

local function writeRing(entry)
    ring[ringHead] = entry
    ringHead = (ringHead % RING_SIZE) + 1
    if ringCount < RING_SIZE then ringCount = ringCount + 1 end
end

--- Write a log entry at the given level.
local function log(level, msg, ...)
    if level < minLevel then return end
    if select("#", ...) > 0 then
        msg = string.format(tostring(msg), ...)
    end
    local entry = string.format("[%s][%s] %s", Utils.timeStr(), LEVEL_NAMES[level] or "?", tostring(msg))
    writeRing(entry)
    openLogFile()
    if logFile then
        logFile.writeLine(entry)
        logFile.flush()
    end
end

--- Set the minimum log level (Logger.LEVELS.DEBUG, INFO, …)
function Logger.setLevel(level)
    minLevel = level
end

--- Return up to `n` recent log lines (newest last).
function Logger.getRecent(n)
    n = math.min(n or 50, ringCount)
    local out = {}
    -- Walk ring from oldest to newest
    local start = ringCount < RING_SIZE and 1 or ringHead
    for i = 0, ringCount - 1 do
        local idx = ((start - 1 + i) % RING_SIZE) + 1
        out[#out + 1] = ring[idx]
    end
    -- Return last n
    if #out > n then
        local trimmed = {}
        for i = #out - n + 1, #out do trimmed[#trimmed + 1] = out[i] end
        return trimmed
    end
    return out
end

--- Clear the in-memory ring buffer.
function Logger.clear()
    ring      = {}
    ringHead  = 1
    ringCount = 0
end

-- Convenience wrappers
function Logger.debug(msg, ...)   log(Logger.LEVELS.DEBUG,   msg, ...) end
function Logger.info(msg, ...)    log(Logger.LEVELS.INFO,    msg, ...) end
function Logger.warn(msg, ...)    log(Logger.LEVELS.WARNING, msg, ...) end
function Logger.error(msg, ...)   log(Logger.LEVELS.ERROR,   msg, ...) end
function Logger.fatal(msg, ...)   log(Logger.LEVELS.FATAL,   msg, ...) end

return Logger
