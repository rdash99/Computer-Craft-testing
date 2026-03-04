-- StorageOS/core.lua
-- Main entry point for StorageOS.
-- Wires all modules together and starts the parallel task scheduler.
--
-- Module load order (respects dependencies):
--   config → utils → logger → network → storage → recipes → crafting → processing → tasks → gui

-- ── Package path setup ────────────────────────────────────────────────────────
-- Allow require("StorageOS.xxx") and require("StorageOS.recipes.yyy")
local function addPath(p)
    if not package.path:find(p, 1, true) then
        package.path = p .. ";" .. package.path
    end
end
addPath("/?.lua")
addPath("/?/init.lua")

-- ── Module loading ────────────────────────────────────────────────────────────
local Config        = require("StorageOS.config")
local Utils         = require("StorageOS.utils")
local Logger        = require("StorageOS.logger")
local Network       = require("StorageOS.network")
local Storage       = require("StorageOS.storage")
local RM            = require("StorageOS.recipes.manager")
local RecipeFetcher = require("StorageOS.recipe_fetcher")
local Crafting      = require("StorageOS.crafting")
local Processing    = require("StorageOS.processing")
local Tasks         = require("StorageOS.tasks")
local GUI           = require("StorageOS.gui")

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function colour(c)
    if term.isColour() then term.setTextColor(c) end
end

local function println(msg, c)
    colour(c or colors.white)
    print(msg)
end

-- ── Recipe loading ────────────────────────────────────────────────────────────

--- Load recipes at startup.
--- Strategy (in order of preference):
---   1. Load cached game recipes from disk (fast, works offline)
---   2. If no cache, attempt live fetch from misode/mcmeta (requires HTTP)
---   3. If HTTP unavailable, fall back to the bundled defaults.lua
local function loadRecipes()
    println("Loading recipes…", colors.white)
    Utils.ensureDir(Config.RECIPE_DIR)
    Utils.ensureDir(Config.RECIPE_FETCHED_DIR)

    -- ── Try disk cache first ──────────────────────────────────────────────────
    local cached = RecipeFetcher.loadCached()
    if cached > 0 then
        local meta = RecipeFetcher.fetchMeta()
        local verStr = meta and (" (MC " .. (meta.version or "?") .. ")") or ""
        println(string.format("  Loaded %d recipes from cache%s", cached, verStr), colors.lime)
        Logger.info("Recipes: %d loaded from disk cache%s", cached, verStr)

        -- Also load any user-defined recipe files from the main recipes dir
        RM.loadFromDisk()
        Logger.info("Recipes total: %d", RM.count())
        return
    end

    -- ── No cache – attempt live fetch ─────────────────────────────────────────
    if http then
        println("  No cached recipes – fetching from game data…", colors.yellow)
        println(string.format("  Source: github.com/misode/mcmeta (MC %s)", Config.MC_VERSION),
                colors.gray)
        println("  This may take a few minutes on the first run.", colors.gray)

        local W = term.getSize()
        local lastPhase = ""
        local barY = select(2, term.getCursorPos()) + 1

        local function progress(done, total, phase)
            if phase ~= lastPhase then
                lastPhase = phase
                println("  " .. phase, colors.cyan)
                barY = select(2, term.getCursorPos())
            end
            -- Simple inline progress bar
            local pct = total > 0 and math.floor((done / total) * (W - 14)) or 0
            term.setCursorPos(1, barY)
            colour(colors.gray)
            io.write(string.format("  [%-" .. (W-14) .. "s] %4d/%d",
                string.rep("=", pct), done, total))
        end

        local result = RecipeFetcher.fetchAll(Config.MC_VERSION, progress)
        println("")  -- newline after progress bar

        if result.ok then
            println(string.format("  Fetched %d recipes (%d skipped)",
                result.loaded, result.skipped), colors.lime)
            Logger.info("Recipes fetched: loaded=%d skipped=%d", result.loaded, result.skipped)
        else
            println("  Fetch failed: " .. tostring(result.error), colors.red)
            println("  Falling back to built-in defaults.", colors.yellow)
            Logger.warn("Recipe fetch failed: %s – using defaults", result.error)
            local defaults = require("StorageOS.recipes.defaults")
            RM.add(defaults)
        end
    else
        -- ── HTTP unavailable – use bundled defaults ────────────────────────────
        println("  HTTP API unavailable – using built-in recipe defaults.", colors.yellow)
        println("  Enable HTTP in computercraft-common.toml for live recipe data.", colors.gray)
        Logger.warn("HTTP unavailable – loading default recipes only")
        local defaults = require("StorageOS.recipes.defaults")
        RM.add(defaults)
    end

    -- Load any user-added .lua recipe files from the main recipes directory
    RM.loadFromDisk()
    Logger.info("Recipes total: %d", RM.count())
end

-- ── Startup ───────────────────────────────────────────────────────────────────

local function startup()
    term.clear()
    term.setCursorPos(1, 1)
    colour(colors.cyan)
    print(string.format("  %s v%s  starting…", Config.NAME, Config.VERSION))
    colour(colors.white)
    print("")

    Utils.ensureDir(Config.DATA_DIR)
    Logger.info("=== %s v%s starting ===", Config.NAME, Config.VERSION)

    -- Load recipes (fetch from game data or disk cache)
    loadRecipes()

    -- Scan the peripheral network
    print("")
    println("Scanning network…", colors.white)
    Network.scan()
    Logger.info("Network: %d peripherals found", Network.count())

    -- Register attach/detach callbacks so hot-plug updates processors
    Network.onAttach(function(info) Processing.onAttach(info) end)
    Network.onDetach(function(info) Processing.onDetach(info) end)

    -- Scan storage and processors
    println("Scanning storage…", colors.white)
    Storage.scan()

    println("Scanning processors…", colors.white)
    Processing.scan()

    Logger.info("Startup complete. %d recipes, %d peripherals.",
        RM.count(), Network.count())
    sleep(0.8)
    term.clear()
end

-- ── Background tasks ──────────────────────────────────────────────────────────

--- Periodically rescan the network for new/removed peripherals.
local function networkScanTask()
    while true do
        sleep(Config.SCAN_INTERVAL)
        Network.scan()
        Logger.debug("networkScanTask: scan complete (%d peripherals)", Network.count())
    end
end

--- Periodically pull items from input chests into storage.
local function ingestTask()
    while true do
        sleep(Config.RESTOCK_INTERVAL)
        local ingested = Storage.ingestAllInputs()
        local count    = Utils.tableLen(ingested)
        if count > 0 then
            Logger.info("ingestTask: ingested %d item type(s) from inputs", count)
        end
    end
end

--- Periodically update furnace/processor status and collect finished output.
local function processingTickTask()
    while true do
        sleep(Config.FURNACE_INTERVAL)
        Processing.tick()
        Processing.dispatch()
    end
end

--- Process one entry from the craft queue each cycle.
local function craftQueueTask()
    while true do
        Crafting.processQueue()
        sleep(Config.TASK_TICK * 10)  -- 0.5 s between craft attempts
    end
end

--- Periodically refresh the storage index (handles external changes).
local function storageRefreshTask()
    while true do
        sleep(Config.SCAN_INTERVAL * 2)
        Storage.scan()
        Logger.debug("storageRefreshTask: storage index refreshed")
    end
end

-- ── Main ──────────────────────────────────────────────────────────────────────

local function main()
    startup()

    -- Register all background tasks
    Tasks.add("network_scan",     networkScanTask,    Config.TASK_PRIORITY.LOW)
    Tasks.add("ingest",           ingestTask,         Config.TASK_PRIORITY.HIGH)
    Tasks.add("processing_tick",  processingTickTask, Config.TASK_PRIORITY.NORMAL)
    Tasks.add("craft_queue",      craftQueueTask,     Config.TASK_PRIORITY.NORMAL)
    Tasks.add("storage_refresh",  storageRefreshTask, Config.TASK_PRIORITY.IDLE)
    Tasks.add("gui",              GUI.run,            Config.TASK_PRIORITY.CRITICAL)

    Logger.info("Starting task scheduler with %d tasks", #Tasks.list())
    Tasks.run()

    -- If Tasks.run() returns (e.g. GUI exited), do a clean shutdown
    Logger.info("All tasks exited – shutting down.")
    term.clear()
    term.setCursorPos(1, 1)
    colour(colors.yellow)
    print(Config.NAME .. " has stopped.")
    colour(colors.white)
end

-- ── Error handling ────────────────────────────────────────────────────────────
local ok, err = xpcall(main, function(e)
    return e .. "\n" .. debug.traceback()
end)

if not ok then
    colour(colors.red)
    printError("\n=== " .. Config.NAME .. " FATAL ERROR ===")
    printError(tostring(err))
    colour(colors.white)
    print("\nPress any key to reboot…")
    os.pullEvent("key")
    os.reboot()
end

