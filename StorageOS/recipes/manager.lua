-- StorageOS/recipes/manager.lua
-- Dynamic recipe loading, lookup, and management.
--
-- Recipes are stored as Lua files in /StorageOS/recipes/ that each return
-- a table (or list of tables) conforming to the recipe schema below.
--
-- Recipe schema:
--   {
--     id        = "unique_string",          -- unique recipe identifier
--     output    = "minecraft:planks",       -- item name produced
--     count     = 4,                        -- items produced per craft
--     type      = "craft" | "smelt" | "blast" | "smoke" | "create_press"
--                 | "create_mixing" | "create_compacting",
--     inputs    = { "minecraft:oak_log" },  -- for shaped/shapeless: flat list
--     grid      = {                         -- 3x3 grid (shaped crafting only)
--       [1]="minecraft:planks", [2]="minecraft:planks", …, [9]=…
--     },
--     shapeless = true,                     -- if true, grid order ignored
--     fuel      = "minecraft:coal",         -- override fuel for smelting
--     time      = 200,                      -- processing time in ticks
--   }

local RecipeManager = {}
RecipeManager.__index = RecipeManager

local Config = require("StorageOS.config")
local Logger = require("StorageOS.logger")
local Utils  = require("StorageOS.utils")

-- Internal registry: id → recipe, output → [recipes]
local byId     = {}
local byOutput = {}

-- ── Internal helpers ──────────────────────────────────────────────────────────

local function register(recipe)
    if not recipe or not recipe.id or not recipe.output then
        Logger.warn("RecipeManager: skipping invalid recipe (missing id/output)")
        return false
    end
    if byId[recipe.id] then
        Logger.debug("RecipeManager: overwriting recipe '%s'", recipe.id)
    end
    byId[recipe.id] = recipe
    if not byOutput[recipe.output] then byOutput[recipe.output] = {} end
    -- Replace existing entry with same id
    local list = byOutput[recipe.output]
    for i, r in ipairs(list) do
        if r.id == recipe.id then
            list[i] = recipe
            return true
        end
    end
    list[#list + 1] = recipe
    return true
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Load a single recipe table (or list of tables) into the registry.
function RecipeManager.add(recipeOrList)
    if type(recipeOrList) == "table" then
        if recipeOrList.id then
            register(recipeOrList)
        else
            -- Assume it's an array of recipes
            for _, r in ipairs(recipeOrList) do
                register(r)
            end
        end
    end
end

--- Load all .lua recipe files from the recipe directory.
function RecipeManager.loadFromDisk()
    local dir = Config.RECIPE_DIR
    if not fs.exists(dir) then
        Logger.info("RecipeManager: recipe dir %s not found, skipping", dir)
        return
    end
    local files = fs.list(dir)
    local loaded = 0
    for _, fname in ipairs(files) do
        if fname:match("%.lua$") and fname ~= "manager.lua" and fname ~= "defaults.lua" then
            local path = dir .. "/" .. fname
            local ok, result = pcall(dofile, path)
            if ok and result then
                RecipeManager.add(result)
                loaded = loaded + 1
                Logger.info("RecipeManager: loaded %s", fname)
            else
                Logger.warn("RecipeManager: failed to load %s: %s", fname, tostring(result))
            end
        end
    end
    Logger.info("RecipeManager: loaded %d recipe file(s), %d total recipes",
        loaded, Utils.tableLen(byId))
end

--- Save a recipe to disk so it persists across reboots.
function RecipeManager.saveToDisk(recipe)
    if not recipe or not recipe.id then return false end
    Utils.ensureDir(Config.RECIPE_DIR)
    local path = Config.RECIPE_DIR .. "/" .. recipe.id:gsub("[^%w_]", "_") .. ".lua"
    local f = fs.open(path, "w")
    if not f then return false end
    f.write("return " .. textutils.serialize(recipe))
    f.close()
    Logger.info("RecipeManager: saved recipe '%s' to %s", recipe.id, path)
    return true
end

--- Remove a recipe by id (from memory only; delete the file separately if needed).
function RecipeManager.remove(id)
    local recipe = byId[id]
    if not recipe then return false end
    byId[id] = nil
    local list = byOutput[recipe.output]
    if list then
        for i, r in ipairs(list) do
            if r.id == id then
                table.remove(list, i)
                break
            end
        end
        if #list == 0 then byOutput[recipe.output] = nil end
    end
    Logger.info("RecipeManager: removed recipe '%s'", id)
    return true
end

--- Look up all recipes that produce `itemName`.
function RecipeManager.forOutput(itemName)
    return byOutput[itemName] or {}
end

--- Look up a recipe by its id.
function RecipeManager.byId(id)
    return byId[id]
end

--- Return a list of all registered recipe ids.
function RecipeManager.allIds()
    return Utils.sortedKeys(byId)
end

--- Return a list of all craftable item names (have at least one recipe).
function RecipeManager.craftableItems()
    local names = {}
    for name in pairs(byOutput) do names[#names + 1] = name end
    table.sort(names)
    return names
end

--- Return total count of registered recipes.
function RecipeManager.count()
    return Utils.tableLen(byId)
end

--- Find the best recipe for `itemName`, preferring shorter ingredient lists.
function RecipeManager.bestFor(itemName)
    local recipes = byOutput[itemName]
    if not recipes or #recipes == 0 then return nil end
    local best = recipes[1]
    for _, r in ipairs(recipes) do
        local inCount = r.inputs and #r.inputs or 0
        local bestCount = best.inputs and #best.inputs or 0
        if inCount < bestCount then best = r end
    end
    return best
end

--- Build a flat ingredient map for a recipe: { itemName → count }
function RecipeManager.ingredients(recipe)
    if not recipe then return {} end
    local map = {}
    local source = recipe.grid or recipe.inputs or {}
    for _, item in pairs(source) do
        if item and item ~= "" then
            map[item] = (map[item] or 0) + 1
        end
    end
    return map
end

return RecipeManager
