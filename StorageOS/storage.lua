-- StorageOS/storage.lua
-- Item tracking, priority-ordered storage and retrieval across all connected
-- inventory peripherals (chests, barrels, storage drawers, Create vaults, …).

local Storage = {}
Storage.__index = Storage

local Config  = require("StorageOS.config")
local Logger  = require("StorageOS.logger")
local Utils   = require("StorageOS.utils")
local Network = require("StorageOS.network")

-- In-memory item index: itemName -> { { periph, slot, count }, … }
-- Rebuilt on full scan, patched on transfer operations.
local itemIndex   = {}   -- map: item name → list of { info, slot, count }
local totalCounts = {}   -- map: item name → total count

-- ── Internal helpers ──────────────────────────────────────────────────────────

--- Clear and rebuild the item index from all storage peripherals.
local function rebuildIndex()
    itemIndex   = {}
    totalCounts = {}
    local storages = Network.getStorageSorted()
    for _, info in ipairs(storages) do
        local ok, items = pcall(info.periph.list, info.periph)
        if ok and items then
            for slot, stack in pairs(items) do
                local name = stack.name
                if not itemIndex[name] then itemIndex[name] = {} end
                itemIndex[name][#itemIndex[name] + 1] = {
                    info  = info,
                    slot  = slot,
                    count = stack.count,
                }
                totalCounts[name] = (totalCounts[name] or 0) + stack.count
            end
        end
    end
end

--- Add a delta to the total count of an item (can be negative).
local function patchCount(name, delta)
    totalCounts[name] = math.max(0, (totalCounts[name] or 0) + delta)
    if totalCounts[name] == 0 then
        totalCounts[name] = nil
        itemIndex[name]   = nil
    end
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Perform a full rescan of all storage peripherals.
function Storage.scan()
    rebuildIndex()
    Logger.debug("Storage.scan: indexed %d unique items", Utils.tableLen(itemIndex))
end

--- Return total count of an item across all storage.
function Storage.count(itemName)
    return totalCounts[itemName] or 0
end

--- Return a copy of the full item→count map.
function Storage.listAll()
    return Utils.shallowCopy(totalCounts)
end

--- Return item names sorted alphabetically.
function Storage.sortedItems()
    local names = {}
    for name in pairs(totalCounts) do names[#names + 1] = name end
    table.sort(names)
    return names
end

--- Push up to `amount` of `itemName` into a specific inventory peripheral.
--- `targetName` is the peripheral network name string.
--- `targetSlot` (optional) specifies a destination slot (for shaped crafting).
--- Returns the number of items actually transferred.
function Storage.pushTo(itemName, amount, targetName, targetSlot)
    local sources = itemIndex[itemName]
    if not sources or #sources == 0 then return 0 end
    local remaining = amount
    local transferred = 0
    for _, loc in ipairs(sources) do
        if remaining <= 0 then break end
        local toMove = math.min(remaining, loc.count, Config.MAX_TRANSFER)
        local ok, moved
        if targetSlot then
            ok, moved = pcall(
                loc.info.periph.pushItems,
                loc.info.periph,
                targetName,
                loc.slot,
                toMove,
                targetSlot
            )
        else
            ok, moved = pcall(
                loc.info.periph.pushItems,
                loc.info.periph,
                targetName,
                loc.slot,
                toMove
            )
        end
        if ok and moved and moved > 0 then
            transferred = transferred + moved
            remaining   = remaining - moved
            patchCount(itemName, -moved)
            loc.count = loc.count - moved
        end
    end
    return transferred
end

--- Pull items from a source peripheral into storage, respecting priority order.
--- `sourceName` is the network name of the source inventory.
--- `slot` is the slot in the source, `amount` is the max to pull.
--- Returns total items stored.
function Storage.pullFromSlot(sourceName, slot, itemName, amount)
    local storages = Network.getStorageSorted()
    local remaining = amount
    local stored    = 0

    for _, info in ipairs(storages) do
        if remaining <= 0 then break end
        -- Skip input/output/fuel chests as destinations
        if info.class ~= "input" and info.class ~= "output" and info.class ~= "fuel_store" then
            local toMove = math.min(remaining, Config.MAX_TRANSFER)
            local ok, moved = pcall(
                info.periph.pullItems,
                info.periph,
                sourceName,
                slot,
                toMove
            )
            if ok and moved and moved > 0 then
                stored    = stored + moved
                remaining = remaining - moved
                -- Patch index
                if itemName then
                    if not itemIndex[itemName] then itemIndex[itemName] = {} end
                    -- Find existing entry for this periph or add new
                    local found = false
                    for _, loc in ipairs(itemIndex[itemName]) do
                        if loc.info.name == info.name then
                            loc.count = loc.count + moved
                            found = true
                            break
                        end
                    end
                    if not found then
                        -- Determine the slot it landed in (approximate — full rescan will fix)
                        itemIndex[itemName][#itemIndex[itemName] + 1] = {
                            info  = info,
                            slot  = -1,  -- unknown until next scan
                            count = moved,
                        }
                    end
                    patchCount(itemName, moved)
                end
            end
        end
    end
    return stored
end

--- Ingest all items from a peripheral (e.g. an input chest) into storage.
--- Returns a map of { itemName → count } for items that were ingested.
function Storage.ingestFrom(sourceName)
    local sourceInfo = Network.getAll()[sourceName]
    if not sourceInfo then return {} end
    local ok, items = pcall(sourceInfo.periph.list, sourceInfo.periph)
    if not ok or not items then return {} end

    local ingested = {}
    for slot, stack in pairs(items) do
        local moved = Storage.pullFromSlot(sourceName, slot, stack.name, stack.count)
        if moved > 0 then
            ingested[stack.name] = (ingested[stack.name] or 0) + moved
        end
    end
    Logger.info("Storage.ingestFrom(%s): ingested %d item types", sourceName, Utils.tableLen(ingested))
    return ingested
end

--- Ingest from ALL input-labelled chests found on the network.
function Storage.ingestAllInputs()
    local inputs = Network.getByClass("input")
    local total  = {}
    for _, info in ipairs(inputs) do
        local ingested = Storage.ingestFrom(info.name)
        for name, count in pairs(ingested) do
            total[name] = (total[name] or 0) + count
        end
    end
    return total
end

--- Export `amount` of `itemName` from storage to a target peripheral.
--- `targetName` is the peripheral network name string.
--- Returns actual amount transferred.
function Storage.exportTo(itemName, amount, targetName)
    return Storage.pushTo(itemName, amount, targetName)
end

--- Export items to ALL output-labelled chests.
function Storage.exportToOutputs(itemName, amount)
    local outputs = Network.getByClass("output")
    if #outputs == 0 then
        Logger.warn("Storage.exportToOutputs: no output chests found")
        return 0
    end
    -- Distribute evenly across outputs
    local perOutput = math.ceil(amount / #outputs)
    local total = 0
    for _, info in ipairs(outputs) do
        local moved = Storage.exportTo(itemName, math.min(perOutput, amount - total), info.name)
        total = total + moved
    end
    return total
end

--- Check if storage has at least `amount` of every item in a requirements map.
--- `reqs` is a map of { itemName → count }.
--- Returns true if all requirements are met, or false + missing map.
function Storage.hasItems(reqs)
    local missing = {}
    for name, needed in pairs(reqs) do
        local have = Storage.count(name)
        if have < needed then
            missing[name] = needed - have
        end
    end
    if next(missing) then
        return false, missing
    end
    return true
end

--- Consume items from storage (reduce counts after crafting/processing).
--- `consumed` is a map of { itemName → count }.
function Storage.consume(consumed)
    for name, count in pairs(consumed) do
        patchCount(name, -count)
    end
end

return Storage
