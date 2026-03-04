# StorageOS — ComputerCraft Storage Management System

A fully-featured Lua program for the **CC:Tweaked** (ComputerCraft) Minecraft mod that turns any Advanced Computer into an intelligent, automated storage and crafting controller.

---

## Features

| Feature | Details |
|---|---|
| **Unified Storage** | Tracks every item across all connected inventories in a single indexed view |
| **Priority System** | Storage Drawers → Barrels → Chests (configurable, higher priority filled first) |
| **Auto-Ingest** | Polls designated input chests and automatically stores their contents |
| **Auto-Export** | Push items to output chests on demand |
| **Crafting** | Shaped & shapeless crafting via a crafting turtle or workbench peripheral |
| **Dynamic Recipes** | Add/remove recipes at runtime; user recipes saved to `/StorageOS/recipes/` |
| **Multi-Furnace** | Distributes smelting jobs across all furnaces, smokers, and blast furnaces |
| **Create Support** | Recognises Create mod basins, presses, mixers, funnels, and vaults |
| **Parallel Tasks** | All background work (ingest, scan, smelting tick, craft queue) runs concurrently via `parallel.waitForAll` |
| **GUI** | Tabbed terminal interface — Home, Storage, Crafting, Processing, Tasks, Log |
| **Hot-Plug** | Detects peripherals added/removed while the system is running |
| **Logging** | Ring-buffer log viewable in the GUI; also written to `/StorageOS/data/system.log` |

---

## Requirements

- **CC:Tweaked** 1.100+ (Minecraft 1.18+) — an *Advanced Computer* is recommended for colour support
- At least one inventory peripheral connected via a Wired Modem network
- *(Optional)* A **Crafting Turtle** or **Workbench** peripheral for crafting support
- *(Optional)* Furnaces / Smokers / Blast Furnaces for smelting
- *(Optional)* **Create** mod peripherals (basins, presses, etc.)

---

## Installation

1. Copy the entire repository into the computer's root directory so the layout looks like:

```
/startup.lua
/StorageOS/
    core.lua
    config.lua
    utils.lua
    logger.lua
    network.lua
    storage.lua
    crafting.lua
    processing.lua
    tasks.lua
    gui.lua
    recipes/
        manager.lua
        defaults.lua
```

2. Reboot the computer (`Ctrl+R`) — `startup.lua` will launch StorageOS automatically.

> **Tip:** Use `wget` or `pastebin get` in-game, or a resource pack / world edit tool, to transfer files.

---

## File Structure

```
startup.lua                 Boot-loader (auto-runs on computer start)
StorageOS/
  core.lua                  Wires all modules; starts the parallel task scheduler
  config.lua                All tunable constants (intervals, priorities, colours, …)
  utils.lua                 Shared helpers (string, table, file, peripheral utilities)
  logger.lua                File-backed logger with in-memory ring buffer for the GUI
  network.lua               Peripheral auto-discovery, hot-plug, and classification
  storage.lua               Item index, priority-ordered store/retrieve, input ingest
  crafting.lua              Turtle/workbench crafting, recipe sourcing, craft queue
  processing.lua            Furnace/smoker/blast-furnace + Create machine management
  tasks.lua                 Coroutine task scheduler wrapping parallel.waitForAll
  gui.lua                   Tabbed terminal GUI with keyboard and mouse support
  recipes/
    manager.lua             Dynamic recipe registry (add, remove, save, load)
    defaults.lua            Built-in recipes (planks, ingots, charcoal, Create items, …)
```

---

## GUI Controls

| Key | Action |
|---|---|
| `Tab` / `→` / `←` | Switch between tabs |
| `↑` / `↓` | Scroll list |
| `PgUp` / `PgDn` | Fast scroll |
| `Enter` | Confirm / open action (e.g. craft an item) |
| `R` | Force re-scan network and storage |
| `Q` | Quit StorageOS |
| Mouse click | Click on tab bar to switch tabs |
| Mouse scroll | Scroll the active list |

### Tabs

| Tab | Contents |
|---|---|
| **Home** | System overview: item count, peripherals, recipe count, queue depths |
| **Storage** | Full item list with quantities, sorted alphabetically |
| **Crafting** | Queue depth, craftable items list; press Enter to queue a craft |
| **Processing** | Furnace/Create machine status and pending job queue |
| **Tasks** | Background task status (id, name, priority, state) |
| **Log** | Live system log with colour-coded severity levels |

---

## Configuration

Edit `/StorageOS/config.lua` to customise behaviour:

- **`STORAGE_PRIORITY_TABLE`** — change the priority order of storage backends  
- **`SCAN_INTERVAL`** / **`RESTOCK_INTERVAL`** / **`FURNACE_INTERVAL`** — adjust polling rates  
- **`FUEL_ITEMS`** — list of acceptable furnace fuels  
- **`INPUT_LABELS`** / **`OUTPUT_LABELS`** — chest label strings that designate I/O chests  
- **`GUI`** colours — customise the terminal palette  

---

## Adding Custom Recipes

Create a `.lua` file in `/StorageOS/recipes/` that returns a recipe table or list of tables:

```lua
-- /StorageOS/recipes/my_recipes.lua
return {
    {
        id       = "compressed_stone",
        output   = "create:compressed_stone",
        count    = 1,
        type     = "create_pressing",   -- "craft" | "smelt" | "blast" | "smoke" | "create_pressing" | "create_mixing"
        inputs   = { "minecraft:stone" },
        time     = 100,
    },
}
```

The file is picked up automatically on next boot (or manual `R` rescan in the GUI).

---

## Priority System

When storing an item, StorageOS walks the sorted list of connected inventories (highest priority first):

1. **Storage Drawers** (priority 90–100) — preferred; drawers auto-filter to matching items  
2. **Sophisticated Storage barrels/chests** (80–90)  
3. **Minecraft barrels** (80)  
4. **Minecraft chests** (70)  
5. **Other** (60 and below)  

Input and output chests are **never** used as storage destinations.

---

## Supported Mod Integrations

| Mod | Peripherals recognised |
|---|---|
| Vanilla | `minecraft:chest`, `minecraft:barrel`, `minecraft:furnace`, `minecraft:smoker`, `minecraft:blast_furnace` |
| **Storage Drawers** | `storagedrawers:*` |
| **Sophisticated Storage** | `sophisticatedstorage:*` |
| **Create** | `create:vault`, `create:basin`, `create:mechanical_press`, `create:mixer`, `create:andesite_funnel`, `create:brass_funnel`, `create:smart_chute`, `create:spout` |

Additional patterns can be added to `Config.STORAGE_PRIORITY_TABLE` and `Config.PROCESSING_PATTERNS` in `config.lua`.

---

## License

MIT — do whatever you like with it in your Minecraft world.