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
| **Local Recipe Discovery** | Automatically discovers recipes from RS/AE2 peripherals, local JSON files, and built-in defaults — **no internet required**, all installed mods handled |
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
- *(Optional)* **Advanced Peripherals** + Refined Storage or AE2 for full automatic recipe discovery

---

## Installation

### One-command install (recommended)

Run the following on your CC:Tweaked computer:

```
wget https://raw.githubusercontent.com/rdash99/Computer-Craft-testing/main/install.lua
install
```

The installer downloads all files, creates the necessary directory structure, and offers to launch StorageOS immediately.

### Manual install

Copy the entire repository into the computer's root directory so the layout looks like:

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
    recipe_scanner.lua
    tasks.lua
    gui.lua
    recipes/
        manager.lua
        defaults.lua
    recipes/data/     ← drop recipe JSON files here
```

Reboot the computer (`Ctrl+R`) — `startup.lua` will launch StorageOS automatically.

---

## File Structure

```
startup.lua                 Boot-loader (auto-runs on computer start)
install.lua                 One-command installer
StorageOS/
  core.lua                  Wires all modules; starts the parallel task scheduler
  config.lua                All tunable constants (intervals, priorities, colours, …)
  utils.lua                 Shared helpers (string, table, file, peripheral utilities)
  logger.lua                File-backed logger with in-memory ring buffer for the GUI
  network.lua               Peripheral auto-discovery, hot-plug, and classification
  storage.lua               Item index, priority-ordered store/retrieve, input ingest
  crafting.lua              Turtle/workbench crafting, recipe sourcing, craft queue
  processing.lua            Furnace/smoker/blast-furnace + Create machine management
  recipe_scanner.lua        Local recipe discovery: peripherals → JSON files → defaults
  tasks.lua                 Coroutine task scheduler wrapping parallel.waitForAll
  gui.lua                   Tabbed terminal GUI with keyboard and mouse support
  recipes/
    manager.lua             Dynamic recipe registry (add, remove, save, load)
    defaults.lua            Built-in fallback recipes (planks, ingots, Create items, …)
    data/                   ← place Minecraft recipe JSON files here for auto-loading
```

---

## Recipe Discovery

StorageOS discovers recipes **entirely locally** — no internet connection required.  
Every installed mod's recipes are handled automatically through the following pipeline:

### 1. Storage-system peripheral APIs (highest priority)

| Peripheral | How to connect | What's loaded |
|---|---|---|
| **rsBridge** (Advanced Peripherals + Refined Storage) | Connect bridge to wired modem | **All RS crafting & processing patterns** — covers every mod recipe you've set up in RS |
| **meBridge** (Advanced Peripherals + AE2) | Connect bridge to wired modem | All AE2 craftable items + ingredient data where available |
| Any peripheral with `getRecipes()` / `listRecipes()` | — | Generic recipe data from any future or custom mod |

When an RS or AE2 bridge is connected, StorageOS imports **all patterns from the storage system's recipe registry** — this includes recipes from Create, Thermal, Mekanism, Botania, or any other installed mod, automatically.

### 2. Local Minecraft recipe JSON files

Drop any Minecraft-format recipe `.json` file into:

```
/StorageOS/recipes/data/
```

or

```
/recipes/
```

Files are scanned recursively, so the standard datapack layout `data/{namespace}/recipes/*.json` works as-is.

**Supported JSON recipe types:**

| Type | Description |
|---|---|
| `minecraft:crafting_shaped` | 3×3 grid crafting |
| `minecraft:crafting_shapeless` | Unordered crafting |
| `minecraft:smelting` | Furnace |
| `minecraft:blasting` | Blast furnace |
| `minecraft:smoking` | Smoker |
| `minecraft:stonecutting` | Stonecutter |

**How to get recipe JSON files for installed mods:**
- Export from JEI/REI using a companion mod
- Copy from the mod's JAR (`data/{namespace}/recipes/`)
- Use KubeJS or CraftTweaker to write recipes to disk
- Use a datapack tool to export recipes

### 3. Hand-crafted Lua recipe files

Place `.lua` files in `/StorageOS/recipes/` that return a recipe table.  See [Adding Custom Recipes](#adding-custom-recipes).

### 4. Built-in defaults (fallback)

If no other source provides any recipes, the built-in `defaults.lua` is loaded automatically.  
It includes common vanilla recipes and a selection of Create mod items.

### Re-scanning

Press **`F`** in the Crafting tab to trigger a re-scan at any time.  
The system also re-scans automatically every ~90 seconds to pick up newly-connected peripherals.

---

## GUI Controls

| Key | Action |
|---|---|
| `Tab` / `→` / `←` | Switch between tabs |
| `↑` / `↓` | Scroll list |
| `PgUp` / `PgDn` | Fast scroll |
| `Enter` | Confirm / open action (e.g. craft an item) |
| `R` | Force re-scan network, storage, and processors |
| `F` | Re-scan recipe sources (peripherals + JSON files) |
| `Q` | Quit StorageOS |
| Mouse click | Click on tab bar to switch tabs |
| Mouse scroll | Scroll the active list |

### Tabs

| Tab | Contents |
|---|---|
| **Home** | System overview: item count, peripherals, recipe count, queue depths |
| **Storage** | Full item list with quantities, sorted alphabetically |
| **Crafting** | Craftable Now (live inventory check), full recipe list, job queue, recipe source breakdown |
| **Processing** | Furnace/Create machine status and pending job queue |
| **Tasks** | Background task status (id, name, priority, state) |
| **Log** | Live system log with colour-coded severity levels |

---

## Configuration

Edit `/StorageOS/config.lua` to customise behaviour:

- **`STORAGE_PRIORITY_TABLE`** — change the priority order of storage backends  
- **`RECIPE_DATA_DIRS`** — additional directories to scan for recipe JSON files  
- **`RECIPE_PERIPHERAL_TYPES`** — peripheral type names probed for recipe APIs  
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

The file is picked up on the next recipe scan (press `F` in the Crafting tab, or reboot).

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
| **Refined Storage** *(with Advanced Peripherals)* | `rsBridge` — full recipe pattern import |
| **Applied Energistics 2** *(with Advanced Peripherals)* | `meBridge` — craftable item + recipe import |

Additional patterns can be added to `Config.STORAGE_PRIORITY_TABLE` and `Config.PROCESSING_PATTERNS` in `config.lua`.

---

## License

MIT — do whatever you like with it in your Minecraft world.
