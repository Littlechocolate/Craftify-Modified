"""Creative Inventory tabs and definitions."""

from enum import Enum
from typing import Any, Dict, List, Tuple

class CreativeTab(str, Enum):
    BUILDING_BLOCKS = "Building Blocks"
    COLORED_BLOCKS = "Colored Blocks"
    NATURAL_BLOCKS = "Natural Blocks"
    FUNCTIONAL_BLOCKS = "Functional Blocks"
    REDSTONE_BLOCKS = "Redstone Blocks"
    TOOLS_AND_UTILITIES = "Tools & Utilities"
    COMBAT = "Combat"
    FOOD_AND_DRINKS = "Food & Drinks"
    INGREDIENTS = "Ingredients"
    SPAWN_EGGS = "Spawn Eggs"
    OPERATOR_UTILITIES = "Operator Utilities"

TAB_DISPLAY_NAMES_ZH: Dict[str, str] = {
    CreativeTab.BUILDING_BLOCKS.value: "建筑方块",
    CreativeTab.COLORED_BLOCKS.value: "彩色方块",
    CreativeTab.NATURAL_BLOCKS.value: "天然方块",
    CreativeTab.FUNCTIONAL_BLOCKS.value: "功能方块",
    CreativeTab.REDSTONE_BLOCKS.value: "红石方块",
    CreativeTab.TOOLS_AND_UTILITIES.value: "工具与实用物品",
    CreativeTab.COMBAT.value: "战斗",
    CreativeTab.FOOD_AND_DRINKS.value: "食物与饮品",
    CreativeTab.INGREDIENTS.value: "原材料",
    CreativeTab.SPAWN_EGGS.value: "刷怪蛋",
    CreativeTab.OPERATOR_UTILITIES.value: "管理与实用方块",
}

TAB_ICONS: Dict[str, str] = {
    CreativeTab.BUILDING_BLOCKS.value: "🧱",
    CreativeTab.COLORED_BLOCKS.value: "🎨",
    CreativeTab.NATURAL_BLOCKS.value: "🌿",
    CreativeTab.FUNCTIONAL_BLOCKS.value: "🛠️",
    CreativeTab.REDSTONE_BLOCKS.value: "⚡",
    CreativeTab.TOOLS_AND_UTILITIES.value: "⛏️",
    CreativeTab.COMBAT.value: "⚔️",
    CreativeTab.FOOD_AND_DRINKS.value: "🍎",
    CreativeTab.INGREDIENTS.value: "💎",
    CreativeTab.SPAWN_EGGS.value: "🥚",
    CreativeTab.OPERATOR_UTILITIES.value: "⚙️",
}

ALL_TABS: List[str] = [t.value for t in CreativeTab]

CREATIVE_TABS_META = [
    ("building_blocks",     "🧱 建筑方块 (Building Blocks)",     (194, 118, 68)),
    ("colored_blocks",      "🎨 染色方块 (Colored Blocks)",      (214, 92, 162)),
    ("natural_blocks",      "🌿 自然方块 (Natural Blocks)",      (98, 168, 68)),
    ("functional_blocks",   "🛠️ 功能方块 (Functional Blocks)",   (218, 165, 58)),
    ("redstone_blocks",     "🔴 红石方块 (Redstone Blocks)",     (204, 62, 52)),
    ("tools_and_utilities", "⛏️ 工具与实用 (Tools & Utilities)", (68, 162, 184)),
    ("combat",              "⚔️ 战斗用品 (Combat)",              (212, 88, 72)),
    ("food_and_drinks",     "🍎 食物与饮品 (Food & Drinks)",     (224, 142, 64)),
    ("ingredients",         "🧪 原材料 (Ingredients)",           (158, 114, 212)),
    ("spawn_eggs",          "🥚 刷怪蛋 (Spawn Eggs)",            (116, 188, 136)),
    ("op_blocks",           "⚙️ 管理员用品 (Operator Utilities)",(138, 102, 204)),
    ("other_items",         "📦 其他未归类 (Other Items)",       (118, 134, 156)),
    ("all_items",           "🔍 全部方块与物品 (All Items)",     (140, 148, 160)),
]

TAB_NAME_MAP = {k: label for k, label, _ in CREATIVE_TABS_META}
TAB_COLOR_MAP = {k: color for k, _, color in CREATIVE_TABS_META}

DYE_COLORS_ORDER = [
    "white", "light_gray", "gray", "black", "brown", "red", "orange", "yellow",
    "lime", "green", "cyan", "light_blue", "blue", "purple", "magenta", "pink"
]

DYE_COLOR_RGB = {
    "white":      (249, 255, 254),
    "orange":     (249, 128, 29),
    "magenta":    (199, 78, 189),
    "light_blue": (58, 179, 218),
    "yellow":     (254, 216, 61),
    "lime":       (128, 199, 31),
    "pink":       (243, 139, 170),
    "gray":       (71, 79, 82),
    "light_gray": (157, 157, 151),
    "cyan":       (22, 156, 156),
    "purple":     (137, 50, 184),
    "blue":       (60, 68, 170),
    "brown":      (131, 84, 50),
    "green":      (94, 124, 22),
    "red":        (176, 46, 38),
    "black":      (29, 29, 33),
}

COPPER_STATES = ["", "exposed_", "weathered_", "oxidized_"]

FIELD_TO_ID_OVERRIDES = {
    "cut_standstone_slab": "cut_sandstone_slab",
}

# Canonical Minecraft spawn egg dual colors: (primary_color, secondary_color)
SPAWN_EGG_COLORS: Dict[str, Tuple[int, int]] = {
    "allay_spawn_egg": (0x00daff, 0x00adff),
    "armadillo_spawn_egg": (0xad716d, 0x824848),
    "axolotl_spawn_egg": (0xfbc1e3, 0xa62d74),
    "bat_spawn_egg": (0x4c3e30, 0x0f0f0f),
    "bee_spawn_egg": (0xedc343, 0x43241b),
    "blaze_spawn_egg": (0xf6b201, 0xfff87e),
    "bogged_spawn_egg": (0x8a9c72, 0x314d1b),
    "breeze_spawn_egg": (0xaf94df, 0x9166df),
    "camel_spawn_egg": (0xfcc369, 0xcb9337),
    "cat_spawn_egg": (0xefc88e, 0x957256),
    "cave_spider_spawn_egg": (0x0c424e, 0xa80e0e),
    "chicken_spawn_egg": (0xa1a1a1, 0xff0000),
    "cod_spawn_egg": (0xc1a76a, 0xe5c48b),
    "cow_spawn_egg": (0x443626, 0xa1a1a1),
    "creeper_spawn_egg": (0x0da70b, 0x000000),
    "dolphin_spawn_egg": (0x223b4d, 0xf9f9f9),
    "donkey_spawn_egg": (0x534539, 0x867566),
    "drowned_spawn_egg": (0x8ff1d7, 0x799c65),
    "elder_guardian_spawn_egg": (0xceccba, 0x747693),
    "ender_dragon_spawn_egg": (0x1c1c1c, 0xe079fa),
    "enderman_spawn_egg": (0x161616, 0x000000),
    "endermite_spawn_egg": (0x161616, 0x6e6e6e),
    "evoker_spawn_egg": (0x959b9b, 0x1e1c1a),
    "fox_spawn_egg": (0xd5b69f, 0xcc6920),
    "frog_spawn_egg": (0xd07444, 0xffc77c),
    "ghast_spawn_egg": (0xf9f9f9, 0xbcbcbc),
    "glow_squid_spawn_egg": (0x095656, 0x85f1bc),
    "goat_spawn_egg": (0xa5947c, 0x55493e),
    "guardian_spawn_egg": (0x5a8272, 0xf17d30),
    "hoglin_spawn_egg": (0xc66e55, 0x5f6464),
    "horse_spawn_egg": (0xc09e7d, 0xeee500),
    "husk_spawn_egg": (0x797061, 0xe6cc94),
    "iron_golem_spawn_egg": (0xdbcdc2, 0x74a332),
    "llama_spawn_egg": (0xc09e7d, 0x995f40),
    "magma_cube_spawn_egg": (0x340000, 0xfcfc00),
    "mooshroom_spawn_egg": (0xa00f10, 0xb7b7b7),
    "mule_spawn_egg": (0x1b0200, 0x51331d),
    "ocelot_spawn_egg": (0xefde7d, 0x564434),
    "panda_spawn_egg": (0xe7e7e7, 0x1b1b22),
    "parrot_spawn_egg": (0x0da70b, 0xff0000),
    "phantom_spawn_egg": (0x43518a, 0x88ff00),
    "pig_spawn_egg": (0xf0a5a2, 0xdb635f),
    "piglin_brute_spawn_egg": (0x592a10, 0xf9f3a4),
    "piglin_spawn_egg": (0x995f40, 0xf9f3a4),
    "pillager_spawn_egg": (0x532f36, 0x959b9b),
    "polar_bear_spawn_egg": (0xeeeede, 0xd5d6cd),
    "pufferfish_spawn_egg": (0xf6b201, 0x37c3f2),
    "rabbit_spawn_egg": (0x995f40, 0x734831),
    "ravager_spawn_egg": (0x757470, 0x5b5049),
    "salmon_spawn_egg": (0xa00f10, 0x0e8474),
    "sheep_spawn_egg": (0xe7e7e7, 0xffb5b5),
    "shulker_spawn_egg": (0x946794, 0x4d3852),
    "silverfish_spawn_egg": (0x6e6e6e, 0x303030),
    "skeleton_horse_spawn_egg": (0x68684f, 0xe5e5d8),
    "skeleton_spawn_egg": (0xc1c1c1, 0x494949),
    "slime_spawn_egg": (0x51a03e, 0x7ebf6e),
    "sniffer_spawn_egg": (0x871e09, 0x25ab70),
    "snow_golem_spawn_egg": (0xd9f2f2, 0x81a4a4),
    "spider_spawn_egg": (0x342d27, 0xa80e0e),
    "squid_spawn_egg": (0x223b4d, 0x708899),
    "stray_spawn_egg": (0x617677, 0xddeaea),
    "strider_spawn_egg": (0x9c3436, 0x4d494d),
    "tadpole_spawn_egg": (0x6d533d, 0x160a00),
    "trader_llama_spawn_egg": (0xeaa430, 0x456296),
    "tropical_fish_spawn_egg": (0xef6915, 0xfff9ef),
    "turtle_spawn_egg": (0xe7e7e7, 0x00afaf),
    "vex_spawn_egg": (0x7a90a4, 0xe8edf1),
    "villager_spawn_egg": (0x563c33, 0xbd8b72),
    "vindicator_spawn_egg": (0x959b9b, 0x275e61),
    "wandering_trader_spawn_egg": (0x456296, 0xeaa430),
    "warden_spawn_egg": (0x0f4649, 0x39d6e0),
    "witch_spawn_egg": (0x340000, 0x51a03e),
    "wither_skeleton_spawn_egg": (0x141414, 0x474d4d),
    "wither_spawn_egg": (0x141414, 0x4d72a0),
    "wolf_spawn_egg": (0xd7d3d3, 0xceaf96),
    "zoglin_spawn_egg": (0xc66e55, 0xe6e6e6),
    "zombie_horse_spawn_egg": (0x315234, 0x97c284),
    "zombie_spawn_egg": (0x00afaf, 0x799c65),
    "zombie_villager_spawn_egg": (0x563c33, 0x799c65),
    "zombified_piglin_spawn_egg": (0xea9393, 0x4c7129),
}

def get_spawn_egg_tints(egg_name: str) -> List[Dict[str, Any]]:
    clean = egg_name.split("/")[-1]
    if clean in SPAWN_EGG_COLORS:
        c1, c2 = SPAWN_EGG_COLORS[clean]
    else:
        h = abs(hash(clean))
        c1 = (h & 0xFFFFFF)
        c2 = ((h >> 8) & 0xFFFFFF)
    return [
        {"type": "minecraft:constant", "value": c1},
        {"type": "minecraft:constant", "value": c2},
    ]

