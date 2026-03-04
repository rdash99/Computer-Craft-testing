-- StorageOS/recipes/defaults.lua
-- Built-in recipe definitions loaded at startup.
-- Each recipe follows the schema in recipes/manager.lua.
--
-- Types:
--   "craft"           – 2×2 or 3×3 crafting table
--   "smelt"           – furnace smelting
--   "blast"           – blast-furnace smelting
--   "smoke"           – smoker
--   "create_pressing" – Create mechanical press
--   "create_mixing"   – Create mixer/basin
--   "create_compacting" – Create compacting (press + basin)

local recipes = {

    -- ── Planks ──────────────────────────────────────────────────────────────
    {
        id       = "oak_planks",
        output   = "minecraft:oak_planks",
        count    = 4,
        type     = "craft",
        shapeless = true,
        inputs   = { "minecraft:oak_log" },
    },
    {
        id       = "spruce_planks",
        output   = "minecraft:spruce_planks",
        count    = 4,
        type     = "craft",
        shapeless = true,
        inputs   = { "minecraft:spruce_log" },
    },
    {
        id       = "birch_planks",
        output   = "minecraft:birch_planks",
        count    = 4,
        type     = "craft",
        shapeless = true,
        inputs   = { "minecraft:birch_log" },
    },

    -- ── Sticks ──────────────────────────────────────────────────────────────
    {
        id     = "sticks",
        output = "minecraft:stick",
        count  = 4,
        type   = "craft",
        grid   = {
            [1] = "minecraft:oak_planks",
            [4] = "minecraft:oak_planks",
        },
    },

    -- ── Torches ─────────────────────────────────────────────────────────────
    {
        id     = "torch",
        output = "minecraft:torch",
        count  = 4,
        type   = "craft",
        grid   = {
            [1] = "minecraft:coal",
            [4] = "minecraft:stick",
        },
    },

    -- ── Charcoal ────────────────────────────────────────────────────────────
    {
        id     = "charcoal",
        output = "minecraft:charcoal",
        count  = 1,
        type   = "smelt",
        inputs = { "minecraft:oak_log" },
        fuel   = "minecraft:coal",
        time   = 200,
    },

    -- ── Iron ingot ──────────────────────────────────────────────────────────
    {
        id     = "iron_ingot_smelt",
        output = "minecraft:iron_ingot",
        count  = 1,
        type   = "smelt",
        inputs = { "minecraft:raw_iron" },
        time   = 200,
    },
    {
        id     = "iron_ingot_blast",
        output = "minecraft:iron_ingot",
        count  = 1,
        type   = "blast",
        inputs = { "minecraft:raw_iron" },
        time   = 100,
    },

    -- ── Gold ingot ──────────────────────────────────────────────────────────
    {
        id     = "gold_ingot_smelt",
        output = "minecraft:gold_ingot",
        count  = 1,
        type   = "smelt",
        inputs = { "minecraft:raw_gold" },
        time   = 200,
    },
    {
        id     = "gold_ingot_blast",
        output = "minecraft:gold_ingot",
        count  = 1,
        type   = "blast",
        inputs = { "minecraft:raw_gold" },
        time   = 100,
    },

    -- ── Copper ingot ────────────────────────────────────────────────────────
    {
        id     = "copper_ingot_smelt",
        output = "minecraft:copper_ingot",
        count  = 1,
        type   = "smelt",
        inputs = { "minecraft:raw_copper" },
        time   = 200,
    },
    {
        id     = "copper_ingot_blast",
        output = "minecraft:copper_ingot",
        count  = 1,
        type   = "blast",
        inputs = { "minecraft:raw_copper" },
        time   = 100,
    },

    -- ── Glass ────────────────────────────────────────────────────────────────
    {
        id     = "glass",
        output = "minecraft:glass",
        count  = 1,
        type   = "smelt",
        inputs = { "minecraft:sand" },
        time   = 200,
    },

    -- ── Cooked food ─────────────────────────────────────────────────────────
    {
        id     = "cooked_beef",
        output = "minecraft:cooked_beef",
        count  = 1,
        type   = "smoke",
        inputs = { "minecraft:beef" },
        time   = 100,
    },
    {
        id     = "cooked_chicken",
        output = "minecraft:cooked_chicken",
        count  = 1,
        type   = "smoke",
        inputs = { "minecraft:chicken" },
        time   = 100,
    },
    {
        id     = "cooked_porkchop",
        output = "minecraft:cooked_porkchop",
        count  = 1,
        type   = "smoke",
        inputs = { "minecraft:porkchop" },
        time   = 100,
    },
    {
        id     = "cooked_salmon",
        output = "minecraft:cooked_salmon",
        count  = 1,
        type   = "smoke",
        inputs = { "minecraft:salmon" },
        time   = 100,
    },

    -- ── Crafting table ───────────────────────────────────────────────────────
    {
        id     = "crafting_table",
        output = "minecraft:crafting_table",
        count  = 1,
        type   = "craft",
        grid   = {
            [1] = "minecraft:oak_planks",
            [2] = "minecraft:oak_planks",
            [4] = "minecraft:oak_planks",
            [5] = "minecraft:oak_planks",
        },
    },

    -- ── Chest ────────────────────────────────────────────────────────────────
    {
        id     = "chest",
        output = "minecraft:chest",
        count  = 1,
        type   = "craft",
        grid   = {
            [1] = "minecraft:oak_planks",
            [2] = "minecraft:oak_planks",
            [3] = "minecraft:oak_planks",
            [4] = "minecraft:oak_planks",
            [6] = "minecraft:oak_planks",
            [7] = "minecraft:oak_planks",
            [8] = "minecraft:oak_planks",
            [9] = "minecraft:oak_planks",
        },
    },

    -- ── Furnace ──────────────────────────────────────────────────────────────
    {
        id     = "furnace",
        output = "minecraft:furnace",
        count  = 1,
        type   = "craft",
        grid   = {
            [1] = "minecraft:cobblestone",
            [2] = "minecraft:cobblestone",
            [3] = "minecraft:cobblestone",
            [4] = "minecraft:cobblestone",
            [6] = "minecraft:cobblestone",
            [7] = "minecraft:cobblestone",
            [8] = "minecraft:cobblestone",
            [9] = "minecraft:cobblestone",
        },
    },

    -- ── Stone ────────────────────────────────────────────────────────────────
    {
        id     = "stone",
        output = "minecraft:stone",
        count  = 1,
        type   = "smelt",
        inputs = { "minecraft:cobblestone" },
        time   = 200,
    },

    -- ── Smooth stone ─────────────────────────────────────────────────────────
    {
        id     = "smooth_stone",
        output = "minecraft:smooth_stone",
        count  = 1,
        type   = "smelt",
        inputs = { "minecraft:stone" },
        time   = 200,
    },

    -- ── Brick ────────────────────────────────────────────────────────────────
    {
        id     = "brick",
        output = "minecraft:brick",
        count  = 1,
        type   = "smelt",
        inputs = { "minecraft:clay_ball" },
        time   = 200,
    },

    -- ── Bricks block ─────────────────────────────────────────────────────────
    {
        id     = "bricks",
        output = "minecraft:bricks",
        count  = 1,
        type   = "craft",
        grid   = {
            [1] = "minecraft:brick",
            [2] = "minecraft:brick",
            [4] = "minecraft:brick",
            [5] = "minecraft:brick",
        },
    },

    -- ── Iron block ───────────────────────────────────────────────────────────
    {
        id     = "iron_block",
        output = "minecraft:iron_block",
        count  = 1,
        type   = "craft",
        grid   = {
            [1] = "minecraft:iron_ingot",
            [2] = "minecraft:iron_ingot",
            [3] = "minecraft:iron_ingot",
            [4] = "minecraft:iron_ingot",
            [5] = "minecraft:iron_ingot",
            [6] = "minecraft:iron_ingot",
            [7] = "minecraft:iron_ingot",
            [8] = "minecraft:iron_ingot",
            [9] = "minecraft:iron_ingot",
        },
    },

    -- ── Iron nugget ──────────────────────────────────────────────────────────
    {
        id       = "iron_nugget",
        output   = "minecraft:iron_nugget",
        count    = 9,
        type     = "craft",
        shapeless = true,
        inputs   = { "minecraft:iron_ingot" },
    },

    -- ── Andesite alloy (Create) ──────────────────────────────────────────────
    {
        id     = "andesite_alloy",
        output = "create:andesite_alloy",
        count  = 2,
        type   = "craft",
        grid   = {
            [1] = "minecraft:andesite",
            [2] = "minecraft:iron_nugget",
            [4] = "minecraft:iron_nugget",
            [5] = "minecraft:andesite",
        },
    },

    -- ── Zinc ingot (Create) ──────────────────────────────────────────────────
    {
        id     = "zinc_ingot",
        output = "create:zinc_ingot",
        count  = 1,
        type   = "smelt",
        inputs = { "create:raw_zinc" },
        time   = 200,
    },
    {
        id     = "zinc_ingot_blast",
        output = "create:zinc_ingot",
        count  = 1,
        type   = "blast",
        inputs = { "create:raw_zinc" },
        time   = 100,
    },

    -- ── Brass ingot (Create – mixing) ────────────────────────────────────────
    {
        id     = "brass_ingot",
        output = "create:brass_ingot",
        count  = 3,
        type   = "create_mixing",
        inputs = { "create:zinc_nugget", "create:zinc_nugget", "minecraft:copper_ingot", "minecraft:copper_ingot" },
        time   = 120,
    },

    -- ── Shaft (Create) ───────────────────────────────────────────────────────
    {
        id     = "shaft",
        output = "create:shaft",
        count  = 2,
        type   = "craft",
        grid   = {
            [2] = "create:andesite_alloy",
            [5] = "create:andesite_alloy",
        },
    },

    -- ── Cogwheel (Create) ────────────────────────────────────────────────────
    {
        id     = "cogwheel",
        output = "create:cogwheel",
        count  = 1,
        type   = "craft",
        grid   = {
            [2] = "minecraft:oak_planks",
            [4] = "minecraft:oak_planks",
            [5] = "create:andesite_alloy",
            [6] = "minecraft:oak_planks",
            [8] = "minecraft:oak_planks",
        },
    },

    -- ── Compressed iron (Create press) ───────────────────────────────────────
    {
        id     = "compressed_iron",
        output = "create:compressed_iron",
        count  = 1,
        type   = "create_pressing",
        inputs = { "minecraft:iron_ingot" },
        time   = 100,
    },

    -- ── Iron sheet (Create press) ─────────────────────────────────────────────
    {
        id     = "iron_sheet",
        output = "create:iron_sheet",
        count  = 1,
        type   = "create_pressing",
        inputs = { "create:compressed_iron" },
        time   = 100,
    },

}

return recipes
