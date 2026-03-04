-- StorageOS/config.lua
-- Central configuration for the StorageOS storage management system.
-- Edit values here to customise behaviour without touching other modules.

local Config = {}

-- ── Version ──────────────────────────────────────────────────────────────────
Config.VERSION = "1.0.0"
Config.NAME    = "StorageOS"

-- ── File / directory paths ────────────────────────────────────────────────────
Config.STORAGE_OS_DIR  = "/StorageOS"
Config.DATA_DIR        = "/StorageOS/data"
Config.RECIPE_DIR      = "/StorageOS/recipes"
Config.LOG_FILE        = "/StorageOS/data/system.log"
Config.CONFIG_FILE     = "/StorageOS/data/settings.dat"
Config.INV_CACHE_FILE  = "/StorageOS/data/inventory.dat"

-- ── Timing intervals (seconds) ────────────────────────────────────────────────
Config.SCAN_INTERVAL    = 30   -- full peripheral re-scan
Config.RESTOCK_INTERVAL = 5    -- check input chest / restock drawers
Config.FURNACE_INTERVAL = 3    -- furnace progress check
Config.TASK_TICK        = 0.05 -- task-scheduler yield interval
Config.GUI_REFRESH      = 1    -- GUI redraw interval

-- ── Transfer limits ───────────────────────────────────────────────────────────
Config.MAX_TRANSFER = 64  -- max items per single pushItems call

-- ── Storage priority ─────────────────────────────────────────────────────────
-- Higher number → preferred destination when distributing items.
-- Partial string prefixes are matched against the peripheral type string.
-- The FIRST matching entry wins; order inside the list matters.
Config.STORAGE_PRIORITY_TABLE = {
    { match = "storagedrawers",           priority = 100, class = "storage_drawer" },
    { match = "sophisticatedstorage",     priority = 90,  class = "chest"          },
    { match = "sophisticatedbackpacks",   priority = 88,  class = "chest"          },
    { match = "minecraft:barrel",         priority = 80,  class = "barrel"         },
    { match = "minecraft:chest",          priority = 70,  class = "chest"          },
    { match = "minecraft:trapped_chest",  priority = 65,  class = "chest"          },
    { match = "minecraft:shulker_box",    priority = 60,  class = "chest"          },
    -- Create storage
    { match = "create:vault",             priority = 85,  class = "chest"          },
    { match = "create:item_vault",        priority = 85,  class = "chest"          },
}

-- ── Processing peripheral patterns ───────────────────────────────────────────
Config.PROCESSING_PATTERNS = {
    { match = "minecraft:furnace",       class = "furnace"       },
    { match = "minecraft:smoker",        class = "smoker"        },
    { match = "minecraft:blast_furnace", class = "blast_furnace" },
    -- Create mod processing
    { match = "create:basin",            class = "create_basin"  },
    { match = "create:mechanical_press", class = "create_press"  },
    { match = "create:mixer",            class = "create_mixer"  },
    { match = "create:deployer",         class = "create_deployer"},
    { match = "create:smart_chute",      class = "create_chute"  },
    { match = "create:chute",            class = "create_chute"  },
    { match = "create:andesite_funnel",  class = "create_funnel" },
    { match = "create:brass_funnel",     class = "create_funnel" },
    { match = "create:spout",            class = "create_spout"  },
}

-- ── Crafting peripheral patterns ─────────────────────────────────────────────
Config.CRAFTING_PATTERNS = {
    { match = "workbench",      class = "workbench" },
    { match = "crafting",       class = "workbench" },
    { match = "turtle",         class = "turtle"    },
}

-- ── Named roles ──────────────────────────────────────────────────────────────
-- The computer will look for chests with these labels on the network.
-- Players can rename chests in an anvil or use config file overrides.
Config.INPUT_LABELS  = { "input", "in", "storage_input" }
Config.OUTPUT_LABELS = { "output", "out", "storage_output" }
Config.FUEL_LABELS   = { "fuel", "furnace_fuel" }

-- ── Fuel items (for furnaces) ─────────────────────────────────────────────────
Config.FUEL_ITEMS = {
    "minecraft:coal",
    "minecraft:charcoal",
    "minecraft:coal_block",
    "minecraft:lava_bucket",
    "minecraft:blaze_rod",
    "minecraft:stick",
    "minecraft:wooden_pickaxe",
    "minecraft:oak_planks",
    "minecraft:spruce_planks",
    "minecraft:birch_planks",
    "minecraft:jungle_planks",
    "minecraft:acacia_planks",
    "minecraft:dark_oak_planks",
}

-- ── GUI palette ───────────────────────────────────────────────────────────────
Config.GUI = {
    BG         = colors.black,
    HEADER_BG  = colors.blue,
    HEADER_FG  = colors.white,
    TAB_BG     = colors.gray,
    TAB_FG     = colors.white,
    TAB_SEL_BG = colors.lightBlue,
    TAB_SEL_FG = colors.black,
    BODY_BG    = colors.black,
    BODY_FG    = colors.white,
    BORDER_FG  = colors.lightGray,
    SUCCESS_FG = colors.lime,
    WARN_FG    = colors.yellow,
    ERROR_FG   = colors.red,
    HIGHLIGHT  = colors.orange,
    DIM_FG     = colors.gray,
    INPUT_BG   = colors.gray,
    INPUT_FG   = colors.white,
}

-- ── Task priorities ───────────────────────────────────────────────────────────
Config.TASK_PRIORITY = {
    CRITICAL = 1,
    HIGH     = 2,
    NORMAL   = 3,
    LOW      = 4,
    IDLE     = 5,
}

return Config
