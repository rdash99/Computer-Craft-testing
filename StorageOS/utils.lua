-- StorageOS/utils.lua
-- Shared utility helpers used across all StorageOS modules.

local Utils = {}

-- ── String helpers ────────────────────────────────────────────────────────────

--- Returns true if `str` starts with `prefix`.
function Utils.startsWith(str, prefix)
    return type(str) == "string" and str:sub(1, #prefix) == prefix
end

--- Returns true if `str` ends with `suffix`.
function Utils.endsWith(str, suffix)
    return type(str) == "string" and str:sub(-#suffix) == suffix
end

--- Trim leading/trailing whitespace.
function Utils.trim(str)
    return str:match("^%s*(.-)%s*$")
end

--- Split a string by a separator pattern, returns table of parts.
function Utils.split(str, sep)
    local parts = {}
    local pattern = "([^" .. sep .. "]+)"
    for part in str:gmatch(pattern) do
        parts[#parts + 1] = part
    end
    return parts
end

--- Pad or truncate a string to a fixed width.
function Utils.pad(str, width, align)
    str = tostring(str or "")
    if #str >= width then
        return str:sub(1, width)
    end
    local padding = string.rep(" ", width - #str)
    if align == "right" then
        return padding .. str
    end
    return str .. padding
end

--- Truncate a string with an ellipsis if it exceeds `maxLen`.
function Utils.ellipsis(str, maxLen)
    str = tostring(str or "")
    if #str <= maxLen then return str end
    return str:sub(1, maxLen - 1) .. "\xc2\xa6"  -- "…" as fallback "¦"
end

--- Format a number with thousand separators (e.g. 1,234,567).
function Utils.formatNumber(n)
    local s = tostring(math.floor(n or 0))
    local result = ""
    local len = #s
    for i = 1, len do
        if i > 1 and (len - i + 1) % 3 == 0 then
            result = result .. ","
        end
        result = result .. s:sub(i, i)
    end
    return result
end

-- ── Table helpers ─────────────────────────────────────────────────────────────

--- Shallow-copy a table.
function Utils.shallowCopy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

--- Deep-copy a table (handles nested tables, not metatables).
function Utils.deepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k, v in pairs(orig) do
            copy[Utils.deepCopy(k)] = Utils.deepCopy(v)
        end
        setmetatable(copy, getmetatable(orig))
    else
        copy = orig
    end
    return copy
end

--- Check if a value exists in an array-like table.
function Utils.contains(tbl, value)
    for _, v in ipairs(tbl) do
        if v == value then return true end
    end
    return false
end

--- Returns the keys of a table as a sorted array.
function Utils.sortedKeys(tbl)
    local keys = {}
    for k in pairs(tbl) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return keys
end

--- Merge table `b` into `a` (shallow, overwrites existing keys).
function Utils.merge(a, b)
    for k, v in pairs(b) do a[k] = v end
    return a
end

--- Count entries in a table (works for both array and map tables).
function Utils.tableLen(tbl)
    local n = 0
    for _ in pairs(tbl) do n = n + 1 end
    return n
end

-- ── Math helpers ──────────────────────────────────────────────────────────────

function Utils.clamp(val, min, max)
    if val < min then return min end
    if val > max then return max end
    return val
end

function Utils.round(val)
    return math.floor(val + 0.5)
end

-- ── File helpers ──────────────────────────────────────────────────────────────

--- Ensure a directory exists, creating parents if needed.
function Utils.ensureDir(path)
    if not fs.exists(path) then
        fs.makeDir(path)
    end
end

--- Save a Lua table to a file using textutils serialisation.
function Utils.saveTable(path, tbl)
    Utils.ensureDir(fs.getDir(path))
    local f = fs.open(path, "w")
    if not f then return false, "Cannot open " .. path end
    f.write(textutils.serialize(tbl))
    f.close()
    return true
end

--- Load a Lua table from a serialised file.
function Utils.loadTable(path)
    if not fs.exists(path) then return nil, "File not found: " .. path end
    local f = fs.open(path, "r")
    if not f then return nil, "Cannot open " .. path end
    local data = f.readAll()
    f.close()
    local ok, result = pcall(textutils.unserialize, data)
    if not ok then return nil, "Parse error in " .. path end
    return result
end

-- ── Time helpers ──────────────────────────────────────────────────────────────

--- Return a human-readable elapsed-time string (e.g. "2m 34s").
function Utils.elapsed(seconds)
    seconds = math.floor(seconds or 0)
    if seconds < 60 then
        return seconds .. "s"
    elseif seconds < 3600 then
        return math.floor(seconds / 60) .. "m " .. (seconds % 60) .. "s"
    else
        local h = math.floor(seconds / 3600)
        local m = math.floor((seconds % 3600) / 60)
        return h .. "h " .. m .. "m"
    end
end

--- Returns the current wall-clock time as a formatted string "HH:MM:SS".
function Utils.timeStr()
    local t = os.time()
    local h = math.floor(t)
    local m = math.floor((t - h) * 60)
    local s = math.floor(((t - h) * 60 - m) * 60)
    return string.format("%02d:%02d:%02d", h % 24, m, s)
end

-- ── Peripheral helpers ────────────────────────────────────────────────────────

--- Safely call a peripheral method, returning nil on error.
function Utils.pcallPeripheral(periph, method, ...)
    if not periph then return nil end
    local ok, result = pcall(periph[method], periph, ...)
    if ok then return result end
    return nil
end

--- Return the total item count stored in an inventory peripheral.
function Utils.inventoryCount(periph)
    if not periph then return 0 end
    local items = Utils.pcallPeripheral(periph, "list")
    if not items then return 0 end
    local total = 0
    for _, stack in pairs(items) do
        total = total + (stack.count or 0)
    end
    return total
end

--- Return free slot count in an inventory peripheral.
function Utils.freeSlots(periph)
    if not periph then return 0 end
    local size  = Utils.pcallPeripheral(periph, "size") or 0
    local items = Utils.pcallPeripheral(periph, "list") or {}
    local used  = 0
    for _ in pairs(items) do used = used + 1 end
    return size - used
end

return Utils
