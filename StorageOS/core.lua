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
local Config     = require("StorageOS.config")
local Utils      = require("StorageOS.utils")
local Logger     = require("StorageOS.logger")
local Network    = require("StorageOS.network")
local Storage    = require("StorageOS.storage")
local RM         = require("StorageOS.recipes.manager")
local Crafting   = require("StorageOS.crafting")
local Processing = require("StorageOS.processing")
local Tasks      = require("StorageOS.tasks")
local GUI        = require("StorageOS.gui")

-- ── Startup ───────────────────────────────────────────────────────────────────

local function startup()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.cyan)
    print(string.format("Starting %s v%s…", Config.NAME, Config.VERSION))
    term.setTextColor(colors.white)

    -- Ensure data directories exist
    Utils.ensureDir(Config.DATA_DIR)
    Utils.ensureDir(Config.RECIPE_DIR)

    Logger.info("=== %s v%s starting ===", Config.NAME, Config.VERSION)

    -- Load recipes from disk (defaults.lua is always loaded first)
    print("Loading recipes…")
    local defaults = require("StorageOS.recipes.defaults")
    RM.add(defaults)

    -- On first boot, persist all built-in recipes to the recipe directory so:
    --   a) players can inspect/edit them without touching Lua source, and
    --   b) any future loadFromDisk() call will pick them up automatically.
    local firstBootFlag = Config.DATA_DIR .. "/recipes_initialized"
    if not fs.exists(firstBootFlag) then
        print("First boot: saving default recipes to disk…")
        local saved = 0
        for _, id in ipairs(RM.allIds()) do
            if RM.saveToDisk(RM.byId(id)) then
                saved = saved + 1
            end
        end
        -- Write flag so this only runs once
        local flag = fs.open(firstBootFlag, "w")
        if flag then flag.write(tostring(saved)); flag.close() end
        Logger.info("First boot: saved %d default recipes to %s", saved, Config.RECIPE_DIR)
        print(string.format("  Saved %d recipes to %s", saved, Config.RECIPE_DIR))
    end

    -- Load any user-added recipe files from disk (skips files already registered)
    RM.loadFromDisk()
    Logger.info("Recipes: %d loaded", RM.count())

    -- Initial network scan
    print("Scanning network…")
    Network.scan()
    Logger.info("Network: %d peripherals found", Network.count())

    -- Register attach/detach callbacks
    Network.onAttach(function(info)
        Processing.onAttach(info)
    end)
    Network.onDetach(function(info)
        Processing.onDetach(info)
    end)

    -- Initial storage scan
    print("Scanning storage…")
    Storage.scan()

    -- Initial processing scan
    print("Scanning processors…")
    Processing.scan()

    Logger.info("Startup complete.")
    sleep(0.5)
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
    term.setTextColor(colors.yellow)
    print(Config.NAME .. " has stopped.")
    term.setTextColor(colors.white)
end

-- ── Error handling ────────────────────────────────────────────────────────────
local ok, err = xpcall(main, function(e)
    return e .. "\n" .. debug.traceback()
end)

if not ok then
    term.setTextColor(colors.red)
    printError("\n=== " .. Config.NAME .. " FATAL ERROR ===")
    printError(tostring(err))
    term.setTextColor(colors.white)
    print("\nPress any key to reboot…")
    os.pullEvent("key")
    os.reboot()
end
