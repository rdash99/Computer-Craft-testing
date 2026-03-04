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
local RecipeScanner = require("StorageOS.recipe_scanner")
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

--- Run the local recipe scanner and report results.
--- Called at startup and whenever the user requests a re-scan (GUI 'F' key).
local function loadRecipes()
    println("Scanning for recipes…", colors.white)

    local function progress(source, n)
        if n > 0 then
            local labels = {
                rs       = "Refined Storage",
                me       = "Applied Energistics 2",
                generic  = "Peripheral API",
                json     = "Local JSON files",
                defaults = "Built-in defaults",
            }
            println(string.format("  %-26s  +%d", labels[source] or source, n), colors.gray)
        end
    end

    local summary = RecipeScanner.scan(progress)

    -- Also load any hand-crafted .lua recipe files the user placed in RECIPE_DIR
    RM.loadFromDisk()

    local total = RM.count()
    if total > 0 then
        println(string.format("  Total: %d recipes loaded", total), colors.lime)
    else
        println("  Warning: no recipes loaded.", colors.yellow)
    end
    Logger.info("loadRecipes complete: %d recipes", total)
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
    Utils.ensureDir(Config.RECIPE_DIR)
    for _, dir in ipairs(Config.RECIPE_DATA_DIRS or {}) do
        Utils.ensureDir(dir)
    end

    Logger.info("=== %s v%s starting ===", Config.NAME, Config.VERSION)

    -- Discover recipes from local sources (peripherals + JSON files + defaults)
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

--- Periodically re-run the recipe scanner so newly-connected peripherals
--- (RS/ME bridges added after boot) get their recipes loaded automatically.
local function recipeScanTask()
    while true do
        sleep(Config.SCAN_INTERVAL * 3)  -- every 90 s
        local prevCount = RM.count()
        RecipeScanner.scan()
        RM.loadFromDisk()
        local newCount = RM.count()
        if newCount ~= prevCount then
            Logger.info("recipeScanTask: recipe count changed %d → %d", prevCount, newCount)
        end
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
    Tasks.add("recipe_scan",      recipeScanTask,     Config.TASK_PRIORITY.IDLE)
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

