"""Creative Inventory Item Classifier."""

import re
import struct
import zipfile
from typing import Any, Dict, List, Optional, Set, Tuple
from .creative_tabs import (
    ALL_TABS,
    COPPER_STATES,
    CREATIVE_TABS_META,
    CreativeTab,
    DYE_COLORS_ORDER,
    FIELD_TO_ID_OVERRIDES,
)
from .categories_data import COLORS, COLORED_ITEM_TYPES, EXPLICIT_ITEM_MAPPING

def parse_java_class_methods(data: bytes) -> Tuple[List[Any], Dict[str, bytes]]:
    """Parses Java .class constant pool and method bytecodes without external tools."""
    magic, minor, major, cp_count = struct.unpack(">IHHH", data[:10])
    if magic != 0xCAFEBABE:
        raise ValueError("Invalid Java class file magic")
    pos = 10
    cp: List[Any] = [None] * cp_count
    i = 1
    while i < cp_count:
        tag = data[pos]
        pos += 1
        if tag == 1:  # Utf8
            length = struct.unpack(">H", data[pos:pos + 2])[0]
            pos += 2
            cp[i] = ("Utf8", data[pos:pos + length].decode("utf-8", errors="replace"))
            pos += length
        elif tag in (3, 4):  # Integer, Float
            cp[i] = (tag, struct.unpack(">I", data[pos:pos + 4])[0])
            pos += 4
        elif tag in (5, 6):  # Long, Double
            cp[i] = (tag, struct.unpack(">Q", data[pos:pos + 8])[0])
            pos += 8
            i += 1
        elif tag in (7, 8, 16, 19, 20):
            cp[i] = (tag, struct.unpack(">H", data[pos:pos + 2])[0])
            pos += 2
        elif tag in (9, 10, 11, 12, 17, 18):
            cp[i] = (tag, struct.unpack(">HH", data[pos:pos + 4]))
            pos += 4
        elif tag == 15:
            cp[i] = (tag, struct.unpack(">BH", data[pos:pos + 3]))
            pos += 3
        else:
            break
        i += 1

    access_flags, this_class, super_class, interfaces_count = struct.unpack(">HHHH", data[pos:pos + 8])
    pos += 8 + 2 * interfaces_count
    fields_count = struct.unpack(">H", data[pos:pos + 2])[0]
    pos += 2
    for _ in range(fields_count):
        f_flags, f_name, f_desc, f_attrs = struct.unpack(">HHHH", data[pos:pos + 8])
        pos += 8
        for _ in range(f_attrs):
            a_name, a_len = struct.unpack(">HI", data[pos:pos + 6])
            pos += 6 + a_len

    methods_count = struct.unpack(">H", data[pos:pos + 2])[0]
    pos += 2
    methods: Dict[str, bytes] = {}
    for _ in range(methods_count):
        m_flags, m_name, m_desc, m_attrs = struct.unpack(">HHHH", data[pos:pos + 8])
        pos += 8
        m_name_str = cp[m_name][1] if cp[m_name] else ""
        code_bytes = None
        for _ in range(m_attrs):
            a_name, a_len = struct.unpack(">HI", data[pos:pos + 6])
            a_data = data[pos + 6:pos + 6 + a_len]
            if cp[a_name] and cp[a_name][1] == "Code":
                max_stack, max_locals, code_len = struct.unpack(">HHI", a_data[:8])
                code_bytes = a_data[8:8 + code_len]
            pos += 6 + a_len
        if code_bytes is not None:
            methods[m_name_str] = code_bytes
    return cp, methods


def _resolve_cp(cp: List[Any], idx: int) -> Any:
    if idx <= 0 or idx >= len(cp) or cp[idx] is None:
        return None
    tag, val = cp[idx]
    if tag == "Utf8":
        return val
    elif tag in (7, 8, 16, 19, 20):
        return _resolve_cp(cp, val)
    elif tag in (9, 10, 11, 12):
        return (_resolve_cp(cp, val[0]), _resolve_cp(cp, val[1]))
    return val


def _extract_bytecode_ops(cp: List[Any], code: bytes) -> List[Tuple[str, Any]]:
    refs = []
    i = 0
    n = len(code)
    while i < n:
        op = code[i]
        if op == 0xB2 and i + 3 <= n:  # getstatic
            idx = struct.unpack(">H", code[i + 1:i + 3])[0]
            refs.append(("getstatic", _resolve_cp(cp, idx)))
            i += 3
        elif op in (0xB8, 0xB6, 0xB7) and i + 3 <= n:  # invoke*
            idx = struct.unpack(">H", code[i + 1:i + 3])[0]
            refs.append(("invoke", _resolve_cp(cp, idx)))
            i += 3
        elif op in (0xB9, 0xBA, 0xC8, 0xC9):
            i += 5
        elif op in (0x12, 0x10, 0x15, 0x16, 0x17, 0x18, 0x19, 0x36, 0x37, 0x38, 0x39, 0x3A, 0xA9, 0xBC):
            i += 2
        elif op in (0x11, 0x13, 0x14, 0x84, 0x99, 0x9A, 0x9B, 0x9C, 0x9D, 0x9E, 0x9F, 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xB3, 0xB4, 0xB5, 0xBB, 0xBD, 0xC0, 0xC1, 0xC6, 0xC7):
            i += 3
        elif op == 0xC5:
            i += 4
        elif op == 0xAA:  # tableswitch
            i = (i + 4) & ~3
            low, high = struct.unpack(">ii", code[i + 4:i + 12])
            i += 12 + 4 * (high - low + 1)
        elif op == 0xAB:  # lookupswitch
            i = (i + 4) & ~3
            npairs = struct.unpack(">i", code[i + 4:i + 8])[0]
            i += 8 + 8 * npairs
        elif op == 0xC4:  # wide
            i += 6 if (i + 1 < n and code[i + 1] == 0x84) else 4
        else:
            i += 1
    return refs


def expand_collection_field(field_name: str, field_desc: str, prefix_override: Optional[str] = None) -> List[str]:
    name = FIELD_TO_ID_OVERRIDES.get(field_name.lower(), field_name.lower())
    if "ColorCollection" in field_desc:
        base = name[5:] if name.startswith("dyed_") else name
        return [f"{c}_{base}" for c in DYE_COLORS_ORDER]
    elif "WeatheringCopperCollection" in field_desc:
        res = []
        prefixes = [prefix_override] if prefix_override is not None else ["", "waxed_"]
        for pfx in prefixes:
            for st in COPPER_STATES:
                if name == "copper_block" and st != "":
                    res.append(f"{pfx}{st}copper")
                else:
                    res.append(f"{pfx}{st}{name}")
        return res
    else:
        return [name]


def _heuristic_tab_for_item(name: str, is_block: bool) -> str:
    """Heuristic creative tab classifier for unmapped or obfuscated jar items."""
    if name.endswith("_spawn_egg"):
        return "spawn_eggs"
    if not is_block:
        if any(x in name for x in (
            "sword", "axe", "bow", "crossbow", "trident", "mace", "spear", "shield", "helmet",
            "chestplate", "leggings", "boots", "turtle_shell", "wolf_armor", "horse_armor", "arrow", "totem"
        )) and not any(x in name for x in ("pickaxe",)):
            return "combat"
        if any(x in name for x in (
            "pickaxe", "shovel", "hoe", "shears", "flint_and_steel", "brush", "fishing_rod", "carrot_on_a_stick",
            "warped_fungus_on_a_stick", "lead", "name_tag", "compass", "clock", "spyglass", "map", "bucket",
            "saddle", "harness", "boat", "raft", "minecart", "elytra", "goat_horn", "music_disc", "bundle", "firework_rocket"
        )):
            return "tools_and_utilities"
        if any(x in name for x in (
            "apple", "bread", "porkchop", "beef", "chicken", "mutton", "rabbit", "cod", "salmon", "tropical_fish",
            "pufferfish", "potato", "carrot", "beetroot", "melon_slice", "berries", "cookie", "pie", "cake",
            "stew", "soup", "honey_bottle", "milk_bucket", "potion", "ominous_bottle", "chorus_fruit", "dried_kelp", "rotten_flesh", "spider_eye"
        )):
            return "food_and_drinks"
        return "ingredients"

    if any(name.startswith(c + "_") for c in DYE_COLORS_ORDER) or any(
        x in name for x in ("terracotta", "concrete", "wool", "carpet", "stained_glass", "shulker_box", "candle", "banner", "bed", "cushion")
    ):
        return "colored_blocks"
    if any(x in name for x in (
        "command_block", "barrier", "structure_block", "structure_void", "jigsaw", "light", "test_block", "test_instance"
    )):
        return "op_blocks"
    if any(x in name for x in (
        "redstone", "piston", "observer", "repeater", "comparator", "hopper", "dropper", "dispenser",
        "lever", "button", "pressure_plate", "target", "daylight_detector", "tripwire", "rail", "tnt",
        "sculk_sensor", "calibrated_sculk_sensor", "lectern", "note_block", "crafter", "slime_block", "honey_block"
    )):
        return "redstone_blocks"
    if any(x in name for x in (
        "torch", "lantern", "table", "furnace", "smoker", "anvil", "grindstone", "stonecutter", "loom",
        "chest", "barrel", "shelf", "bookshelf", "chiseled_bookshelf", "sign", "bell", "campfire",
        "cauldron", "brewing_stand", "composter", "beehive", "bee_nest", "respawn_anchor", "lodestone",
        "conduit", "beacon", "end_rod", "froglight", "decorated_pot", "head", "skull", "spawner", "vault", "statue"
    )):
        return "functional_blocks"
    if any(x in name for x in (
        "grass", "dirt", "podzol", "mycelium", "mud", "clay", "gravel", "sand", "ice", "snow", "moss",
        "ore", "raw_", "log", "leaves", "sapling", "propagule", "flower", "tulip", "orchid", "allium",
        "azure_bluet", "daisy", "cornflower", "lily", "rose", "dandelion", "poppy", "torchflower",
        "pitcher", "mushroom", "fungus", "roots", "wart", "vine", "kelp", "seagrass", "coral", "sponge",
        "melon", "pumpkin", "cactus", "bamboo", "sugar_cane", "cocoa", "berry", "sculk", "amethyst", "dripstone"
    )) and not any(x in name for x in ("planks", "stairs", "slab", "fence", "wall", "door", "trapdoor", "stripped_", "bricks", "polished_")):
        return "natural_blocks"
    return "building_blocks"


_heuristic_tab_for_block = lambda name: _heuristic_tab_for_item(name, True)


def categorize_all_items_from_jar(zf: zipfile.ZipFile, all_items: List[str], block_set: Set[str]) -> Dict[str, List[str]]:
    item_set = set(all_items)
    categories: Dict[str, List[str]] = {k: [] for k, _, _ in CREATIVE_TABS_META}
    categories["all_items"] = list(all_items)

    cmt_path = "net/minecraft/world/item/CreativeModeTabs.class"
    assigned: Set[str] = set()

    if cmt_path in zf.namelist():
        try:
            cp, methods = parse_java_class_methods(zf.read(cmt_path))
            copper_fams = []
            if "copperBlockFamilies" in methods:
                for op, ref in _extract_bytecode_ops(cp, methods["copperBlockFamilies"]):
                    if op == "getstatic" and isinstance(ref, tuple) and ref[0] in (
                        "net/minecraft/world/item/Items", "net/minecraft/world/level/block/Blocks"
                    ):
                        copper_fams.append((ref[1][0], ref[1][1]))

            tab_method_groups = {
                "building_blocks":     ["lambda$bootstrap$1"],
                "colored_blocks":      ["lambda$bootstrap$5"],
                "natural_blocks":      ["lambda$bootstrap$7"],
                "functional_blocks":   ["lambda$bootstrap$9", "lambda$bootstrap$10"],
                "redstone_blocks":     ["lambda$bootstrap$13"],
                "tools_and_utilities": ["lambda$bootstrap$18", "lambda$bootstrap$19"],
                "combat":              ["lambda$bootstrap$21", "lambda$bootstrap$22"],
                "food_and_drinks":     ["lambda$bootstrap$24", "lambda$bootstrap$25"],
                "ingredients":         ["lambda$bootstrap$27", "lambda$bootstrap$28", "lambda$bootstrap$29"],
                "spawn_eggs":          ["lambda$bootstrap$31"],
                "op_blocks":           ["lambda$bootstrap$33", "lambda$bootstrap$34"],
            }

            helper_method_items = {
                "generateFireworksAllDurations": ["firework_rocket"],
                "generateSuspiciousStews": ["suspicious_stew"],
                "generateOminousBottles": ["ominous_bottle"],
                "generateEnchantmentBookTypesOnlyMaxLevel": ["enchanted_book"],
                "generateEnchantmentBookTypesAllLevels": ["enchanted_book"],
                "generateInstrumentTypes": ["goat_horn"],
            }

            for tab_key, mnames in tab_method_groups.items():
                tab_list: List[str] = []
                copper_pass = 0
                for mname in mnames:
                    if mname not in methods:
                        continue
                    ops = _extract_bytecode_ops(cp, methods[mname])
                    for op, ref in ops:
                        if op == "getstatic" and isinstance(ref, tuple) and ref[0] in (
                            "net/minecraft/world/item/Items", "net/minecraft/world/level/block/Blocks"
                        ):
                            fn, fd = ref[1]
                            for exp_name in expand_collection_field(fn, fd):
                                if exp_name in item_set and exp_name not in tab_list:
                                    tab_list.append(exp_name)
                                    assigned.add(exp_name)
                        elif op == "invoke" and isinstance(ref, tuple) and ref[1]:
                            called_m = ref[1][0]
                            if called_m == "copperBlockFamilies":
                                pfx = "" if copper_pass == 0 else "waxed_"
                                copper_pass += 1
                                for fn, fd in copper_fams:
                                    for exp_name in expand_collection_field(fn, fd, prefix_override=pfx):
                                        if exp_name in item_set and exp_name not in tab_list:
                                            tab_list.append(exp_name)
                                            assigned.add(exp_name)
                            elif called_m in helper_method_items:
                                for h_item in helper_method_items[called_m]:
                                    if h_item in item_set and h_item not in tab_list:
                                        tab_list.append(h_item)
                                        assigned.add(h_item)
                categories[tab_key] = tab_list
        except Exception as e:
            pass

    for it in all_items:
        if it in assigned:
            continue
        if it in ("short_dry_grass", "tall_dry_grass"):
            categories["natural_blocks"].append(it)
            assigned.add(it)
        elif it in ("ender_dragon_spawn_egg", "wither_spawn_egg") or it.endswith("_spawn_egg"):
            categories["spawn_eggs"].append(it)
            assigned.add(it)
        elif it in ("potion", "splash_potion", "lingering_potion", "suspicious_stew", "ominous_bottle"):
            categories["food_and_drinks"].append(it)
            assigned.add(it)
        elif it == "tipped_arrow":
            categories["combat"].append(it)
            assigned.add(it)
        elif it == "enchanted_book":
            categories["ingredients"].append(it)
            assigned.add(it)
        elif it == "goat_horn" or it == "filled_map" or it.endswith("_map") or it == "written_book":
            categories["tools_and_utilities"].append(it)
            assigned.add(it)
        elif it == "knowledge_book":
            categories["op_blocks"].append(it)
            assigned.add(it)
        else:
            cat = _heuristic_tab_for_item(it, it in block_set)
            categories[cat].append(it)
            assigned.add(it)

    return categories


def categorize_blocks_from_jar(zf: zipfile.ZipFile, block_items: List[str]) -> Dict[str, List[str]]:
    return categorize_all_items_from_jar(zf, block_items, set(block_items))

class CreativeClassifier:
    """Classifies Minecraft items and blocks into the 11 Creative Mode tabs."""

    def __init__(self, tag_mapping: Optional[Dict[str, List[str]]] = None):
        self.tag_mapping = tag_mapping or {}
        # Precompile colored patterns: e.g. ^(red|blue)_wool$
        color_pattern = "|".join(COLORS)
        item_types_pattern = "|".join(COLORED_ITEM_TYPES)
        self.colored_regex = re.compile(rf"^({color_pattern})_({item_types_pattern})$")

    def normalize_id(self, item_id: str) -> str:
        if not item_id:
            return ""
        if item_id.startswith("minecraft:"):
            item_id = item_id[len("minecraft:"):]
        # Remove suffixes like .json or path prefixes
        item_id = item_id.split("/")[-1]
        if item_id.endswith(".json"):
            item_id = item_id[:-5]
        return item_id.lower()

    def classify(self, item_id: str, tags: Optional[List[str]] = None, is_block: bool = True) -> str:
        """
        Classifies an item/block ID into a CreativeTab.
        
        Args:
            item_id: e.g. "minecraft:iron_sword", "oak_stairs", "stone"
            tags: optional list of tag identifiers
            is_block: True if this item has a block model
        """
        raw_id = self.normalize_id(item_id)
        if not raw_id:
            return CreativeTab.BUILDING_BLOCKS.value

        # 1. Spawn Eggs
        if raw_id.endswith("_spawn_egg"):
            return CreativeTab.SPAWN_EGGS.value

        # 2. Operator Utilities
        if any(raw_id.startswith(k) or raw_id == k for k in [
            "command_block", "chain_command_block", "repeating_command_block",
            "barrier", "structure_block", "structure_void", "jigsaw", "light",
            "debug_stick", "test_block"
        ]):
            return CreativeTab.OPERATOR_UTILITIES.value

        # 3. Explicit Mapping
        if raw_id in EXPLICIT_ITEM_MAPPING:
            return EXPLICIT_ITEM_MAPPING[raw_id]

        # 4. Colored Blocks
        if self.colored_regex.match(raw_id):
            return CreativeTab.COLORED_BLOCKS.value
        if any(color in raw_id for color in COLORS) and any(t in raw_id for t in ["stained_glass", "glazed_terracotta", "concrete", "wool", "bed", "candle", "banner", "shulker_box"]):
            return CreativeTab.COLORED_BLOCKS.value

        # 5. Combat
        combat_keywords = [
            "sword", "bow", "crossbow", "shield", "trident", "mace",
            "arrow", "spectral_arrow", "tipped_arrow",
            "helmet", "chestplate", "leggings", "boots",
            "horse_armor", "totem_of_undying"
        ]
        if any(k in raw_id for k in combat_keywords):
            return CreativeTab.COMBAT.value

        # 6. Tools & Utilities
        tool_keywords = [
            "pickaxe", "shovel", "hoe", "fishing_rod", "shears",
            "flint_and_steel", "brush", "spyglass", "compass", "clock",
            "lead", "name_tag", "saddle", "boat", "minecart", "elytra",
            "bundle", "music_disc", "firework", "bucket"
        ]
        if any(k in raw_id for k in tool_keywords):
            return CreativeTab.TOOLS_AND_UTILITIES.value
        # Axe: if not classified, tools
        if raw_id.endswith("_axe") and "pickaxe" not in raw_id:
            return CreativeTab.TOOLS_AND_UTILITIES.value

        # 7. Food & Drinks
        food_keywords = [
            "apple", "bread", "porkchop", "beef", "chicken", "mutton", "rabbit",
            "cod", "salmon", "fish", "carrot", "potato", "beetroot", "stew",
            "soup", "berries", "melon_slice", "cookie", "cake", "pie",
            "chorus_fruit", "honey_bottle", "potion", "juice", "honeycomb"
        ]
        if any(k in raw_id for k in food_keywords):
            return CreativeTab.FOOD_AND_DRINKS.value

        # 8. Redstone Blocks
        redstone_keywords = [
            "redstone", "repeater", "comparator", "piston", "observer",
            "dispenser", "dropper", "hopper", "daylight_detector", "target",
            "lever", "button", "pressure_plate", "tripwire_hook", "sculk_sensor",
            "crafter", "copper_bulb", "lightning_rod", "note_block", "lamp",
            "detector_rail", "activator_rail", "powered_rail"
        ]
        if any(k in raw_id for k in redstone_keywords):
            return CreativeTab.REDSTONE_BLOCKS.value

        # 9. Functional Blocks
        functional_keywords = [
            "table", "furnace", "smoker", "anvil", "chest", "barrel",
            "bell", "lectern", "jukebox", "loom", "grindstone", "stonecutter",
            "scaffolding", "lantern", "torch", "end_rod", "decorated_pot",
            "bookshelf", "cauldron", "composter", "beacon", "conduit",
            "lodestone", "respawn_anchor"
        ]
        if any(k in raw_id for k in functional_keywords):
            return CreativeTab.FUNCTIONAL_BLOCKS.value

        # 10. Natural Blocks
        natural_keywords = [
            "dirt", "grass", "podzol", "mycelium", "ore", "raw_iron", "raw_copper", "raw_gold",
            "log", "wood", "stem", "hyphae", "leaves", "sapling", "flower",
            "tulip", "orchid", "allium", "dandelion", "poppy", "rose", "lily",
            "peony", "sunflower", "lilac", "blossom", "vine", "lichen", "spore",
            "dripleaf", "moss", "fern", "kelp", "seagrass", "coral", "ice",
            "snow", "sand", "gravel", "clay", "obsidian", "netherrack", "basalt",
            "blackstone", "end_stone", "calcite", "dripstone", "mud", "mangrove_roots",
            "fungus", "mushroom", "nylium", "pumpkin", "melon"
        ]
        if any(k in raw_id for k in natural_keywords):
            return CreativeTab.NATURAL_BLOCKS.value

        # 11. Building Blocks
        building_keywords = [
            "stairs", "slab", "wall", "fence", "gate", "door", "trapdoor",
            "planks", "brick", "stone", "cobblestone", "sandstone", "diorite",
            "granite", "andesite", "deepslate", "tuff", "prismarine", "purpur",
            "copper", "chiseled", "polished", "smooth", "pillar", "glass", "pane",
            "terracotta", "concrete", "coral_block", "quartz"
        ]
        if any(k in raw_id for k in building_keywords):
            return CreativeTab.BUILDING_BLOCKS.value

        # 12. Ingredients
        ingredient_keywords = [
            "ingot", "nugget", "gem", "diamond", "emerald", "amethyst", "lapis",
            "quartz", "coal", "charcoal", "stick", "bone", "feather", "gunpowder",
            "string", "leather", "hide", "blaze", "ghast", "magma", "pearl",
            "eye", "slime", "star", "shell", "heart", "shard", "fragment",
            "scrap", "flint", "paper", "book", "bowl", "bottle", "charge",
            "dye", "clay_ball", "brick", "wheat", "seeds"
        ]
        if any(k in raw_id for k in ingredient_keywords):
            return CreativeTab.INGREDIENTS.value

        # Default fallback
        if is_block:
            return CreativeTab.BUILDING_BLOCKS.value
        return CreativeTab.INGREDIENTS.value
