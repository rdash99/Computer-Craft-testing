-- StorageOS/crafting.lua
-- Crafting subsystem: turtle-based 3×3 crafting, workbench peripherals,
-- recipe queueing, ingredient sourcing, and result collection.

local Crafting = {}
Crafting.__index = Crafting

local Config        = require("StorageOS.config")
local Logger        = require("StorageOS.logger")
local Utils         = require("StorageOS.utils")
local Network       = require("StorageOS.network")
local Storage       = require("StorageOS.storage")
local RecipeManager = require("StorageOS.recipes.manager")

-- ── Internal state ────────────────────────────────────────────────────────────

-- Pending craft queue: list of { recipe, amount, callbackFn, status }
local craftQueue = {}
local craftQueueLock = false  -- simple mutex for queue access

-- ── Helpers ───────────────────────────────────────────────────────────────────

--- Find a usable crafting turtle or workbench on the network.
--- Returns an info record or nil.
local function findCrafter()
    -- Prefer a crafting turtle (can do shaped crafts via turtle.craft())
    local turtles = Network.getByClass("turtle")
    if #turtles > 0 then return turtles[1] end
    -- Fall back to workbench peripheral
    local workbenches = Network.getByClass("workbench")
    if #workbenches > 0 then return workbenches[1] end
    return nil
end

--- Transfer an ingredient from storage into a specific turtle slot.
--- `crafterName` is the turtle/workbench peripheral name.
--- `slot` is the 1-9 slot index.
--- `itemName` is the item to place.
--- `count` is the number of items needed.
--- Returns true on success.
local function loadIngredient(crafterName, slot, itemName, count)
    if not itemName or itemName == "" then return true end
    local moved = Storage.pushTo(itemName, count, crafterName)
    if moved < count then
        Logger.warn("Crafting.loadIngredient: needed %d %s, only moved %d", count, itemName, moved)
        return false
    end
    -- For a workbench peripheral the items land in its inventory;
    -- for a turtle the items must be in the correct turtle slot.
    -- (The turtle.transferTo() call below handles turtle-internal re-slotting.)
    return true
end

--- Perform a 3×3 shaped craft on a crafting turtle.
--- Items are pushed from storage directly into the correct turtle inventory slots
--- via pushItems(targetName, fromSlot, count, toSlot).
--- `crafterInfo` is the Network info record; `recipe` and `times` as described above.
--- Returns amount produced or 0 on error.
local function craftOnTurtle(crafterInfo, recipe, times)
    -- Crafting turtle slot layout (slots 1-16, skip column 4):
    --   Grid pos:  1  2  3    →  Turtle slots: 1  2  3
    --              4  5  6    →                5  6  7
    --              7  8  9    →                9 10 11
    local gridToTurtleSlot = { 1, 2, 3, 5, 6, 7, 9, 10, 11 }
    local crafterName = crafterInfo.name
    local produced    = 0

    -- Clear any leftover items from a previous failed craft attempt so the
    -- crafting grid slots are guaranteed empty before we begin.
    Storage.ingestFrom(crafterName)

    for _ = 1, times do
        local placed = true

        if recipe.shapeless then
            -- Shapeless: push each ingredient into sequential turtle slots
            for i, item in ipairs(recipe.inputs or {}) do
                local tSlot = gridToTurtleSlot[i]
                if tSlot and item and item ~= "" then
                    local moved = Storage.pushTo(item, 1, crafterName, tSlot)
                    if moved < 1 then placed = false; break end
                end
            end
        else
            -- Shaped: push each grid ingredient into its exact turtle slot
            for gridSlot = 1, 9 do
                local item  = (recipe.grid or {})[gridSlot]
                local tSlot = gridToTurtleSlot[gridSlot]
                if item and item ~= "" then
                    local moved = Storage.pushTo(item, 1, crafterName, tSlot)
                    if moved < 1 then placed = false; break end
                end
            end
        end

        if not placed then
            Logger.warn("Crafting.craftOnTurtle: failed to fill all ingredient slots")
            -- Recover any ingredients already placed back into storage
            Storage.ingestFrom(crafterName)
            break
        end

        -- Execute craft via the turtle peripheral's craft() method
        local ok, crafted = pcall(crafterInfo.periph.craft, crafterInfo.periph)
        if ok and crafted then
            produced = produced + (recipe.count or 1)
            -- Collect the crafted output immediately so those slots are free
            -- for the next iteration's ingredients (otherwise turtle slots
            -- remain occupied and subsequent pushes to the same slots fail).
            Storage.ingestFrom(crafterName)
        else
            Logger.warn("Crafting.craftOnTurtle: craft() returned false or errored")
            -- Recover any ingredients left in the turtle
            Storage.ingestFrom(crafterName)
            break
        end
    end
    return produced
end

--- Perform a craft on a workbench peripheral (CC:Tweaked workbench API).
--- `workbench` is the peripheral; `recipe` and `times` as above.
local function craftOnWorkbench(workbench, recipe, times)
    -- Workbench peripheral API: workbench.craft(recipe_table)
    -- recipe_table keys are 1-9 with item names.
    local produced = 0
    for _ = 1, times do
        local gridArg = {}
        if recipe.shapeless then
            for i, item in ipairs(recipe.inputs or {}) do
                gridArg[i] = item
            end
        else
            for slot, item in pairs(recipe.grid or {}) do
                gridArg[slot] = item
            end
        end
        local ok, err = pcall(workbench.craft, workbench, gridArg)
        if ok then
            produced = produced + (recipe.count or 1)
        else
            Logger.warn("Crafting.craftOnWorkbench: %s", tostring(err))
            break
        end
    end
    return produced
end

--- Validate that all ingredients for `recipe * times` are available in storage.
--- Returns true if all ingredients are available, false + (item, missing_count) otherwise.
--- Does NOT move any items.
local function validateIngredients(recipe, times)
    local ingredients = RecipeManager.ingredients(recipe)
    for item, perCraft in pairs(ingredients) do
        local needed = perCraft * times
        local avail  = Storage.count(item)
        if avail < needed then
            Logger.warn("Crafting: missing %d %s (have %d)", needed - avail, item, avail)
            return false, item, needed - avail
        end
    end
    return true
end

--- Push all ingredients for `recipe * times` into a workbench peripheral.
--- (Workbenches need items physically in adjacent inventory.)
local function loadWorkbenchIngredients(crafterName, recipe, times)
    local ingredients = RecipeManager.ingredients(recipe)
    for item, perCraft in pairs(ingredients) do
        local moved = Storage.pushTo(item, perCraft * times, crafterName)
        if moved < perCraft * times then
            Logger.warn("Crafting: only pushed %d/%d %s", moved, perCraft * times, item)
            return false, item, perCraft * times - moved
        end
    end
    return true
end

-- Keep alias for callers that still use the old name
local sourceIngredients = validateIngredients

--- Collect crafting results back into storage from the crafter peripheral.
local function collectResults(crafterInfo)
    local moved = Storage.ingestFrom(crafterInfo.name)
    local total = 0
    for _, count in pairs(moved) do total = total + count end
    return total
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Immediately attempt to craft `amount` of `itemName`.
--- Returns { success, produced, error }.
function Crafting.craft(itemName, amount)
    amount = amount or 1
    local recipe = RecipeManager.bestFor(itemName)
    if not recipe then
        return false, 0, "No recipe for " .. itemName
    end
    if recipe.type ~= "craft" then
        return false, 0, string.format("Recipe '%s' is not a crafting recipe (type=%s)", recipe.id, recipe.type)
    end

    local crafterInfo = findCrafter()
    if not crafterInfo then
        return false, 0, "No crafting turtle or workbench found on network"
    end

    -- How many times to run the recipe
    local timesNeeded = math.ceil(amount / (recipe.count or 1))
    Logger.info("Crafting.craft: %s × %d (running recipe %d times)", itemName, amount, timesNeeded)

    -- Validate ingredient availability (does not move items)
    local ok, missingItem, missingCount = validateIngredients(recipe, timesNeeded)
    if not ok then
        return false, 0, string.format("Missing %d %s", missingCount, missingItem)
    end

    -- Execute craft
    local produced = 0
    local pType    = crafterInfo.class
    if pType == "turtle" then
        -- craftOnTurtle pushes each ingredient to the correct turtle slot, then calls craft()
        produced = craftOnTurtle(crafterInfo, recipe, timesNeeded)
    elseif pType == "workbench" then
        -- Workbench needs items pre-loaded into its inventory
        local loadOk, loadItem, loadMissing = loadWorkbenchIngredients(crafterInfo.name, recipe, timesNeeded)
        if not loadOk then
            return false, 0, string.format("Load failed: missing %d %s", loadMissing, loadItem)
        end
        produced = craftOnWorkbench(crafterInfo.periph, recipe, timesNeeded)
    else
        return false, 0, "Crafter type not supported: " .. pType
    end

    -- Collect leftovers / results
    collectResults(crafterInfo)
    Storage.scan()  -- refresh index after crafting

    if produced > 0 then
        Logger.info("Crafting.craft: produced %d %s", produced, itemName)
        return true, produced
    else
        Logger.warn("Crafting.craft: produced 0 items for %s", itemName)
        return false, 0, "Craft produced no output"
    end
end

--- Queue a crafting job (non-blocking).
--- `callbackFn` is called with (success, produced, err) when done.
function Crafting.queue(itemName, amount, callbackFn)
    local job = {
        itemName   = itemName,
        amount     = amount or 1,
        callbackFn = callbackFn,
        status     = "queued",
        queued_at  = os.time(),
    }
    craftQueue[#craftQueue + 1] = job
    Logger.info("Crafting.queue: queued %d × %s", amount, itemName)
    return job
end

--- Process one job from the craft queue.
--- Call this from the task scheduler or main loop.
--- Returns true if a job was processed.
function Crafting.processQueue()
    if craftQueueLock or #craftQueue == 0 then return false end
    craftQueueLock = true
    local job = table.remove(craftQueue, 1)
    if not job then craftQueueLock = false; return false end

    job.status = "running"
    local ok, produced, err = Crafting.craft(job.itemName, job.amount)
    job.status = ok and "done" or "failed"
    job.result = { ok = ok, produced = produced, err = err }

    if job.callbackFn then
        pcall(job.callbackFn, ok, produced, err)
    end
    craftQueueLock = false
    return true
end

--- Return the current craft queue (read-only snapshot).
function Crafting.getQueue()
    local snap = {}
    for _, j in ipairs(craftQueue) do snap[#snap + 1] = Utils.shallowCopy(j) end
    return snap
end

--- Clear the craft queue (e.g. on shutdown or error recovery).
function Crafting.clearQueue()
    craftQueue = {}
    Logger.info("Crafting.clearQueue: queue cleared")
end

--- Return true if a crafting turtle or workbench is available on the network.
function Crafting.hasCrafter()
    return findCrafter() ~= nil
end

--- Register a new recipe dynamically (also saves to disk).
function Crafting.addRecipe(recipe, saveToDisk)
    RecipeManager.add(recipe)
    if saveToDisk then
        RecipeManager.saveToDisk(recipe)
    end
    Logger.info("Crafting.addRecipe: added recipe '%s'", recipe.id or "?")
end

--- Remove a recipe by id.
function Crafting.removeRecipe(id)
    return RecipeManager.remove(id)
end

return Crafting
