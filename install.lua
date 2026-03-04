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
    "StorageOS/storage.lua",
    "StorageOS/tasks.lua",
    "StorageOS/utils.lua",
    "StorageOS/recipes/manager.lua",
    "StorageOS/recipes/defaults.lua",
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
    if fail_count == 0 then
        colour(colors.lime)
        print("  ✓ All " .. ok_count .. " files installed successfully!")
        colour(colors.white)
    else
        colour(colors.yellow)
        print(string.format("  Installed: %d   Failed: %d", ok_count, fail_count))
        colour(colors.red)
        for _, f in ipairs(failures) do print("  • " .. f) end
        colour(colors.white)
    end

    print("")

    if fail_count == 0 then
        -- Ask to launch StorageOS immediately
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
