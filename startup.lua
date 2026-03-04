-- startup.lua
-- ComputerCraft auto-start file.
-- Place this file in the root of the ComputerCraft computer (/) alongside the
-- StorageOS/ directory.  The computer will execute it automatically on boot.

-- Ensure the StorageOS directory is present
if not fs.exists("/StorageOS/core.lua") then
    term.setTextColor(colors.red)
    print("ERROR: StorageOS not found!")
    print("Please place the StorageOS/ folder in the computer's root directory.")
    term.setTextColor(colors.white)
    return
end

-- Set up package path so that require("StorageOS.xxx") works from any module
package.path = "/?.lua;/?/init.lua;" .. (package.path or "")

-- Hand off to the core
local ok, err = pcall(dofile, "/StorageOS/core.lua")
if not ok then
    term.setTextColor(colors.red)
    printError("StorageOS startup error: " .. tostring(err))
    term.setTextColor(colors.white)
    print("Press any key to reboot…")
    os.pullEvent("key")
    os.reboot()
end
