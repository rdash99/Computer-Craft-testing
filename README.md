# StorageOS — ComputerCraft Storage Management System

A fully-featured Lua program for the **CC:Tweaked** (ComputerCraft) Minecraft mod that turns any Advanced Computer into an intelligent, automated storage and crafting controller.

---

## ⚠️ Install on a Computer, Not a Turtle

StorageOS **must be installed on a regular Advanced Computer** (or standard Computer).  
**Do not install it on a turtle.**

The computer uses the Wired Modem network to talk to every peripheral — chests, furnaces, turtles, presses, etc. — via the `pushItems`/`pullItems` inventory API.  A turtle is not needed *on* the controller computer; it is an optional *peripheral on the network* used only for shaped/shapeless crafting jobs.

---

## Features

| Feature | Details |
|---|---|
| **Unified Storage** | Tracks every item across all connected inventories in a single indexed view |
| **Priority System** | Storage Drawers → Barrels → Chests (configurable, higher priority filled first) |
| **Auto-Ingest** | Polls designated input chests and automatically stores their contents |
| **Item Retrieval** | Select any item in the Storage tab, press `Enter`, enter an amount — items are pushed to your output chest for collection |
| **Crafting** | Shaped & shapeless crafting via a crafting turtle or workbench peripheral on the network |
| **Local Recipe Discovery** | Automatically discovers recipes from RS/AE2 peripherals, local JSON files, and built-in defaults — **no internet required**, all installed mods handled |
| **Multi-Furnace** | Distributes smelting jobs across all furnaces, smokers, and blast furnaces |
| **Create Support** | Recognises Create mod basins, presses, mixers, funnels, and vaults |
| **Parallel Tasks** | All background work (ingest, scan, smelting tick, craft queue) runs concurrently via `parallel.waitForAll` |
| **GUI** | Tabbed terminal interface — Home, Storage, Crafting, Processing, Tasks, Log |
| **Hot-Plug** | Detects peripherals added/removed while the system is running |
| **Logging** | Ring-buffer log viewable in the GUI; also written to `/StorageOS/data/system.log` |

---

## Requirements

- **CC:Tweaked** 1.100+ (Minecraft 1.18+)
- An **Advanced Computer** *(for colour GUI)* — **not** a turtle
- A **Wired Modem** on the computer, connected by cable to all peripherals
- At least one inventory (chest / barrel / Storage Drawer / etc.) on the network
- An **output chest** labelled `output` on the network — items you retrieve are pushed here
- *(Optional)* An **input chest** labelled `input` — items placed here are auto-stored
- *(Optional)* A **Crafting Turtle** on the network for shaped/shapeless crafting
- *(Optional)* A **Workbench** peripheral as an alternative crafter
- *(Optional)* Furnaces / Smokers / Blast Furnaces for smelting
- *(Optional)* **Create** mod peripherals (basins, presses, etc.)
- *(Optional)* **Advanced Peripherals** + Refined Storage or AE2 for full automatic recipe discovery

---

## Hardware Setup

```
┌─────────────────────────────────────────────────────────────────┐
│                     Wired Modem Network                         │
│                                                                 │
│  ┌──────────────┐   ┌──────────┐   ┌──────────┐   ┌─────────┐ │
│  │   Advanced   │   │ Storage  │   │  Output  │   │ Crafting│ │
│  │   Computer   │   │  Chests  │   │  Chest   │   │  Turtle │ │
│  │  (StorageOS) │   │ Barrels  │   │(labelled │   │(no code │ │
│  │              │   │ Drawers  │   │"output") │   │needed)  │ │
│  └──────┬───────┘   └────┬─────┘   └────┬─────┘   └────┬────┘ │
│         └────────────────┴──────────────┴───────────────┘      │
│                     Wired Modems + Cable                        │
└─────────────────────────────────────────────────────────────────┘
```

### Step-by-step wiring

1. Place an **Advanced Computer** anywhere convenient.
2. Attach a **Wired Modem** to one side of the computer (`Right-click` the modem to activate it — it turns orange).
3. Run **Networking Cable** from that modem to every inventory you want managed.
4. Attach a **Wired Modem** to each inventory peripheral (chest, barrel, furnace, etc.) and activate each one.
5. Use the `peripheral list` command on the computer to confirm all devices appear.

### Labelling chests (anvil or `label set`)

StorageOS recognises chests by their in-game label:

| Label | Purpose |
|---|---|
| `output` / `out` / `storage_output` | **Items you retrieve are pushed here** — place this chest where you stand to collect |
| `input` / `in` / `storage_input` | Items placed here are auto-ingested into storage every 5 s |
| `fuel` / `furnace_fuel` | Fuel reserved for furnaces |

Label a chest by renaming it with an **anvil**: put the chest in an anvil, type the label (e.g. `output`), take it out, then place it on the cable network.

### The crafting turtle

The crafting turtle **does not run any program**.  It is just a peripheral on the wired network.  StorageOS pushes ingredients into the turtle's crafting grid slots remotely, calls `turtle.craft()` via the peripheral API, then pulls the results back into storage automatically.

- Use a **Crafting Turtle** (turtle with a crafting table upgrade).
- Connect it to the same Wired Modem network as the computer.
- Leave the turtle's inventory empty and its program slot blank — StorageOS manages it entirely.

---

## Installation

### One-command install (recommended)

Run the following on your **Advanced Computer** (not a turtle):

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
| `↑` / `↓` | Scroll list / move cursor |
| `PgUp` / `PgDn` | Fast scroll |
| `Enter` | Context action (see tab table below) |
| `R` | Force re-scan network, storage, and processors |
| `F` | Re-scan recipe sources (peripherals + JSON files) |
| `Q` | Quit StorageOS |
| Mouse click | Click on tab bar to switch tabs |
| Mouse scroll | Scroll the active list |

### Tabs

| Tab | `Enter` action | Contents |
|---|---|---|
| **Home** | — | System overview: item count, peripherals, recipe count, queue depths |
| **Storage** | **Retrieve item** — prompts for amount, pushes items to your output chest | Full item list with quantities, sorted alphabetically |
| **Crafting** | **Queue job** — prompts for amount; routes `craft`-type recipes to the craft queue, all others (smelt, Create, etc.) to the processing queue | Craftable Now (machine + ingredient check), full recipe list with type, job queue, recipe source breakdown |
| **Processing** | Queue a smelting job by name | Furnace/Create machine status and pending job queue |
| **Tasks** | — | Background task status (id, name, priority, state) |
| **Log** | — | Live system log with colour-coded severity levels |

### Retrieving items

1. Navigate to the **Storage** tab with `Tab`.  
2. Use `↑` / `↓` to highlight the item you want.  
3. Press `Enter` — a prompt asks *"Retrieve X (have N, 0=all):"*.  
4. Type the amount (or `0` for everything) and press `Enter`.  
5. Items are pushed to your **output chest** — walk over and collect them.

> **No output chest?**  Make sure you have a chest on the wired network that is labelled `output` (or `out` / `storage_output`).  See [Hardware Setup](#hardware-setup).

### "Craftable Now" vs "All Recipes"

The **Craftable Now** section only shows items that meet *both* conditions:

1. All required ingredients are currently in storage.
2. The required machine is present on the network (crafting turtle for `craft`, furnace for `smelt`/`blast`/`smoke`, Create press for `create_pressing`, etc.).

The **All Recipes** section lists every known recipe. Each entry shows the recipe type in brackets (e.g. `[craft]`, `[smelt]`, `[create_pressing]`) so you can see at a glance what machine an item requires. Items that cannot be made right now are shown in grey; items ready to queue are highlighted green.

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
