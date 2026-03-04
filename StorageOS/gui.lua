-- StorageOS/gui.lua
-- Full terminal GUI for StorageOS.
--
-- Layout (standard 51×19 ComputerCraft terminal or Advanced Computer):
--
--  ┌─────────────────────────────────────────────────────┐
--  │  StorageOS v1.0.0          [time]    [status]        │  ← header
--  ├──────┬──────────┬───────────┬────────────┬──────────┤
--  │ Home │ Storage  │ Crafting  │ Processing │  Tasks   │  ← tabs
--  ├──────┴──────────┴───────────┴────────────┴──────────┤
--  │                                                     │
--  │   (page content area – varies by tab)               │
--  │                                                     │
--  ├─────────────────────────────────────────────────────┤
--  │ [Q]uit  [R]escan  [↑↓] navigate  [Enter] select    │  ← footer
--  └─────────────────────────────────────────────────────┘

local GUI = {}
GUI.__index = GUI

local Config     = require("StorageOS.config")
local Logger     = require("StorageOS.logger")
local Utils      = require("StorageOS.utils")
local Network    = require("StorageOS.network")
local Storage    = require("StorageOS.storage")
local Crafting   = require("StorageOS.crafting")
local Processing = require("StorageOS.processing")
local Tasks      = require("StorageOS.tasks")
local RM         = require("StorageOS.recipes.manager")

-- ── Terminal dimensions ───────────────────────────────────────────────────────
local W, H = term.getSize()

-- ── Tab definitions ───────────────────────────────────────────────────────────
local TABS = {
    { id = "home",       label = " Home "      },
    { id = "storage",    label = " Storage "   },
    { id = "crafting",   label = " Crafting "  },
    { id = "processing", label = " Processing "},
    { id = "tasks",      label = " Tasks "     },
    { id = "log",        label = " Log "       },
}
local currentTab  = 1   -- index into TABS
local scrollPos   = {}  -- per-tab scroll offset
local cursor      = {}  -- per-tab cursor row
local inputMode   = false
local inputBuffer = ""
local inputPrompt = ""
local inputCb     = nil

for i = 1, #TABS do
    scrollPos[i] = 0
    cursor[i]    = 1
end

-- ── Drawing helpers ───────────────────────────────────────────────────────────

local G = Config.GUI  -- colour shorthand

local function setColours(fg, bg)
    if term.isColour() then
        term.setTextColor(fg or G.BODY_FG)
        term.setBackgroundColor(bg or G.BODY_BG)
    end
end

local function clearLine(y, bg)
    bg = bg or G.BODY_BG
    term.setCursorPos(1, y)
    setColours(G.BODY_FG, bg)
    term.clearLine()
end

local function writeAt(x, y, text, fg, bg)
    term.setCursorPos(x, y)
    setColours(fg, bg)
    term.write(text)
end

local function hline(y, char, fg, bg)
    char = char or "─"
    writeAt(1, y, string.rep(char, W), fg or G.BORDER_FG, bg or G.BODY_BG)
end

-- ── Header (row 1) ────────────────────────────────────────────────────────────
local function drawHeader()
    clearLine(1, G.HEADER_BG)
    local title = Config.NAME .. " v" .. Config.VERSION
    writeAt(2, 1, title, G.HEADER_FG, G.HEADER_BG)
    local timeStr  = Utils.timeStr()
    local netCount = string.format("%d devs", Network.count())
    local right    = timeStr .. "  " .. netCount
    writeAt(W - #right, 1, right, G.HEADER_FG, G.HEADER_BG)
end

-- ── Tabs (row 2) ──────────────────────────────────────────────────────────────
local function drawTabs()
    clearLine(2, G.TAB_BG)
    local x = 1
    for i, tab in ipairs(TABS) do
        local fg = (i == currentTab) and G.TAB_SEL_FG or G.TAB_FG
        local bg = (i == currentTab) and G.TAB_SEL_BG or G.TAB_BG
        writeAt(x, 2, tab.label, fg, bg)
        x = x + #tab.label
    end
end

-- ── Footer (last row) ─────────────────────────────────────────────────────────
local function drawFooter()
    local y = H
    clearLine(y, G.TAB_BG)
    local hint = " [Q]uit [R]escan [Tab]switch [\x18\x19]scroll [Enter]select"
    writeAt(1, y, hint:sub(1, W), G.BORDER_FG, G.TAB_BG)
end

-- ── Content area bounds ───────────────────────────────────────────────────────
local CONTENT_TOP    = 3   -- first content row
local CONTENT_BOTTOM = H - 1  -- last content row (above footer)
local CONTENT_HEIGHT = CONTENT_BOTTOM - CONTENT_TOP + 1
local CONTENT_WIDTH  = W

-- ── Clear content area ────────────────────────────────────────────────────────
local function clearContent()
    for y = CONTENT_TOP, CONTENT_BOTTOM do
        clearLine(y, G.BODY_BG)
    end
end

-- ── Scrollable list renderer ──────────────────────────────────────────────────
-- `lines` is a list of { text, fg, bg } or plain strings.
-- `scroll` is the top-of-view index (1-based).
-- `cursorRow` is the highlighted row (absolute index into lines).
-- Returns the new (possibly clamped) cursor row.
local function drawList(lines, scroll, cursorRow)
    local visibleCount = CONTENT_HEIGHT - 2  -- leave room for borders
    scroll    = math.max(1, math.min(scroll, math.max(1, #lines - visibleCount + 1)))
    cursorRow = math.max(1, math.min(cursorRow, #lines))

    for i = 0, visibleCount - 1 do
        local lineIdx = scroll + i
        local y       = CONTENT_TOP + 1 + i
        if lineIdx <= #lines then
            local line = lines[lineIdx]
            local text, fg, bg
            if type(line) == "table" then
                text = line.text or ""
                fg   = line.fg   or G.BODY_FG
                bg   = line.bg   or G.BODY_BG
            else
                text = tostring(line)
                fg   = G.BODY_FG
                bg   = G.BODY_BG
            end
            if lineIdx == cursorRow then
                fg = G.TAB_SEL_FG
                bg = G.TAB_SEL_BG
            end
            clearLine(y, bg)
            writeAt(2, y, Utils.pad(text, CONTENT_WIDTH - 2), fg, bg)
        else
            clearLine(y, G.BODY_BG)
        end
    end

    -- Scroll indicator
    if #lines > visibleCount then
        local pct   = math.floor((scroll / (#lines - visibleCount + 1)) * (visibleCount - 2))
        local barY  = CONTENT_TOP + 2 + pct
        writeAt(W, barY, "\x95", G.BORDER_FG, G.BODY_BG)  -- block character
    end

    return cursorRow
end

-- ── Page renderers ────────────────────────────────────────────────────────────

local function renderHome()
    local items    = Storage.listAll()
    local itemCount = Utils.tableLen(items)
    local totalItems = 0
    for _, n in pairs(items) do totalItems = totalItems + n end
    local procStatus = Processing.status()
    local busyCount  = 0
    for _, p in ipairs(procStatus) do if p.busy then busyCount = busyCount + 1 end end
    local craftQueue = Crafting.getQueue()
    local taskList   = Tasks.list()

    local y = CONTENT_TOP
    -- Box
    writeAt(1, y, "┌" .. string.rep("─", W-2) .. "┐", G.BORDER_FG, G.BODY_BG)
    y = y + 1
    local function row(label, value, fg)
        writeAt(1, y, "│", G.BORDER_FG, G.BODY_BG)
        writeAt(3, y, Utils.pad(label, 22), G.DIM_FG, G.BODY_BG)
        writeAt(26, y, Utils.pad(tostring(value), W-27), fg or G.SUCCESS_FG, G.BODY_BG)
        writeAt(W, y, "│", G.BORDER_FG, G.BODY_BG)
        y = y + 1
    end

    row("Unique item types:",    itemCount)
    row("Total items stored:",   Utils.formatNumber(totalItems))
    row("Network peripherals:",  Network.count())
    row("Known recipes:",        RM.count())
    row("Active processors:",    #procStatus,              G.BODY_FG)
    row("Busy processors:",      busyCount,                busyCount > 0 and G.WARN_FG or G.SUCCESS_FG)
    row("Craft queue depth:",    #craftQueue,              #craftQueue > 0 and G.WARN_FG or G.SUCCESS_FG)
    row("Running tasks:",        #taskList,                G.BODY_FG)

    -- Separator
    writeAt(1, y, "├" .. string.rep("─", W-2) .. "┤", G.BORDER_FG, G.BODY_BG)
    y = y + 1

    -- Network summary
    writeAt(2, y, "Network: " .. Network.summary(), G.DIM_FG, G.BODY_BG)
    y = y + 1

    -- Pad to bottom border
    while y < CONTENT_BOTTOM do
        writeAt(1, y, "│", G.BORDER_FG, G.BODY_BG)
        writeAt(W, y, "│", G.BORDER_FG, G.BODY_BG)
        y = y + 1
    end
    writeAt(1, y, "└" .. string.rep("─", W-2) .. "┘", G.BORDER_FG, G.BODY_BG)
end

local function renderStorage()
    local items = Storage.sortedItems()
    local counts = Storage.listAll()
    local lines  = {}
    for _, name in ipairs(items) do
        local short = name:match(":(.+)$") or name
        local count = counts[name] or 0
        lines[#lines + 1] = {
            text = string.format("%-30s %8s", short, Utils.formatNumber(count)),
            fg   = G.BODY_FG,
        }
    end
    if #lines == 0 then
        lines[1] = { text = "  (no items in storage)", fg = G.DIM_FG }
    end
    -- Header
    clearLine(CONTENT_TOP, G.TAB_BG)
    writeAt(2, CONTENT_TOP,
        Utils.pad("Item", 30) .. Utils.pad("Count", 10),
        G.TAB_SEL_FG, G.TAB_BG)

    local tab = 2
    cursor[tab]    = drawList(lines, scrollPos[tab], cursor[tab])
    scrollPos[tab] = math.max(1, cursor[tab] - math.floor(CONTENT_HEIGHT / 2))
end

local function renderCrafting()
    local tab    = 3
    local queue  = Crafting.getQueue()
    local craftable = RM.craftableItems()
    local lines  = {}

    -- Section header
    lines[#lines + 1] = { text = "── Queued Jobs ──────────────────────────", fg = G.HIGHLIGHT }
    if #queue == 0 then
        lines[#lines + 1] = { text = "  (queue empty)", fg = G.DIM_FG }
    else
        for _, j in ipairs(queue) do
            local short = j.itemName:match(":(.+)$") or j.itemName
            lines[#lines + 1] = {
                text = string.format("  %-28s ×%-4d  [%s]", short, j.amount, j.status),
                fg   = j.status == "running" and G.WARN_FG or G.BODY_FG,
            }
        end
    end

    lines[#lines + 1] = { text = "", fg = G.BODY_FG }
    lines[#lines + 1] = { text = "── Craftable Items ──────────────────────", fg = G.HIGHLIGHT }
    for _, name in ipairs(craftable) do
        local short = name:match(":(.+)$") or name
        local have  = Storage.count(name)
        lines[#lines + 1] = {
            text = string.format("  %-30s (have %s)", short, Utils.formatNumber(have)),
            fg   = G.BODY_FG,
        }
    end
    if #craftable == 0 then
        lines[#lines + 1] = { text = "  (no recipes loaded)", fg = G.DIM_FG }
    end

    clearLine(CONTENT_TOP, G.TAB_BG)
    writeAt(2, CONTENT_TOP, Utils.pad("Crafting", W-2), G.TAB_SEL_FG, G.TAB_BG)
    cursor[tab]    = drawList(lines, scrollPos[tab], cursor[tab])
    scrollPos[tab] = math.max(1, cursor[tab] - math.floor(CONTENT_HEIGHT / 2))
end

local function renderProcessing()
    local tab    = 4
    local status = Processing.status()
    local queue  = Processing.getQueue()
    local lines  = {}

    lines[#lines + 1] = { text = "── Active Processors ────────────────────", fg = G.HIGHLIGHT }
    if #status == 0 then
        lines[#lines + 1] = { text = "  (no processors on network)", fg = G.DIM_FG }
    else
        for _, p in ipairs(status) do
            local busyStr = p.busy and ("  → " .. (p.job or p.recipe or "?")) or "  idle"
            local fg      = p.busy and G.WARN_FG or G.SUCCESS_FG
            lines[#lines + 1] = {
                text = string.format("  %-20s [%-14s] %s",
                    p.name:sub(1, 20), p.class, busyStr),
                fg = fg,
            }
        end
    end

    lines[#lines + 1] = { text = "", fg = G.BODY_FG }
    lines[#lines + 1] = { text = "── Job Queue ────────────────────────────", fg = G.HIGHLIGHT }
    if #queue == 0 then
        lines[#lines + 1] = { text = "  (queue empty)", fg = G.DIM_FG }
    else
        for _, j in ipairs(queue) do
            local short = j.itemName:match(":(.+)$") or j.itemName
            lines[#lines + 1] = {
                text = string.format("  %-28s ×%d", short, j.amount),
                fg   = G.BODY_FG,
            }
        end
    end

    clearLine(CONTENT_TOP, G.TAB_BG)
    writeAt(2, CONTENT_TOP, Utils.pad("Processing Machines", W-2), G.TAB_SEL_FG, G.TAB_BG)
    cursor[tab]    = drawList(lines, scrollPos[tab], cursor[tab])
    scrollPos[tab] = math.max(1, cursor[tab] - math.floor(CONTENT_HEIGHT / 2))
end

local function renderTasks()
    local tab   = 5
    local tlist = Tasks.list()
    local lines = {}

    if #tlist == 0 then
        lines[1] = { text = "  (no tasks)", fg = G.DIM_FG }
    else
        for _, t in ipairs(tlist) do
            local fg
            if t.status == "running" then fg = G.SUCCESS_FG
            elseif t.status == "crashed" then fg = G.ERROR_FG
            elseif t.status == "done"    then fg = G.DIM_FG
            else                              fg = G.BODY_FG
            end
            lines[#lines + 1] = {
                text = string.format("  [%3d] %-20s  p=%d  %s",
                    t.id, t.name:sub(1, 20), t.priority, t.status),
                fg = fg,
            }
        end
    end

    clearLine(CONTENT_TOP, G.TAB_BG)
    writeAt(2, CONTENT_TOP, Utils.pad("Background Tasks", W-2), G.TAB_SEL_FG, G.TAB_BG)
    cursor[tab]    = drawList(lines, scrollPos[tab], cursor[tab])
    scrollPos[tab] = math.max(1, cursor[tab] - math.floor(CONTENT_HEIGHT / 2))
end

local function renderLog()
    local tab   = 6
    local lines = Logger.getRecent(CONTENT_HEIGHT - 2)
    local richLines = {}
    for _, entry in ipairs(lines) do
        local fg = G.BODY_FG
        if entry:find("%[ERROR%]") then fg = G.ERROR_FG
        elseif entry:find("%[WARN%]")  then fg = G.WARN_FG
        elseif entry:find("%[DEBUG%]") then fg = G.DIM_FG
        end
        richLines[#richLines + 1] = { text = entry, fg = fg }
    end
    if #richLines == 0 then
        richLines[1] = { text = "  (no log entries)", fg = G.DIM_FG }
    end

    clearLine(CONTENT_TOP, G.TAB_BG)
    writeAt(2, CONTENT_TOP, Utils.pad("System Log", W-2), G.TAB_SEL_FG, G.TAB_BG)
    -- Auto-scroll to bottom
    scrollPos[tab] = math.max(1, #richLines - (CONTENT_HEIGHT - 4))
    cursor[tab]    = #richLines
    drawList(richLines, scrollPos[tab], cursor[tab])
end

-- ── Input modal ───────────────────────────────────────────────────────────────
local function drawInputModal(prompt, buffer)
    local y  = math.floor(H / 2)
    local mW = math.min(W - 4, 50)
    local x  = math.floor((W - mW) / 2)

    -- Box
    writeAt(x, y-1, "┌" .. string.rep("─", mW-2) .. "┐", G.BORDER_FG, G.BODY_BG)
    writeAt(x, y,   "│ " .. Utils.pad(prompt, mW-4) .. " │", G.BODY_FG, G.BODY_BG)
    writeAt(x, y+1, "│ > " .. Utils.pad(buffer, mW-5) .. "│", G.INPUT_FG, G.INPUT_BG)
    writeAt(x, y+2, "└" .. string.rep("─", mW-2) .. "┘", G.BORDER_FG, G.BODY_BG)
    term.setCursorPos(x + 4 + #buffer, y + 1)
    term.setCursorBlink(true)
end

-- ── Main draw ─────────────────────────────────────────────────────────────────

local function draw()
    clearContent()
    local tab = TABS[currentTab]
    if     tab.id == "home"       then renderHome()
    elseif tab.id == "storage"    then renderStorage()
    elseif tab.id == "crafting"   then renderCrafting()
    elseif tab.id == "processing" then renderProcessing()
    elseif tab.id == "tasks"      then renderTasks()
    elseif tab.id == "log"        then renderLog()
    end
    drawHeader()
    drawTabs()
    drawFooter()
    if inputMode then
        drawInputModal(inputPrompt, inputBuffer)
    end
end

-- ── Input handling ────────────────────────────────────────────────────────────

local function startInput(prompt, cb)
    inputMode   = true
    inputBuffer = ""
    inputPrompt = prompt
    inputCb     = cb
    term.setCursorBlink(true)
end

local function handleInputKey(key, char)
    if key == keys.enter then
        inputMode = false
        term.setCursorBlink(false)
        if inputCb then
            pcall(inputCb, inputBuffer)
        end
        inputBuffer = ""
        inputCb     = nil
    elseif key == keys.backspace then
        if #inputBuffer > 0 then
            inputBuffer = inputBuffer:sub(1, -2)
        end
    elseif key == keys.escape then
        inputMode   = false
        inputBuffer = ""
        inputCb     = nil
        term.setCursorBlink(false)
    elseif char then
        inputBuffer = inputBuffer .. char
    end
end

-- Tab-specific Enter action
local function handleEnter()
    local tab = TABS[currentTab]
    if tab.id == "crafting" then
        -- Get craftable items list
        local craftable = RM.craftableItems()
        local idx = cursor[3]
        -- Account for the header lines in the list (2 for "Queued Jobs" section)
        -- This is simplified; a production implementation would track line→item mapping
        local queueLines = #Crafting.getQueue()
        local headerOffset = 3 + queueLines + (queueLines == 0 and 1 or 0) + 2
        local itemIdx = idx - headerOffset
        if itemIdx >= 1 and itemIdx <= #craftable then
            local itemName = craftable[itemIdx]
            startInput("Craft how many " .. (itemName:match(":(.+)$") or itemName) .. "?",
                function(s)
                    local n = tonumber(s)
                    if n and n > 0 then
                        Crafting.queue(itemName, n)
                        Logger.info("GUI: queued craft %d × %s", n, itemName)
                    end
                end)
        end
    elseif tab.id == "processing" then
        -- Queue smelting job for selected item
        startInput("Smelt item name (e.g. minecraft:raw_iron):",
            function(s)
                s = Utils.trim(s)
                if s ~= "" then
                    startInput("Amount?", function(amtStr)
                        local n = tonumber(amtStr) or 1
                        Processing.queue(s, n)
                        Logger.info("GUI: queued process %d × %s", n, s)
                    end)
                end
            end)
    end
end

-- ── Public API ────────────────────────────────────────────────────────────────

--- Main GUI loop.  Runs forever, handling terminal events.
--- Call from a task/coroutine.
function GUI.run()
    term.clear()
    draw()

    -- Schedule a periodic refresh timer so the display stays current even
    -- when no keyboard/mouse events are fired.
    local refreshTimer = os.startTimer(Config.GUI_REFRESH)

    while true do
        local event, p1, p2, p3 = os.pullEvent()

        if inputMode then
            if event == "key" then
                handleInputKey(p1, nil)
            elseif event == "char" then
                handleInputKey(nil, p1)
            end
            draw()

        elseif event == "key" then
            local key = p1
            if key == keys.q or key == keys.leftCtrl then
                -- Quit / shutdown signal: return to let core.lua handle it
                return
            elseif key == keys.r then
                Network.scan()
                Storage.scan()
                Processing.scan()
                Logger.info("GUI: manual rescan triggered")
            elseif key == keys.tab then
                currentTab = (currentTab % #TABS) + 1
            elseif key == keys.left then
                currentTab = ((currentTab - 2 + #TABS) % #TABS) + 1
            elseif key == keys.right then
                currentTab = (currentTab % #TABS) + 1
            elseif key == keys.up then
                if cursor[currentTab] > 1 then
                    cursor[currentTab] = cursor[currentTab] - 1
                end
            elseif key == keys.down then
                cursor[currentTab] = cursor[currentTab] + 1
            elseif key == keys.pageUp then
                cursor[currentTab] = math.max(1, cursor[currentTab] - CONTENT_HEIGHT)
            elseif key == keys.pageDown then
                cursor[currentTab] = cursor[currentTab] + CONTENT_HEIGHT
            elseif key == keys.enter then
                handleEnter()
            end
            draw()

        elseif event == "timer" then
            -- Reschedule our own refresh timer so the GUI keeps ticking
            if p1 == refreshTimer then
                refreshTimer = os.startTimer(Config.GUI_REFRESH)
            end
            draw()

        elseif event == "peripheral" or event == "peripheral_detach" then
            Network.handleEvent(event, p1)
            draw()

        elseif event == "term_resize" then
            W, H = term.getSize()
            CONTENT_HEIGHT = H - CONTENT_TOP - 1
            draw()

        elseif event == "mouse_click" then
            local button, mx, my = p1, p2, p3
            -- Tab click
            if my == 2 then
                local x = 1
                for i, tab in ipairs(TABS) do
                    if mx >= x and mx < x + #tab.label then
                        currentTab = i
                        break
                    end
                    x = x + #tab.label
                end
            end
            draw()

        elseif event == "mouse_scroll" then
            local dir = p1
            if dir > 0 then
                cursor[currentTab] = cursor[currentTab] + 1
            else
                cursor[currentTab] = math.max(1, cursor[currentTab] - 1)
            end
            draw()
        end
    end
end

--- Trigger a single GUI redraw (call from other tasks).
function GUI.refresh()
    draw()
end

return GUI
