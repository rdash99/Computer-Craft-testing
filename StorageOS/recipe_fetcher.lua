-- StorageOS/recipe_fetcher.lua
-- Downloads and parses vanilla Minecraft recipes from the misode/mcmeta
-- GitHub repository, which mirrors the official Minecraft game data assets.
--
-- Source: https://github.com/misode/mcmeta  (branch "{version}-assets")
-- Recipe files: data/minecraft/recipes/*.json
--
-- Fetched recipes are cached as .lua files in Config.RECIPE_FETCHED_DIR so
-- the system works fully offline after the first successful fetch.
-- CC:Tweaked's built-in textutils.unserialiseJSON() handles all JSON parsing.
--
-- Usage:
--   local RF = require("StorageOS.recipe_fetcher")
--   if RF.needsFetch() then
--       RF.fetchAll(nil, function(done, total, phase) ... end)
--   else
--       RF.loadCached()
--   end

local RecipeFetcher = {}

local Config = require("StorageOS.config")
local Logger = require("StorageOS.logger")
local Utils  = require("StorageOS.utils")
local RM     = require("StorageOS.recipes.manager")

-- ── GitHub source configuration ───────────────────────────────────────────────

local REPO_OWNER  = "misode"
local REPO_NAME   = "mcmeta"
local RECIPE_PATH = "data/minecraft/recipes"

local function mcmetaBranch(version)
    return version .. "-assets"
end

-- GitHub Contents API: returns a JSON array of file metadata for a directory.
local function contentsApiUrl(version)
    return string.format(
        "https://api.github.com/repos/%s/%s/contents/%s?ref=%s",
        REPO_OWNER, REPO_NAME, RECIPE_PATH, mcmetaBranch(version))
end

-- Raw file URL for individual recipe JSON files.
local function rawFileUrl(version, filename)
    return string.format(
        "https://raw.githubusercontent.com/%s/%s/%s/%s/%s",
        REPO_OWNER, REPO_NAME, mcmetaBranch(version), RECIPE_PATH, filename)
end

-- ── Tag resolution table ──────────────────────────────────────────────────────
-- Maps Minecraft item tag IDs → a representative concrete item.
-- When a recipe ingredient specifies a tag, StorageOS will use this item.
-- Recipes with unrecognised tags are skipped (they'll log a debug warning).
local TAG_ITEMS = {
    -- Logs & stems
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
    -- Planks & wood products
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
    -- Generic building blocks
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
    -- Wool, carpet, terracotta
    ["minecraft:wool"]                   = "minecraft:white_wool",
    ["minecraft:carpets"]                = "minecraft:white_carpet",
    ["minecraft:beds"]                   = "minecraft:white_bed",
    ["minecraft:terracotta"]             = "minecraft:white_terracotta",
    ["minecraft:concrete_powder"]        = "minecraft:white_concrete_powder",
    ["minecraft:banners"]                = "minecraft:white_banner",
    ["minecraft:shulker_boxes"]          = "minecraft:shulker_box",
    -- Misc
    ["minecraft:coals"]                  = "minecraft:coal",
    ["minecraft:sand"]                   = "minecraft:sand",
    ["minecraft:flowers"]                = "minecraft:dandelion",
    ["minecraft:small_flowers"]          = "minecraft:dandelion",
    ["minecraft:tall_flowers"]           = "minecraft:sunflower",
    ["minecraft:saplings"]               = "minecraft:oak_sapling",
    ["minecraft:leaves"]                 = "minecraft:oak_leaves",
    ["minecraft:boats"]                  = "minecraft:oak_boat",
    ["minecraft:chest_boats"]            = "minecraft:oak_chest_boat",
    -- Ingots, gems, materials
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
    -- Misc tools/equipment
    ["minecraft:arrows"]                 = "minecraft:arrow",
    ["minecraft:music_discs"]            = "minecraft:music_disc_13",
    ["minecraft:anvil"]                  = "minecraft:anvil",
}

-- ── JSON ↔ StorageOS recipe conversion ───────────────────────────────────────

--- Resolve a Minecraft ingredient JSON value to a concrete item name string.
--- Returns nil if the ingredient cannot be resolved (unknown tag, empty, etc.).
--- Handles:
---   "minecraft:coal"                → "minecraft:coal"  (legacy string)
---   {"item": "minecraft:coal"}      → "minecraft:coal"
---   {"tag":  "minecraft:coals"}     → TAG_ITEMS lookup
---   [{...}, {...}]                  → first resolvable option
local function resolveIngredient(ing)
    if not ing then return nil end
    if type(ing) == "string" then return ing end
    -- Array of alternatives – use first resolvable one
    if ing[1] ~= nil then
        for _, alt in ipairs(ing) do
            local resolved = resolveIngredient(alt)
            if resolved then return resolved end
        end
        return nil
    end
    if ing.item then return ing.item end
    if ing.tag  then
        local resolved = TAG_ITEMS[ing.tag]
        if not resolved then
            Logger.debug("RecipeFetcher: unknown tag '%s'", ing.tag)
        end
        return resolved
    end
    return nil
end

--- Extract (itemName, count) from a Minecraft result value.
--- Handles string "minecraft:item", {"item":"minecraft:item","count":N},
--- and the 1.20.5+ {"id":"minecraft:item","count":N} format.
local function resolveResult(result)
    if not result then return nil, 0 end
    if type(result) == "string" then return result, 1 end
    local item  = result.item or result.id
    local count = result.count or 1
    return item, count
end

--- Convert a shaped crafting JSON data table to a StorageOS recipe.
local function parseShapedRecipe(data, id)
    if not data.pattern or not data.key or not data.result then return nil end
    local output, count = resolveResult(data.result)
    if not output then return nil end

    -- Build the 3×3 grid: slot 1 = top-left, slot 9 = bottom-right.
    local grid = {}
    for rowIdx, patternRow in ipairs(data.pattern) do
        for col = 1, #patternRow do
            local ch   = patternRow:sub(col, col)
            local slot = (rowIdx - 1) * 3 + col
            if ch ~= " " then
                local item = resolveIngredient(data.key[ch])
                if not item then return nil end  -- ingredient unresolvable → skip
                grid[slot] = item
            end
        end
    end

    return {
        id       = id,
        output   = output,
        count    = count,
        type     = "craft",
        grid     = grid,
        shapeless = false,
    }
end

--- Convert a shapeless crafting JSON data table to a StorageOS recipe.
local function parseShapelessRecipe(data, id)
    if not data.ingredients or not data.result then return nil end
    local output, count = resolveResult(data.result)
    if not output then return nil end

    local inputs = {}
    for _, ing in ipairs(data.ingredients) do
        local item = resolveIngredient(ing)
        if not item then return nil end  -- any unresolvable ingredient → skip
        inputs[#inputs + 1] = item
    end

    return {
        id        = id,
        output    = output,
        count     = count,
        type      = "craft",
        inputs    = inputs,
        shapeless = true,
    }
end

--- Convert a smelting / blasting / smoking JSON data table to a StorageOS recipe.
local function parseSmeltingRecipe(data, id, rtype)
    if not data.ingredient or not data.result then return nil end
    local output, count = resolveResult(data.result)
    if not output then return nil end
    local item = resolveIngredient(data.ingredient)
    if not item then return nil end

    return {
        id     = id,
        output = output,
        count  = count or 1,
        type   = rtype,
        inputs = { item },
        time   = data.cookingtime or 200,
    }
end

--- Convert a stonecutting JSON data table.
--- Treated as a shapeless 1-input crafting recipe.
local function parseStonecuttingRecipe(data, id)
    if not data.ingredient or not data.result then return nil end
    local output, count = resolveResult(data.result)
    if not output then return nil end
    local item = resolveIngredient(data.ingredient)
    if not item then return nil end

    return {
        id        = id,
        output    = output,
        count     = count or 1,
        type      = "craft",
        inputs    = { item },
        shapeless = true,
    }
end

-- Map of Minecraft recipe type string → parser function
local PARSERS = {
    ["minecraft:crafting_shaped"]    = parseShapedRecipe,
    ["minecraft:crafting_shapeless"] = parseShapelessRecipe,
    ["minecraft:smelting"]           = function(d, id) return parseSmeltingRecipe(d, id, "smelt") end,
    ["minecraft:blasting"]           = function(d, id) return parseSmeltingRecipe(d, id, "blast") end,
    ["minecraft:smoking"]            = function(d, id) return parseSmeltingRecipe(d, id, "smoke") end,
    ["minecraft:stonecutting"]       = parseStonecuttingRecipe,
    -- Smithing, special, and decorated-pot recipes are intentionally omitted
    -- as they cannot be automated by a storage turtle/workbench.
}

--- Parse a raw recipe JSON string into a StorageOS recipe table.
--- `filename` is used to derive the recipe id (e.g. "oak_planks.json" → "mc:oak_planks").
--- Returns a recipe table, or nil if the type is unsupported / ingredient unresolvable.
local function parseRecipeJSON(jsonStr, filename)
    local id = "mc:" .. (filename:match("^(.+)%.json$") or filename)

    local ok, data = pcall(textutils.unserialiseJSON, jsonStr)
    if not ok or type(data) ~= "table" then
        Logger.debug("RecipeFetcher: JSON parse error in '%s'", filename)
        return nil
    end

    local rtype  = data.type
    local parser = rtype and PARSERS[rtype]
    if not parser then
        -- Unsupported recipe type (smithing, special, etc.) – silently skip
        return nil
    end

    local recipe = parser(data, id)
    if not recipe then
        Logger.debug("RecipeFetcher: skipped '%s' (unresolvable ingredient or malformed)", filename)
    end
    return recipe
end

-- ── HTTP helpers ──────────────────────────────────────────────────────────────

local HTTP_HEADERS = { ["User-Agent"] = "StorageOS/1.1 CC:Tweaked" }

--- Synchronous HTTP GET.  Returns body string or nil + error string.
local function httpGet(url)
    if not http then return nil, "HTTP API unavailable" end
    local ok, handle = pcall(http.get, url, HTTP_HEADERS)
    if not ok or not handle then
        return nil, "Request failed: " .. tostring(handle)
    end
    if type(handle) == "string" then
        return nil, "Request failed: " .. handle
    end
    local code = handle.getResponseCode()
    if code ~= 200 then
        handle.close()
        return nil, "HTTP " .. tostring(code)
    end
    local body = handle.readAll()
    handle.close()
    return body
end

--- Asynchronous parallel HTTP GET for a list of URLs.
--- Fires all requests simultaneously, then waits for all to complete/fail.
--- `progressCb(completed, total)` is called after each response arrives.
--- Returns a table { [url] = body } for successful responses only.
local function httpGetBatch(urls, progressCb)
    local results = {}
    local pending = {}
    local done    = 0
    local total   = #urls

    -- Submit all requests at once
    for _, url in ipairs(urls) do
        http.request(url, nil, HTTP_HEADERS)
        pending[url] = true
    end

    -- Collect responses (interleaved with other events the scheduler may fire)
    while next(pending) do
        local event, url, handle = os.pullEvent()
        if event == "http_success" and pending[url] then
            pending[url] = nil
            results[url] = handle.readAll()
            handle.close()
            done = done + 1
            if progressCb then pcall(progressCb, done, total) end
        elseif event == "http_failure" and pending[url] then
            pending[url] = nil
            done = done + 1
            Logger.debug("RecipeFetcher: HTTP failure for %s", url)
            if progressCb then pcall(progressCb, done, total) end
        end
    end

    return results
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Return true when a recipe fetch is needed:
---   • the cache directory is empty / missing, OR
---   • the cached version differs from Config.MC_VERSION.
function RecipeFetcher.needsFetch(version)
    version = version or Config.MC_VERSION
    local meta, _ = Utils.loadTable(Config.RECIPE_FETCH_META)
    if not meta then return true end
    if meta.version ~= version then return true end
    -- Check cache dir actually has files
    local cacheDir = Config.RECIPE_FETCHED_DIR
    if not fs.exists(cacheDir) then return true end
    local files = fs.list(cacheDir)
    return #files == 0
end

--- Fetch the list of recipe filenames available in the mcmeta repo.
--- Uses the GitHub Contents API (1 HTTP request).
--- Returns an array of filename strings (e.g. "oak_planks.json"), or nil + err.
function RecipeFetcher.listRecipes(version)
    version = version or Config.MC_VERSION
    Logger.info("RecipeFetcher.listRecipes: querying MC %s branch…", version)
    local body, err = httpGet(contentsApiUrl(version))
    if not body then
        return nil, "Contents API failed: " .. tostring(err)
    end
    local ok, items = pcall(textutils.unserialiseJSON, body)
    if not ok or type(items) ~= "table" then
        return nil, "Contents API response unparseable"
    end
    local names = {}
    for _, item in ipairs(items) do
        if type(item) == "table" and type(item.name) == "string"
                and item.name:match("%.json$") then
            names[#names + 1] = item.name
        end
    end
    Logger.info("RecipeFetcher.listRecipes: found %d files", #names)
    return names
end

--- Fetch, parse, and cache all vanilla Minecraft recipes.
---
--- `version`    – Minecraft version string (default Config.MC_VERSION).
--- `progressCb` – optional function(done, total, phase) for UI feedback.
---
--- Returns { ok=bool, loaded=N, skipped=N, error=string }.
--- On success, all parsed recipes are added to the RecipeManager and
--- cached as .lua files in Config.RECIPE_FETCHED_DIR.
function RecipeFetcher.fetchAll(version, progressCb)
    version = version or Config.MC_VERSION

    if not http then
        return {
            ok = false, loaded = 0, skipped = 0,
            error = "HTTP API is disabled. Set http.enabled=true in computercraft-common.toml.",
        }
    end

    local function progress(done, total, phase)
        if progressCb then pcall(progressCb, done, total, phase) end
    end

    -- ── Phase 1: list recipe files ────────────────────────────────────────────
    progress(0, 1, "Querying recipe list…")
    local names, listErr = RecipeFetcher.listRecipes(version)
    if not names then
        return { ok = false, loaded = 0, skipped = 0, error = listErr }
    end
    local total = #names

    -- ── Phase 2: fetch recipe JSON files in parallel batches ──────────────────
    Utils.ensureDir(Config.RECIPE_FETCHED_DIR)

    local BATCH   = Config.RECIPE_FETCH_BATCH
    local loaded  = 0
    local skipped = 0
    local fetched = 0

    for batchStart = 1, total, BATCH do
        -- Build URL list for this batch
        local batchUrls = {}
        local urlToName = {}
        for j = batchStart, math.min(batchStart + BATCH - 1, total) do
            local fname = names[j]
            local url   = rawFileUrl(version, fname)
            batchUrls[#batchUrls + 1] = url
            urlToName[url] = fname
        end

        -- Parallel download
        local batchResults = httpGetBatch(batchUrls, function(bDone, _bTotal)
            fetched = (batchStart - 1) + bDone
            progress(fetched, total, "Fetching recipes")
        end)

        -- Parse and cache each downloaded recipe
        for url, body in pairs(batchResults) do
            local fname  = urlToName[url]
            local recipe = parseRecipeJSON(body, fname)
            if recipe then
                -- Cache to disk as a .lua file so it survives reboot
                local cachePath = Config.RECIPE_FETCHED_DIR .. "/"
                              .. fname:gsub("%.json$", ".lua")
                local f = fs.open(cachePath, "w")
                if f then
                    f.write("return " .. textutils.serialize(recipe))
                    f.close()
                end
                RM.add(recipe)
                loaded = loaded + 1
            else
                skipped = skipped + 1
            end
        end
    end

    -- ── Phase 3: write fetch metadata ─────────────────────────────────────────
    Utils.saveTable(Config.RECIPE_FETCH_META, {
        version   = version,
        fetchedAt = os.time(),
        loaded    = loaded,
        skipped   = skipped,
    })

    Logger.info("RecipeFetcher.fetchAll: version=%s loaded=%d skipped=%d",
        version, loaded, skipped)
    return { ok = true, loaded = loaded, skipped = skipped }
end

--- Load previously-fetched recipes from the disk cache.
--- Call this on every boot to avoid re-fetching from the network.
--- Returns the number of recipe files loaded.
function RecipeFetcher.loadCached()
    local cacheDir = Config.RECIPE_FETCHED_DIR
    if not fs.exists(cacheDir) then return 0 end

    local files = fs.list(cacheDir)
    local count = 0
    for _, fname in ipairs(files) do
        if fname:match("%.lua$") then
            local ok, result = pcall(dofile, cacheDir .. "/" .. fname)
            if ok and result then
                RM.add(result)
                count = count + 1
            end
        end
    end
    Logger.info("RecipeFetcher.loadCached: loaded %d cached recipes", count)
    return count
end

--- Return the fetch metadata table (version, fetchedAt, loaded, skipped)
--- or nil if the system has never fetched from the network.
function RecipeFetcher.fetchMeta()
    local meta, _ = Utils.loadTable(Config.RECIPE_FETCH_META)
    return meta
end

return RecipeFetcher
