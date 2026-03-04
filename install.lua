-- install.lua
-- StorageOS Installer for CC:Tweaked
--
-- Automatically downloads all StorageOS files from GitHub and places them in
-- the correct directory structure on this computer.
--
-- ── Usage ─────────────────────────────────────────────────────────────────────
--
--   Step 1 (only needed once – to get this installer):
--     wget https://raw.githubusercontent.com/rdash99/Computer-Craft-testing/main/install.lua
--
--   Step 2:
--     install
--
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Configuration ──────────────────────────────────────────────────────────────
-- Change BRANCH to "main" (or another branch/tag/commit) as needed.
local REPO   = "rdash99/Computer-Craft-testing"
local BRANCH = "main"

-- Full list of files to download, relative to the repo root.
-- This list mirrors the StorageOS directory structure exactly.
local FILES = {
    "startup.lua",
    "StorageOS/config.lua",
    "StorageOS/core.lua",
    "StorageOS/crafting.lua",
    "StorageOS/gui.lua",
    "StorageOS/logger.lua",
    "StorageOS/network.lua",
    "StorageOS/processing.lua",
    "StorageOS/recipe_scanner.lua",
    "StorageOS/storage.lua",
    "StorageOS/tasks.lua",
    "StorageOS/utils.lua",
    "StorageOS/recipes/manager.lua",
    "StorageOS/recipes/defaults.lua",
}

-- Directories to create after downloading files.
-- These are used by StorageOS at runtime.
local DIRS = {
    "/StorageOS/data",
    "/StorageOS/recipes",
    "/StorageOS/recipes/data",  -- drop Minecraft recipe JSON files here
    "/recipes",                  -- root-level shortcut for recipe JSON files
}

-- ── Helpers ────────────────────────────────────────────────────────────────────

local BASE_URL = "https://raw.githubusercontent.com/" .. REPO .. "/" .. BRANCH .. "/"

local function colour(c)
    if term.isColour() then term.setTextColor(c) end
end

local function print_ok(msg)
    colour(colors.lime)
    print("  [OK] " .. msg)
    colour(colors.white)
end

local function print_err(msg)
    colour(colors.red)
    print("  [!!] " .. msg)
    colour(colors.white)
end

local function print_info(msg)
    colour(colors.cyan)
    print("  --> " .. msg)
    colour(colors.white)
end

--- Download a single URL and return its text body, or nil + error string.
local function fetch(url)
    if not http then
        return nil, "HTTP API is disabled. Enable it in ComputerCraft config."
    end
    local ok, handle = pcall(http.get, url)
    if not ok or not handle then
        return nil, "HTTP request failed for: " .. url
    end
    local code = handle.getResponseCode()
    if code ~= 200 then
        handle.close()
        return nil, string.format("HTTP %d for %s", code, url)
    end
    local body = handle.readAll()
    handle.close()
    return body
end

--- Write `content` to `path`, creating parent directories as needed.
local function writeFile(path, content)
    local dir = fs.getDir(path)
    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end
    local f = fs.open(path, "w")
    if not f then return false, "Cannot open " .. path end
    f.write(content)
    f.close()
    return true
end

-- ── Main installer ─────────────────────────────────────────────────────────────

local function main()
    -- Header
    colour(colors.yellow)
    print("╔══════════════════════════════════════╗")
    print("║    StorageOS Installer for CC:T      ║")
    print("╚══════════════════════════════════════╝")
    colour(colors.white)
    print("")
    print_info("Repo   : " .. REPO)
    print_info("Branch : " .. BRANCH)
    print("")

    -- Check for HTTP API
    if not http then
        print_err("The HTTP API is not available.")
        print("Enable it in computercraft-common.toml:")
        print("  [http] enabled = true")
        return
    end

    -- Confirm
    colour(colors.white)
    write("Download " .. #FILES .. " files? [Y/n] ")
    local answer = read()
    if answer:lower() == "n" then
        print("Aborted.")
        return
    end
    print("")

    -- Download each file
    local ok_count   = 0
    local fail_count = 0
    local failures   = {}

    for i, relPath in ipairs(FILES) do
        local url    = BASE_URL .. relPath
        local dest   = "/" .. relPath
        colour(colors.gray)
        io.write(string.format("  [%2d/%2d] %-45s ", i, #FILES, relPath))
        colour(colors.white)

        -- Skip if file exists and user hasn't asked to overwrite
        -- (first pass we always download – overwriting is safe and ensures up-to-date)
        local body, err = fetch(url)
        if body then
            local written, werr = writeFile(dest, body)
            if written then
                colour(colors.lime)
                print("OK")
                colour(colors.white)
                ok_count = ok_count + 1
            else
                colour(colors.red)
                print("WRITE FAIL")
                colour(colors.white)
                fail_count = fail_count + 1
                failures[#failures + 1] = relPath .. " – " .. tostring(werr)
            end
        else
            colour(colors.red)
            print("FETCH FAIL")
            colour(colors.white)
            fail_count = fail_count + 1
            failures[#failures + 1] = relPath .. " – " .. tostring(err)
        end
    end

    -- Summary
    print("")
    if fail_count > 0 then
        colour(colors.yellow)
        print(string.format("  Installed: %d   Failed: %d", ok_count, fail_count))
        colour(colors.red)
        for _, f in ipairs(failures) do print("  • " .. f) end
        colour(colors.white)
    end

    print("")

    if fail_count == 0 then
        -- Create runtime directories
        print("")
        colour(colors.cyan)
        print("Creating directories…")
        colour(colors.white)
        for _, dir in ipairs(DIRS) do
            if not fs.exists(dir) then
                fs.makeDir(dir)
                colour(colors.gray)
                print("  created " .. dir)
                colour(colors.white)
            end
        end

        -- Write a README into the recipe data directory so the user knows it's there
        local readmePath = "/StorageOS/recipes/data/README.txt"
        if not fs.exists(readmePath) then
            local f = fs.open(readmePath, "w")
            if f then
                f.write(
                    "StorageOS – Recipe Data Directory\n" ..
                    "==================================\n\n" ..
                    "Drop Minecraft datapack recipe JSON files here and StorageOS\n" ..
                    "will load them automatically on the next scan (press F in the\n" ..
                    "Crafting tab, or reboot).\n\n" ..
                    "Supported recipe types:\n" ..
                    "  minecraft:crafting_shaped\n" ..
                    "  minecraft:crafting_shapeless\n" ..
                    "  minecraft:smelting\n" ..
                    "  minecraft:blasting\n" ..
                    "  minecraft:smoking\n" ..
                    "  minecraft:stonecutting\n\n" ..
                    "Recipes are also loaded automatically from connected\n" ..
                    "Refined Storage (rsBridge) and Applied Energistics 2\n" ..
                    "(meBridge) peripherals via Advanced Peripherals.\n"
                )
                f.close()
            end
        end

        print("")
        colour(colors.lime)
        print("  ✓ All " .. ok_count .. " files installed successfully!")
        colour(colors.white)
        print("")
        colour(colors.cyan)
        print("  Recipe discovery (automatic, no internet needed):")
        colour(colors.white)
        print("  • If you have Refined Storage + Advanced Peripherals,")
        print("    connect an rsBridge and StorageOS reads all RS patterns.")
        print("  • If you have AE2 + Advanced Peripherals,")
        print("    connect an meBridge and StorageOS reads AE2 craftables.")
        print("  • Drop Minecraft recipe JSON files into:")
        colour(colors.yellow)
        print("      /StorageOS/recipes/data/")
        colour(colors.white)
        print("    for any other mod recipes.")
        print("  • Press F in the Crafting tab to re-scan at any time.")
        print("")
        write("Launch StorageOS now? [Y/n] ")
        local launch = read()
        if launch:lower() ~= "n" then
            print("")
            colour(colors.cyan)
            print("Starting StorageOS…")
            colour(colors.white)
            sleep(0.5)
            dofile("/startup.lua")
        else
            print("Reboot the computer to start StorageOS automatically.")
        end
    else
        colour(colors.red)
        print("Some files failed to download.")
        colour(colors.white)
        print("Check your HTTP settings and try again.")
        print("Tip: set http.whitelist = [\"raw.githubusercontent.com\"] in config.")
    end
end

-- Run with error protection
local ok, err = pcall(main)
if not ok then
    colour(colors.red)
    print("\nInstaller error: " .. tostring(err))
    colour(colors.white)
end
