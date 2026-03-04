-- StorageOS/recipe_scanner.lua
-- Discovers and loads recipes from LOCAL sources only.
-- No internet connection required.  Works for ALL installed mods.
--
-- Discovery order (highest → lowest priority):
--
--   1. Storage-system peripherals (Advanced Peripherals)
--      • rsBridge  – Refined Storage:  getRecipes() returns every crafting
--                    and processing pattern stored in the RS system.
--      • meBridge  – Applied Energistics 2: listCraftableItems() + per-item
--                    recipe query.  Covers all patterns set up in AE2.
--      • Generic   – any connected peripheral that exposes a listRecipes(),
--                    getRecipes(), or getCraftingRecipes() method.
--        (Handles custom mods or future Advanced Peripherals releases.)
--
--   2. Local Minecraft recipe JSON files
--      Directories listed in Config.RECIPE_DATA_DIRS are scanned for *.json
--      files using the standard Minecraft recipe JSON schema:
--        minecraft:crafting_shaped / shapeless / smelting / blasting / smoking
--      Drop any datapack recipe files here and they load automatically.
--
--   3. User .lua recipe files in Config.RECIPE_DIR
--      Handled by RecipeManager.loadFromDisk() after the scanner runs.
--
--   4. Built-in defaults (StorageOS/recipes/defaults.lua)
--      Final fallback – always available, no peripherals or files needed.
--
-- Summary statistics are written to Config.RECIPE_SCAN_META after each scan
-- so the GUI can show how many recipes came from each source.

local RecipeScanner = {}

local Config = require("StorageOS.config")
local Logger = require("StorageOS.logger")
local Utils  = require("StorageOS.utils")
local RM     = require("StorageOS.recipes.manager")

-- ── Minecraft recipe JSON parsers ─────────────────────────────────────────────
-- (Shared with the optional recipe_fetcher module so we don't duplicate code.)
-- These parse the standard Minecraft datapack JSON format into StorageOS tables.

-- Common item tags → a representative concrete item.
-- Used when a recipe ingredient is specified as a tag rather than a direct item.
local TAG_ITEMS = {
    ["minecraft:logs"]                   = "minecraft:oak_log",
    ["minecraft:logs_that_burn"]         = "minecraft:oak_log",
    ["minecraft:oak_logs"]               = "minecraft:oak_log",
    ["minecraft:spruce_logs"]            = "minecraft:spruce_log",
    ["minecraft:birch_logs"]             = "minecraft:birch_log",
    ["minecraft:jungle_logs"]            = "minecraft:jungle_log",
    ["minecraft:acacia_logs"]            = "minecraft:acacia_log",
    ["minecraft:dark_oak_logs"]          = "minecraft:dark_oak_log",
    ["minecraft:cherry_logs"]            = "minecraft:cherry_log",
    ["minecraft:mangrove_logs"]          = "minecraft:mangrove_log",
    ["minecraft:bamboo_blocks"]          = "minecraft:bamboo_block",
    ["minecraft:crimson_stems"]          = "minecraft:crimson_stem",
    ["minecraft:warped_stems"]           = "minecraft:warped_stem",
    ["minecraft:planks"]                 = "minecraft:oak_planks",
    ["minecraft:wooden_slabs"]           = "minecraft:oak_slab",
    ["minecraft:wooden_stairs"]          = "minecraft:oak_stairs",
    ["minecraft:wooden_fences"]          = "minecraft:oak_fence",
    ["minecraft:wooden_fence_gates"]     = "minecraft:oak_fence_gate",
    ["minecraft:wooden_doors"]           = "minecraft:oak_door",
    ["minecraft:wooden_trapdoors"]       = "minecraft:oak_trapdoor",
    ["minecraft:wooden_buttons"]         = "minecraft:oak_button",
    ["minecraft:wooden_pressure_plates"] = "minecraft:oak_pressure_plate",
    ["minecraft:signs"]                  = "minecraft:oak_sign",
    ["minecraft:hanging_signs"]          = "minecraft:oak_hanging_sign",
    ["minecraft:slabs"]                  = "minecraft:oak_slab",
    ["minecraft:stairs"]                 = "minecraft:oak_stairs",
    ["minecraft:fences"]                 = "minecraft:oak_fence",
    ["minecraft:fence_gates"]            = "minecraft:oak_fence_gate",
    ["minecraft:doors"]                  = "minecraft:oak_door",
    ["minecraft:trapdoors"]              = "minecraft:oak_trapdoor",
    ["minecraft:buttons"]                = "minecraft:oak_button",
    ["minecraft:pressure_plates"]        = "minecraft:oak_pressure_plate",
    ["minecraft:stone_bricks"]           = "minecraft:stone_bricks",
    ["minecraft:stone_crafting_materials"] = "minecraft:cobblestone",
    ["minecraft:stone_tool_materials"]   = "minecraft:cobblestone",
    ["minecraft:wool"]                   = "minecraft:white_wool",
    ["minecraft:carpets"]                = "minecraft:white_carpet",
    ["minecraft:beds"]                   = "minecraft:white_bed",
    ["minecraft:terracotta"]             = "minecraft:white_terracotta",
    ["minecraft:concrete_powder"]        = "minecraft:white_concrete_powder",
    ["minecraft:banners"]                = "minecraft:white_banner",
    ["minecraft:shulker_boxes"]          = "minecraft:shulker_box",
    ["minecraft:coals"]                  = "minecraft:coal",
    ["minecraft:sand"]                   = "minecraft:sand",
    ["minecraft:flowers"]                = "minecraft:dandelion",
    ["minecraft:small_flowers"]          = "minecraft:dandelion",
    ["minecraft:tall_flowers"]           = "minecraft:sunflower",
    ["minecraft:saplings"]               = "minecraft:oak_sapling",
    ["minecraft:leaves"]                 = "minecraft:oak_leaves",
    ["minecraft:boats"]                  = "minecraft:oak_boat",
    ["minecraft:chest_boats"]            = "minecraft:oak_chest_boat",
    ["minecraft:iron_ingots"]            = "minecraft:iron_ingot",
    ["minecraft:gold_ingots"]            = "minecraft:gold_ingot",
    ["minecraft:copper_ingots"]          = "minecraft:copper_ingot",
    ["minecraft:diamonds"]               = "minecraft:diamond",
    ["minecraft:emeralds"]               = "minecraft:emerald",
    ["minecraft:netherite_ingots"]       = "minecraft:netherite_ingot",
    ["minecraft:lapis_lazuli"]           = "minecraft:lapis_lazuli",
    ["minecraft:redstone"]               = "minecraft:redstone",
    ["minecraft:quartz"]                 = "minecraft:quartz",
    ["minecraft:amethyst"]               = "minecraft:amethyst_shard",
    ["minecraft:arrows"]                 = "minecraft:arrow",
    ["minecraft:music_discs"]            = "minecraft:music_disc_13",
    ["minecraft:anvil"]                  = "minecraft:anvil",
}

--- Resolve a Minecraft ingredient JSON value to a concrete item name string.
--- Returns nil if the ingredient cannot be resolved.
local function resolveIngredient(ing)
    if not ing then return nil end
    if type(ing) == "string" then return ing end
    if ing[1] ~= nil then               -- array of alternatives
        for _, alt in ipairs(ing) do
            local r = resolveIngredient(alt)
            if r then return r end
        end
        return nil
    end
    if ing.item then return ing.item end
    if ing.tag  then
        local r = TAG_ITEMS[ing.tag]
        if not r then Logger.debug("RecipeScanner: unknown tag '%s'", ing.tag) end
        return r
    end
    return nil
end

--- Extract (itemName, count) from a Minecraft result value.
local function resolveResult(result)
    if not result then return nil, 0 end
    if type(result) == "string" then return result, 1 end
    return (result.item or result.id), (result.count or 1)
end

local function parseShapedRecipe(data, id)
    if not data.pattern or not data.key or not data.result then return nil end
    local output, count = resolveResult(data.result)
    if not output then return nil end
    local grid = {}
    for rowIdx, row in ipairs(data.pattern) do
        for col = 1, #row do
            local ch   = row:sub(col, col)
            local slot = (rowIdx - 1) * 3 + col
            if ch ~= " " then
                local item = resolveIngredient(data.key[ch])
                if not item then return nil end
                grid[slot] = item
            end
        end
    end
    return { id=id, output=output, count=count, type="craft", grid=grid, shapeless=false }
end

local function parseShapelessRecipe(data, id)
    if not data.ingredients or not data.result then return nil end
    local output, count = resolveResult(data.result)
    if not output then return nil end
    local inputs = {}
    for _, ing in ipairs(data.ingredients) do
        local item = resolveIngredient(ing)
        if not item then return nil end
        inputs[#inputs + 1] = item
    end
    return { id=id, output=output, count=count, type="craft", inputs=inputs, shapeless=true }
end

local function parseSmeltingRecipe(data, id, rtype)
    if not data.ingredient or not data.result then return nil end
    local output, count = resolveResult(data.result)
    if not output then return nil end
    local item = resolveIngredient(data.ingredient)
    if not item then return nil end
    return { id=id, output=output, count=count or 1, type=rtype, inputs={item}, time=data.cookingtime or 200 }
end

local function parseStonecuttingRecipe(data, id)
    if not data.ingredient or not data.result then return nil end
    local output, count = resolveResult(data.result)
    if not output then return nil end
    local item = resolveIngredient(data.ingredient)
    if not item then return nil end
    return { id=id, output=output, count=count or 1, type="craft", inputs={item}, shapeless=true }
end

local JSON_PARSERS = {
    ["minecraft:crafting_shaped"]    = parseShapedRecipe,
    ["minecraft:crafting_shapeless"] = parseShapelessRecipe,
    ["minecraft:smelting"]           = function(d,i) return parseSmeltingRecipe(d,i,"smelt") end,
    ["minecraft:blasting"]           = function(d,i) return parseSmeltingRecipe(d,i,"blast") end,
    ["minecraft:smoking"]            = function(d,i) return parseSmeltingRecipe(d,i,"smoke")  end,
    ["minecraft:stonecutting"]       = parseStonecuttingRecipe,
}

--- Parse a raw Minecraft recipe JSON string.
--- `id` prefix is prepended to the filename-derived recipe id.
local function parseRecipeJSON(jsonStr, filename, idPrefix)
    idPrefix = idPrefix or "file"
    local id = idPrefix .. ":" .. (filename:match("^(.+)%.json$") or filename)
    local ok, data = pcall(textutils.unserialiseJSON, jsonStr)
    if not ok or type(data) ~= "table" then
        Logger.debug("RecipeScanner: JSON parse failed for '%s'", filename)
        return nil
    end
    local parser = data.type and JSON_PARSERS[data.type]
    if not parser then return nil end  -- unsupported type (smithing, special, etc.)
    return parser(data, id)
end

-- ── Source 1: Peripheral API discovery ───────────────────────────────────────

--- Convert a Refined Storage crafting pattern to a StorageOS recipe.
--- RS pattern format (Advanced Peripherals):
---   { inputs = [{name, count, slot?}], outputs = [{name, count}] }
--- Slot numbers in RS are 0-based; we convert to 1-based.
local function convertRSPattern(pattern, idx)
    if not pattern.outputs or #pattern.outputs == 0 then return nil end
    local output = pattern.outputs[1]
    if not output or not output.name then return nil end

    local grid    = {}
    local inputs  = {}
    local hasSlot = false

    for _, ing in ipairs(pattern.inputs or {}) do
        if ing.name then
            if ing.slot ~= nil then
                -- Grid (shaped) pattern – RS uses 0-based slot indices
                grid[ing.slot + 1] = ing.name
                hasSlot = true
            else
                inputs[#inputs + 1] = ing.name
            end
        end
    end

    -- Determine recipe type from the pattern if RS exposes it, else default "craft"
    local rtype = pattern.type or "craft"

    local id = "rs:" .. output.name:gsub("[:/]", "_") .. "_" .. tostring(idx)

    if hasSlot then
        return { id=id, output=output.name, count=output.count or 1, type=rtype,
                 grid=grid, shapeless=false }
    else
        return { id=id, output=output.name, count=output.count or 1, type=rtype,
                 inputs=inputs, shapeless=true }
    end
end

--- Query an RS Bridge peripheral (Advanced Peripherals) for all crafting patterns.
--- Calls `getRecipes()` which returns the full list of patterns stored in the
--- Refined Storage system — including patterns for ALL installed mods.
local function queryRSBridge(bridge, bridgeName)
    local ok, recipes = pcall(bridge.getRecipes)
    if not ok or type(recipes) ~= "table" then
        Logger.warn("RecipeScanner: rsBridge.getRecipes() failed on %s: %s",
            bridgeName, tostring(recipes))
        return 0
    end
    local loaded = 0
    for i, pattern in ipairs(recipes) do
        local recipe = convertRSPattern(pattern, i)
        if recipe then
            RM.add(recipe)
            loaded = loaded + 1
        end
    end
    Logger.info("RecipeScanner: %d recipes from RS Bridge '%s'", loaded, bridgeName)
    return loaded
end

--- Query an ME Bridge peripheral (Advanced Peripherals) for AE2 recipe data.
--- Uses listCraftableItems() to get all items AE2 can autocraft, then attempts
--- getRecipeFor(item) for ingredient details (available in AP 0.7.4+).
local function queryMEBridge(bridge, bridgeName)
    -- listCraftableItems() → [{name, fingerprint, amount, displayName, tags, nbt}]
    local ok, craftable = pcall(bridge.listCraftableItems)
    if not ok or type(craftable) ~= "table" then
        Logger.warn("RecipeScanner: meBridge.listCraftableItems() failed on %s", bridgeName)
        return 0
    end

    local loaded = 0
    for i, entry in ipairs(craftable) do
        local itemName = entry.name or entry.fingerprint
        if itemName then
            -- Try getRecipeFor if available (Advanced Peripherals 0.7.4+)
            local recipeOk, recipeData
            if bridge.getRecipeFor then
                recipeOk, recipeData = pcall(bridge.getRecipeFor, itemName)
            end

            if recipeOk and type(recipeData) == "table" and recipeData.inputs then
                -- getRecipeFor returns a single pattern in RS-like format
                local recipe = convertRSPattern(recipeData, i)
                if recipe then
                    RM.add(recipe)
                    loaded = loaded + 1
                end
            else
                -- No ingredient data available – register as "craftable via AE2"
                -- with unknown ingredients (still useful for the "Craftable Now" check
                -- when AE2 is the crafting backend).
                RM.add({
                    id        = "me:" .. itemName:gsub("[:/]", "_") .. "_" .. i,
                    output    = itemName,
                    count     = entry.amount or 1,
                    type      = "craft",
                    inputs    = {},   -- AE2 manages the ingredients internally
                    shapeless = true,
                    via_ae2   = true, -- flag so crafting module can delegate to AE2
                })
                loaded = loaded + 1
            end
        end
    end
    Logger.info("RecipeScanner: %d recipes from ME Bridge '%s'", loaded, bridgeName)
    return loaded
end

--- Generic peripheral probe: check any peripheral for common recipe API methods.
--- Handles unknown mods that expose recipe data under a standard method name.
local function queryGenericPeripheral(periph, name)
    -- Try each common recipe method name
    local candidates = { "getRecipes", "listRecipes", "getCraftingRecipes", "getAllRecipes" }
    for _, method in ipairs(candidates) do
        if periph[method] then
            local ok, recipes = pcall(periph[method], periph)
            if ok and type(recipes) == "table" and #recipes > 0 then
                Logger.info("RecipeScanner: '%s' has %s() → %d entries", name, method, #recipes)
                local loaded = 0
                for i, r in ipairs(recipes) do
                    -- Try to interpret as an RS-style pattern first
                    if type(r) == "table" then
                        local recipe = convertRSPattern(r, i)
                        if recipe then
                            -- Prefix id with peripheral name to avoid clashes
                            recipe.id = name:gsub("[:/.]", "_") .. ":" .. (recipe.id or i)
                            RM.add(recipe)
                            loaded = loaded + 1
                        end
                    end
                end
                if loaded > 0 then
                    Logger.info("RecipeScanner: loaded %d via %s.%s()", loaded, name, method)
                    return loaded
                end
            end
        end
    end
    return 0
end

--- Scan ALL connected peripherals for recipe APIs.
--- Returns { rs=N, me=N, generic=N } counts per source.
local function scanPeripherals()
    local counts = { rs = 0, me = 0, generic = 0 }
    local scanned = {}  -- track already-queried peripherals

    -- First pass: look for known bridge types
    for _, ptype in ipairs(Config.RECIPE_PERIPHERAL_TYPES) do
        -- peripheral.find iterates ALL connected peripherals of this type
        local found = { peripheral.find(ptype) }
        for _, periph in ipairs(found) do
            local pname = peripheral.getName(periph) or ptype
            if not scanned[pname] then
                scanned[pname] = true
                local lower = ptype:lower()
                if lower:find("rs") or lower:find("refinedstorage") then
                    counts.rs = counts.rs + queryRSBridge(periph, pname)
                elseif lower:find("me") or lower:find("appeng") then
                    counts.me = counts.me + queryMEBridge(periph, pname)
                else
                    counts.generic = counts.generic + queryGenericPeripheral(periph, pname)
                end
            end
        end
    end

    -- Second pass: probe ALL remaining peripherals for generic recipe methods
    for _, pname in ipairs(peripheral.getNames()) do
        if not scanned[pname] then
            local periph = peripheral.wrap(pname)
            if periph then
                local n = queryGenericPeripheral(periph, pname)
                if n > 0 then
                    counts.generic = counts.generic + n
                    scanned[pname] = true
                end
            end
        end
    end

    return counts
end

-- ── Source 2: Local Minecraft recipe JSON files ───────────────────────────────

--- Scan a directory for *.json recipe files and load them.
--- Subdirectories are also scanned (one level deep) to support the
--- standard Minecraft datapack layout: data/{namespace}/recipes/*.json
local function loadJsonDir(dir, idPrefix)
    if not fs.exists(dir) or not fs.isDir(dir) then return 0 end
    local loaded = 0

    local function scanDir(path, prefix)
        local entries = fs.list(path)
        for _, entry in ipairs(entries) do
            local fullPath = path .. "/" .. entry
            if fs.isDir(fullPath) then
                -- One level of subdirectory recursion
                scanDir(fullPath, prefix .. entry .. "/")
            elseif entry:match("%.json$") then
                local f = fs.open(fullPath, "r")
                if f then
                    local body = f.readAll()
                    f.close()
                    local recipe = parseRecipeJSON(body, entry, idPrefix)
                    if recipe then
                        RM.add(recipe)
                        loaded = loaded + 1
                    end
                end
            end
        end
    end

    scanDir(dir, idPrefix or "file")
    return loaded
end

--- Scan all directories in Config.RECIPE_DATA_DIRS for JSON recipe files.
local function scanJsonDirs()
    local total = 0
    for _, dir in ipairs(Config.RECIPE_DATA_DIRS or {}) do
        local n = loadJsonDir(dir, "file")
        if n > 0 then
            Logger.info("RecipeScanner: loaded %d JSON recipes from %s", n, dir)
            total = total + n
        end
    end
    return total
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Run the full local recipe discovery process.
--- `progressCb(source, loaded)` is called after each source completes.
---
--- Returns a summary table:
---   { rs=N, me=N, generic=N, json=N, defaults=N, total=N }
function RecipeScanner.scan(progressCb)
    local summary = { rs=0, me=0, generic=0, json=0, defaults=0, total=0 }

    local function progress(src, n)
        summary[src] = (summary[src] or 0) + n
        if progressCb then pcall(progressCb, src, n) end
    end

    -- ── Phase 1: peripheral APIs ──────────────────────────────────────────────
    Logger.info("RecipeScanner: probing peripheral recipe APIs…")
    local ok, periphCounts = pcall(scanPeripherals)
    if ok then
        progress("rs",      periphCounts.rs)
        progress("me",      periphCounts.me)
        progress("generic", periphCounts.generic)
    else
        Logger.warn("RecipeScanner: peripheral scan error: %s", tostring(periphCounts))
    end

    -- ── Phase 2: local JSON files ─────────────────────────────────────────────
    Logger.info("RecipeScanner: scanning local recipe JSON directories…")
    local jsonCount = scanJsonDirs()
    progress("json", jsonCount)

    -- ── Phase 3: user .lua recipe files (handled by manager) ─────────────────
    -- Caller is responsible for calling RM.loadFromDisk() afterwards.

    -- ── Phase 4: built-in defaults if nothing else loaded ────────────────────
    local periodTotal = summary.rs + summary.me + summary.generic + summary.json
    if periodTotal == 0 then
        Logger.info("RecipeScanner: no external recipes found – loading defaults")
        local defaults = require("StorageOS.recipes.defaults")
        RM.add(defaults)
        summary.defaults = RM.count()
        progress("defaults", summary.defaults)
    end

    summary.total = RM.count()

    -- Persist scan metadata
    Utils.saveTable(Config.RECIPE_SCAN_META, {
        scannedAt = os.time(),
        summary   = summary,
    })

    Logger.info("RecipeScanner.scan: total=%d (rs=%d me=%d generic=%d json=%d defaults=%d)",
        summary.total, summary.rs, summary.me, summary.generic,
        summary.json, summary.defaults)

    return summary
end

--- Return the metadata from the last scan, or nil if never scanned.
function RecipeScanner.lastScanMeta()
    local meta, _ = Utils.loadTable(Config.RECIPE_SCAN_META)
    return meta
end

--- Return a human-readable source breakdown string for the GUI.
--- e.g. "RS:120  ME:45  JSON:30  dflt:40  total:235"
function RecipeScanner.sourceSummary()
    local meta = RecipeScanner.lastScanMeta()
    if not meta or not meta.summary then
        return "not scanned"
    end
    local s = meta.summary
    local parts = {}
    if (s.rs      or 0) > 0 then parts[#parts+1] = "RS:"      .. s.rs      end
    if (s.me      or 0) > 0 then parts[#parts+1] = "ME:"      .. s.me      end
    if (s.generic or 0) > 0 then parts[#parts+1] = "ext:"     .. s.generic end
    if (s.json    or 0) > 0 then parts[#parts+1] = "JSON:"    .. s.json    end
    if (s.defaults or 0) > 0 then parts[#parts+1] = "dflt:"   .. s.defaults end
    parts[#parts+1] = "total:" .. (s.total or 0)
    return table.concat(parts, "  ")
end

return RecipeScanner
