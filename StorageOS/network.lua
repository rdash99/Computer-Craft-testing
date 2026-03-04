-- StorageOS/network.lua
-- Peripheral auto-discovery, classification, and live change detection.
--
-- Every peripheral on the wired/wireless modem network is scanned.
-- Each one is assigned a "class" (chest, barrel, storage_drawer, furnace, …)
-- based on the priority table in config.lua.
-- Changes are detected via os.pullEvent("peripheral") / "peripheral_detach".

local Network = {}
Network.__index = Network

local Config = require("StorageOS.config")
local Logger = require("StorageOS.logger")
local Utils  = require("StorageOS.utils")

-- Internal registry: name -> { name, type, class, priority, periph, label }
local registry = {}

-- Callbacks registered by other modules
local onAttach  = {}  -- list of function(info)
local onDetach  = {}  -- list of function(info)

-- ── Classification ────────────────────────────────────────────────────────────

--- Match a peripheral type string against Config tables and return class+priority.
local function classify(pType)
    -- Storage peripherals
    for _, entry in ipairs(Config.STORAGE_PRIORITY_TABLE) do
        if Utils.startsWith(pType, entry.match) then
            return entry.class, entry.priority
        end
    end
    -- Processing peripherals
    for _, entry in ipairs(Config.PROCESSING_PATTERNS) do
        if Utils.startsWith(pType, entry.match) then
            return entry.class, 0
        end
    end
    -- Crafting peripherals
    for _, entry in ipairs(Config.CRAFTING_PATTERNS) do
        if Utils.startsWith(pType, entry.match) then
            return entry.class, 0
        end
    end
    return "unknown", 0
end

--- Try to read a label from an inventory peripheral (anvil-named chest, etc.)
local function getLabel(periph)
    -- Some mods expose a getLabel() method
    if periph and periph.getLabel then
        local ok, lbl = pcall(periph.getLabel, periph)
        if ok and lbl then return lbl:lower() end
    end
    return nil
end

--- Build an info record for a peripheral name.
local function buildInfo(name)
    local ok, pType = pcall(peripheral.getType, name)
    if not ok or not pType then return nil end
    local ok2, periph = pcall(peripheral.wrap, name)
    if not ok2 or not periph then return nil end

    local class, priority = classify(pType)
    local label           = getLabel(periph)

    -- Override class for labelled input/output chests
    if label then
        if Utils.contains(Config.INPUT_LABELS, label) then
            class    = "input"
            priority = 200  -- always available as input source
        elseif Utils.contains(Config.OUTPUT_LABELS, label) then
            class    = "output"
            priority = 199
        elseif Utils.contains(Config.FUEL_LABELS, label) then
            class    = "fuel_store"
            priority = 198
        end
    end

    return {
        name     = name,
        pType    = pType,
        class    = class,
        priority = priority,
        periph   = periph,
        label    = label,
    }
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Register a callback invoked when a new peripheral attaches.
function Network.onAttach(fn)
    onAttach[#onAttach + 1] = fn
end

--- Register a callback invoked when a peripheral detaches.
function Network.onDetach(fn)
    onDetach[#onDetach + 1] = fn
end

--- Perform a full scan of all peripherals and rebuild the registry.
function Network.scan()
    local names = peripheral.getNames()
    local seen  = {}

    for _, name in ipairs(names) do
        seen[name] = true
        if not registry[name] then
            local info = buildInfo(name)
            if info then
                registry[name] = info
                Logger.info("Network: attached %s (%s / %s)", name, info.pType, info.class)
                for _, cb in ipairs(onAttach) do
                    pcall(cb, info)
                end
            end
        end
    end

    -- Detect detachments
    for name, info in pairs(registry) do
        if not seen[name] then
            Logger.info("Network: detached %s (%s)", name, info.class)
            for _, cb in ipairs(onDetach) do
                pcall(cb, info)
            end
            registry[name] = nil
        end
    end
end

--- Handle a single "peripheral" or "peripheral_detach" event.
function Network.handleEvent(event, name)
    if event == "peripheral" then
        local info = buildInfo(name)
        if info then
            registry[name] = info
            Logger.info("Network: hot-attached %s (%s)", name, info.class)
            for _, cb in ipairs(onAttach) do
                pcall(cb, info)
            end
        end
    elseif event == "peripheral_detach" then
        local info = registry[name]
        if info then
            Logger.info("Network: hot-detached %s", name)
            for _, cb in ipairs(onDetach) do
                pcall(cb, info)
            end
            registry[name] = nil
        end
    end
end

--- Return all registered peripherals (read-only copy of registry).
function Network.getAll()
    return Utils.shallowCopy(registry)
end

--- Return all peripherals of a given class (or list of classes).
function Network.getByClass(...)
    local wanted = {}
    for _, c in ipairs({...}) do wanted[c] = true end
    local out = {}
    for _, info in pairs(registry) do
        if wanted[info.class] then
            out[#out + 1] = info
        end
    end
    return out
end

--- Return all storage peripherals sorted by descending priority.
function Network.getStorageSorted()
    local storage = {}
    for _, info in pairs(registry) do
        local isStorage = info.priority > 0 and (
            info.class == "storage_drawer" or
            info.class == "chest"          or
            info.class == "barrel"         or
            info.class == "input"          or
            info.class == "output"         or
            info.class == "fuel_store"
        )
        if isStorage then
            storage[#storage + 1] = info
        end
    end
    table.sort(storage, function(a, b) return a.priority > b.priority end)
    return storage
end

--- Return the total number of registered peripherals.
function Network.count()
    return Utils.tableLen(registry)
end

--- Return a summary string for the GUI status bar.
function Network.summary()
    local counts = {}
    for _, info in pairs(registry) do
        counts[info.class] = (counts[info.class] or 0) + 1
    end
    local parts = {}
    for class, n in pairs(counts) do
        parts[#parts + 1] = n .. " " .. class
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end

return Network
