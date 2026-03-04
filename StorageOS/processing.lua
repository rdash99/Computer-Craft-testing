-- StorageOS/processing.lua
-- Manages smelting (furnaces, smokers, blast furnaces) and Create mod
-- processing machines (basins, presses, mixers).
--
-- Each processor is tracked as a "processor" record:
--   {
--     info       – Network info record
--     class      – "furnace" | "smoker" | "blast_furnace" | "create_*"
--     inputSlot  – slot number for input items (furnace = 1)
--     fuelSlot   – slot number for fuel (furnace = 2, nil for Create)
--     outputSlot – slot number for output (furnace = 3)
--     recipe     – currently-assigned recipe or nil
--     busy       – true while processing
--   }

local Processing = {}
Processing.__index = Processing

local Config        = require("StorageOS.config")
local Logger        = require("StorageOS.logger")
local Utils         = require("StorageOS.utils")
local Network       = require("StorageOS.network")
local Storage       = require("StorageOS.storage")
local RecipeManager = require("StorageOS.recipes.manager")

-- ── Constants ─────────────────────────────────────────────────────────────────
local FURNACE_INPUT  = 1
local FURNACE_FUEL   = 2
local FURNACE_OUTPUT = 3

-- ── Internal state ────────────────────────────────────────────────────────────
local processors = {}     -- list of processor records
local jobQueue   = {}     -- { recipe, amount, callback }
local jobLock    = false

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function isFurnaceClass(class)
    return class == "furnace" or class == "smoker" or class == "blast_furnace"
end

local function isCreateClass(class)
    return class == "create_basin" or class == "create_press" or
           class == "create_mixer" or class == "create_compacting"
end

--- Determine the recipe type(s) a processor can handle.
local function acceptedTypes(class)
    if class == "furnace"       then return { "smelt" } end
    if class == "smoker"        then return { "smoke", "smelt" } end
    if class == "blast_furnace" then return { "blast", "smelt" } end
    if class == "create_basin"  then return { "create_mixing", "create_compacting" } end
    if class == "create_press"  then return { "create_pressing" } end
    if class == "create_mixer"  then return { "create_mixing" } end
    return {}
end

--- Returns true if `processor` can handle the given recipe type.
local function canHandle(processor, recipeType)
    for _, t in ipairs(acceptedTypes(processor.class)) do
        if t == recipeType then return true end
    end
    return false
end

--- Find a free (not busy) processor that can handle a recipe type.
local function findFree(recipeType)
    for _, p in ipairs(processors) do
        if not p.busy and canHandle(p, recipeType) then
            return p
        end
    end
    return nil
end

--- Check how many items are currently in a furnace's output slot.
local function furnaceOutputCount(p)
    local ok, items = pcall(p.info.periph.list, p.info.periph)
    if not ok or not items then return 0 end
    local stack = items[FURNACE_OUTPUT]
    return stack and stack.count or 0
end

--- Check if a furnace still has fuel / is burning.
local function furnaceHasFuel(p)
    local ok, data = pcall(p.info.periph.getFuelLevel, p.info.periph)
    return ok and (data or 0) > 0
end

--- Load fuel from storage into a furnace's fuel slot.
local function refuelFurnace(p)
    -- Check if it already has fuel
    if furnaceHasFuel(p) then return true end

    for _, fuelItem in ipairs(Config.FUEL_ITEMS) do
        local have = Storage.count(fuelItem)
        if have > 0 then
            local moved = Storage.pushTo(fuelItem, 1, p.info.name)
            -- Push puts item into the first available slot; we need slot 2
            -- For furnaces via pushItems we can specify a toSlot argument.
            if moved > 0 then
                Logger.debug("Processing.refuelFurnace(%s): pushed %s", p.info.name, fuelItem)
                return true
            end
        end
    end
    Logger.warn("Processing.refuelFurnace(%s): no fuel available", p.info.name)
    return false
end

--- Push input items to a furnace's input slot (slot 1).
local function loadFurnaceInput(p, itemName, count)
    local moved = Storage.pushTo(itemName, count, p.info.name)
    return moved
end

--- Collect output from a furnace's output slot into storage.
local function collectFurnaceOutput(p)
    local ok, items = pcall(p.info.periph.list, p.info.periph)
    if not ok or not items then return 0 end
    local stack = items[FURNACE_OUTPUT]
    if not stack or stack.count == 0 then return 0 end

    -- Pull from furnace output slot into storage
    local storages = Network.getStorageSorted()
    local total    = 0
    for _, info in ipairs(storages) do
        if info.class ~= "input" and info.class ~= "output" and info.class ~= "fuel_store" then
            local ok2, moved = pcall(
                info.periph.pullItems,
                info.periph,
                p.info.name,
                FURNACE_OUTPUT,
                stack.count - total
            )
            if ok2 and moved and moved > 0 then
                total = total + moved
                if total >= stack.count then break end
            end
        end
    end
    if total > 0 then
        Logger.debug("Processing.collectFurnaceOutput(%s): collected %d", p.info.name, total)
    end
    return total
end

-- ── Peripheral attach/detach ─────────────────────────────────────────────────

--- Called when a new peripheral attaches; add it to processors if applicable.
function Processing.onAttach(info)
    if isFurnaceClass(info.class) or isCreateClass(info.class) then
        -- Check not already registered
        for _, p in ipairs(processors) do
            if p.info.name == info.name then return end
        end
        processors[#processors + 1] = {
            info       = info,
            class      = info.class,
            inputSlot  = FURNACE_INPUT,
            fuelSlot   = isFurnaceClass(info.class) and FURNACE_FUEL or nil,
            outputSlot = FURNACE_OUTPUT,
            recipe     = nil,
            busy       = false,
        }
        Logger.info("Processing: registered %s (%s)", info.name, info.class)
    end
end

--- Called when a peripheral detaches; remove from processors.
function Processing.onDetach(info)
    for i, p in ipairs(processors) do
        if p.info.name == info.name then
            table.remove(processors, i)
            Logger.info("Processing: unregistered %s", info.name)
            return
        end
    end
end

--- Rebuild processor list from current network state.
function Processing.scan()
    processors = {}
    for _, info in ipairs(Network.getByClass("furnace", "smoker", "blast_furnace",
                                              "create_basin", "create_press", "create_mixer")) do
        Processing.onAttach(info)
    end
    Logger.info("Processing.scan: found %d processors", #processors)
end

-- ── Core processing logic ─────────────────────────────────────────────────────

--- Assign a job to a free processor and start it.
--- Returns true if a processor was found and started.
local function startJob(job)
    local recipe = RecipeManager.bestFor(job.itemName)
    if not recipe then
        Logger.warn("Processing.startJob: no recipe for %s", job.itemName)
        return false
    end
    local p = findFree(recipe.type)
    if not p then
        Logger.debug("Processing.startJob: no free %s processor", recipe.type)
        return false
    end

    -- Check ingredient availability
    local ingredients = RecipeManager.ingredients(recipe)
    local ok2, missing = Storage.hasItems(ingredients)
    if not ok2 then
        Logger.debug("Processing.startJob: missing ingredients for %s", job.itemName)
        return false
    end

    -- Mark busy and assign recipe
    p.busy   = true
    p.recipe = recipe
    p.job    = job

    Logger.info("Processing: starting %s × %d on %s (%s)",
        job.itemName, job.amount, p.info.name, p.class)

    if isFurnaceClass(p.class) then
        -- Furnace processing: load input and fuel
        local timesNeeded = math.ceil(job.amount / (recipe.count or 1))
        for item, perCraft in pairs(ingredients) do
            loadFurnaceInput(p, item, perCraft * timesNeeded)
        end
        refuelFurnace(p)
    elseif isCreateClass(p.class) then
        -- Create machine: push items to its inventory
        for item, count in pairs(ingredients) do
            Storage.pushTo(item, count * job.amount, p.info.name)
        end
    end

    return true
end

--- Tick function: check all busy processors and collect finished output.
function Processing.tick()
    for _, p in ipairs(processors) do
        if p.busy and p.recipe then
            local collected = 0
            if isFurnaceClass(p.class) then
                collected = collectFurnaceOutput(p)
            elseif isCreateClass(p.class) then
                -- Collect any items that have been deposited to output
                collected = Storage.ingestFrom(p.info.name) and 1 or 0
            end

            if collected > 0 then
                -- Check if the job is complete
                local job = p.job
                if job then
                    job.produced = (job.produced or 0) + collected
                    if job.produced >= job.amount then
                        Logger.info("Processing: completed %s × %d", job.itemName, job.amount)
                        if job.callbackFn then
                            pcall(job.callbackFn, true, job.produced)
                        end
                        p.busy   = false
                        p.recipe = nil
                        p.job    = nil
                        Storage.scan()
                    end
                end
            end
        end
    end
end

--- Queue a processing job.
function Processing.queue(itemName, amount, callbackFn)
    local job = {
        itemName   = itemName,
        amount     = amount or 1,
        callbackFn = callbackFn,
        produced   = 0,
        status     = "queued",
    }
    jobQueue[#jobQueue + 1] = job
    Logger.info("Processing.queue: queued %d × %s", amount, itemName)
    return job
end

--- Attempt to dispatch pending jobs to free processors.
function Processing.dispatch()
    if jobLock then return end
    jobLock = true
    local remaining = {}
    for _, job in ipairs(jobQueue) do
        if not startJob(job) then
            remaining[#remaining + 1] = job
        end
    end
    jobQueue = remaining
    jobLock  = false
end

--- Return status of all processors (for GUI).
function Processing.status()
    local out = {}
    for _, p in ipairs(processors) do
        out[#out + 1] = {
            name   = p.info.name,
            class  = p.class,
            busy   = p.busy,
            recipe = p.recipe and p.recipe.id or nil,
            job    = p.job and p.job.itemName or nil,
        }
    end
    return out
end

--- Return queue snapshot (for GUI).
function Processing.getQueue()
    local snap = {}
    for _, j in ipairs(jobQueue) do snap[#snap + 1] = Utils.shallowCopy(j) end
    return snap
end

return Processing
