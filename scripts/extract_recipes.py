#!/usr/bin/env python3
"""
Craftify Minecraft Recipe Extractor & Icon Packager
Directly extracts recipes from Minecraft server / client jars,
processes them, classifies them according to Minecraft's built-in in-game categories,
renders 3D/2D inventory icons via Craftify Asset Studio's IsometricRenderer (run.py),
and packages both recipes and version-isolated icons into Craftify .recipe files.
"""

import argparse
import base64
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime, timezone
from typing import Callable, Dict, List, Optional

# Ensure craftify-asset-studio is on sys.path so IsometricRenderer can be imported
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
ASSET_STUDIO_DIR = os.path.join(PROJECT_ROOT, "craftify-asset-studio")
if os.path.isdir(ASSET_STUDIO_DIR) and ASSET_STUDIO_DIR not in sys.path:
    sys.path.insert(0, ASSET_STUDIO_DIR)

# Minecraft built-in category mapping
MINECRAFT_BUILTIN_CATEGORIES = {
    "building": "Building Blocks",
    "blocks": "Building Blocks",
    "equipment": "Equipment",
    "redstone": "Redstone",
    "misc": "Miscellaneous",
    "food": "Food & Cooking",
}

# Representative item fallbacks for Minecraft recipe ingredient tags (#minecraft:*)
TAG_ICON_FALLBACKS = {
    "acacia_logs": "acacia_log",
    "anvil": "anvil",
    "arrows": "arrow",
    "bamboo_blocks": "bamboo_block",
    "banners": "white_banner",
    "beds": "red_bed",
    "birch_logs": "birch_log",
    "boats": "oak_boat",
    "buttons": "oak_button",
    "candles": "candle",
    "carpets": "white_carpet",
    "cherry_logs": "cherry_log",
    "chest_boats": "oak_chest_boat",
    "coals": "coal",
    "compasses": "compass",
    "copper_tool_materials": "copper_ingot",
    "creeper_drop_music_discs": "music_disc_cat",
    "crimson_stems": "crimson_stem",
    "dark_oak_logs": "dark_oak_log",
    "decorated_pot_ingredients": "brick",
    "decorated_pot_sherds": "angler_pottery_sherd",
    "diamond_tool_materials": "diamond",
    "doors": "oak_door",
    "eggs": "egg",
    "fence_gates": "oak_fence_gate",
    "fences": "oak_fence",
    "fishes": "cod",
    "flowers": "dandelion",
    "furnace_materials": "cobblestone",
    "gold_tool_materials": "gold_ingot",
    "hanging_signs": "oak_hanging_sign",
    "iron_tool_materials": "iron_ingot",
    "jungle_logs": "jungle_log",
    "leaves": "oak_leaves",
    "lectern_books": "writable_book",
    "logs": "oak_log",
    "logs_that_burn": "oak_log",
    "mangrove_logs": "mangrove_log",
    "metal_nuggets": "iron_nugget",
    "netherite_tool_materials": "netherite_ingot",
    "oak_logs": "oak_log",
    "pale_oak_logs": "pale_oak_log",
    "planks": "oak_planks",
    "rails": "rail",
    "sand": "sand",
    "saplings": "oak_sapling",
    "shulker_boxes": "shulker_box",
    "signs": "oak_sign",
    "slabs": "oak_slab",
    "small_flowers": "poppy",
    "smelts_to_glass": "sand",
    "soul_fire_base_blocks": "soul_sand",
    "spruce_logs": "spruce_log",
    "stairs": "oak_stairs",
    "stone_bricks": "stone_bricks",
    "stone_buttons": "stone_button",
    "stone_crafting_materials": "cobblestone",
    "stone_tool_materials": "cobblestone",
    "terracotta": "terracotta",
    "trapdoors": "oak_trapdoor",
    "trim_materials": "amethyst_shard",
    "trim_templates": "ward_armor_trim_smithing_template",
    "trimmable_armor": "iron_chestplate",
    "walls": "cobblestone_wall",
    "warped_stems": "warped_stem",
    "wooden_buttons": "oak_button",
    "wooden_doors": "oak_door",
    "wooden_fences": "oak_fence",
    "wooden_pressure_plates": "oak_pressure_plate",
    "wooden_slabs": "oak_slab",
    "wooden_stairs": "oak_stairs",
    "wooden_tool_materials": "oak_planks",
    "wooden_trapdoors": "oak_trapdoor",
    "wool": "white_wool",
    "wool_carpets": "white_carpet",
}


def format_item_name(item_id: str) -> str:
    """Converts a minecraft identifier (e.g. 'minecraft:iron_pickaxe') to a human-readable title."""
    if not item_id:
        return ""
    raw = item_id.lstrip("#").split(":")[-1]
    words = raw.replace("_", " ").split()
    capitalized = []
    for word in words:
        if word in ["of", "and", "the", "in", "with"] and len(capitalized) > 0:
            capitalized.append(word)
        else:
            capitalized.append(word.capitalize())
    return " ".join(capitalized)


def resolve_ingredient_name(ing) -> str:
    """Extracts a readable item name from a recipe ingredient definition."""
    if not ing:
        return ""
    if isinstance(ing, str):
        return format_item_name(ing)
    if isinstance(ing, list):
        if len(ing) > 0:
            return resolve_ingredient_name(ing[0])
        return ""
    if isinstance(ing, dict):
        if "item" in ing:
            return format_item_name(ing["item"])
        if "tag" in ing:
            return format_item_name(ing["tag"])
        if "id" in ing:
            return format_item_name(ing["id"])
    return ""


def process_recipe_json(raw_data: dict, recipe_id: int, version: str) -> Optional[dict]:
    """Processes a raw Minecraft recipe JSON into Craftify Recipe structure."""
    recipe_type = raw_data.get("type", "")
    category_key = raw_data.get("category", "").lower()

    # Minecraft Built-in Category fallback
    category = MINECRAFT_BUILTIN_CATEGORIES.get(category_key, "")

    result_name = ""
    result_image = ""
    output_count = 1
    imageremark = "Crafting Table"
    remarks = ""
    ingredients = [""] * 9

    # Determine Result
    result_field = raw_data.get("result")
    if isinstance(result_field, str):
        result_name = format_item_name(result_field)
        result_image = result_name
    elif isinstance(result_field, dict):
        item_id = result_field.get("id") or result_field.get("item", "")
        result_name = format_item_name(item_id)
        result_image = result_name
        output_count = result_field.get("count", 1)

    # 1. Shaped Crafting
    if "crafting_shaped" in recipe_type:
        imageremark = "Crafting Table"
        if not category:
            category = "Miscellaneous"
        pattern = raw_data.get("pattern", [])
        key_map = raw_data.get("key", {})

        # 3x3 grid layout
        grid = [["" for _ in range(3)] for _ in range(3)]
        for r, row_str in enumerate(pattern[:3]):
            for c, char in enumerate(row_str[:3]):
                if char != " " and char in key_map:
                    grid[r][c] = resolve_ingredient_name(key_map[char])

        ingredients = []
        for r in range(3):
            for c in range(3):
                ingredients.append(grid[r][c])

    # 2. Shapeless Crafting
    elif "crafting_shapeless" in recipe_type:
        imageremark = "Crafting Table"
        if not category:
            category = "Miscellaneous"
        raw_ings = raw_data.get("ingredients", [])
        resolved = [resolve_ingredient_name(i) for i in raw_ings]
        ingredients = (resolved + [""] * 9)[:9]

    # 3. Smelting / Blasting / Smoking / Campfire
    elif any(t in recipe_type for t in ["smelting", "blasting", "smoking", "campfire_cooking"]):
        if "blasting" in recipe_type:
            imageremark = "Blast Furnace"
        elif "smoking" in recipe_type:
            imageremark = "Smoker"
        elif "campfire" in recipe_type:
            imageremark = "Campfire"
        else:
            imageremark = "Furnace"

        if not category:
            category = "Food & Cooking" if "cooking" in recipe_type or "smoking" in recipe_type else "Building Blocks"

        raw_ing = raw_data.get("ingredient")
        input_name = resolve_ingredient_name(raw_ing)
        # Furnace layout in Craftify: 2 slots [input, fuel/empty]
        ingredients = [input_name, ""]
        cooking_time = raw_data.get("cookingtime")
        xp = raw_data.get("experience")
        remarks_parts = []
        if cooking_time:
            remarks_parts.append(f"Cooking Time: {cooking_time} ticks")
        if xp:
            remarks_parts.append(f"XP: {xp}")
        remarks = ", ".join(remarks_parts)

    # 4. Stonecutting
    elif "stonecutting" in recipe_type:
        imageremark = "Stonecutter"
        if not category:
            category = "Building Blocks"
        raw_ing = raw_data.get("ingredient")
        input_name = resolve_ingredient_name(raw_ing)
        ingredients = [input_name] + [""] * 8

    # 5. Smithing
    elif "smithing" in recipe_type:
        imageremark = "Smithing Table"
        if not category:
            category = "Equipment"
        template = resolve_ingredient_name(raw_data.get("template"))
        base = resolve_ingredient_name(raw_data.get("base"))
        addition = resolve_ingredient_name(raw_data.get("addition"))
        ingredients = [template, base, addition] + [""] * 6
        if not result_name and "smithing_trim" in recipe_type:
            result_name = f"{base} (Trimmed)"
            result_image = base

    # 6. Special recipes
    elif "special" in recipe_type or "decorated_pot" in recipe_type:
        imageremark = "Crafting Table"
        if not category:
            category = "Miscellaneous"
        if not result_name:
            clean_type = recipe_type.replace("minecraft:crafting_special_", "").replace("_", " ").title()
            result_name = clean_type
            result_image = "Crafting Table"

    if not result_name:
        return None

    return {
        "id": recipe_id,
        "name": result_name,
        "image": result_image,
        "ingredients": ingredients,
        "alternateIngredients": None,
        "alternateIngredients1": None,
        "alternateIngredients2": None,
        "alternateIngredients3": None,
        "output": output_count,
        "alternateOutput": None,
        "alternateOutput1": None,
        "alternateOutput2": None,
        "alternateOutput3": None,
        "category": category,
        "imageremark": imageremark,
        "remarks": remarks if remarks else None,
    }


def find_java_executable() -> str:
    """Finds a valid Java runtime on macOS / Linux."""
    jvm_dirs = ["/Library/Java/JavaVirtualMachines", os.path.expanduser("~/Library/Java/JavaVirtualMachines")]
    for jvm_root in jvm_dirs:
        if os.path.isdir(jvm_root):
            for entry in sorted(os.listdir(jvm_root), reverse=True):
                candidate = os.path.join(jvm_root, entry, "Contents/Home/bin/java")
                if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                    return candidate

    java_home = os.environ.get("JAVA_HOME")
    if java_home:
        candidate = os.path.join(java_home, "bin/java")
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate

    system_java = shutil.which("java")
    if system_java:
        return system_java

    return "java"


def jar_has_client_assets(jar_path: str) -> bool:
    """Checks whether a .jar file contains client textures and models for icon rendering."""
    if not jar_path or not os.path.isfile(jar_path):
        return False
    try:
        with zipfile.ZipFile(jar_path, "r") as z:
            return any(n.startswith("assets/minecraft/textures/") for n in z.namelist())
    except Exception:
        return False


def resolve_asset_jar(jar_path: str, version: str, client_jar_path: Optional[str] = None) -> Optional[str]:
    """Resolves the best Minecraft client .jar containing textures/models for rendering icons."""
    if client_jar_path and jar_has_client_assets(client_jar_path):
        return client_jar_path
    if jar_has_client_assets(jar_path):
        return jar_path

    # Search local Minecraft installations for a client jar matching `version`
    try:
        from craftify_asset_studio.extractor.jar_scanner import JarScanner

        local_jars = JarScanner.find_local_minecraft_jars()
        for entry in local_jars:
            if version and (version in entry["version"] or entry["version"] in version):
                if jar_has_client_assets(entry["path"]):
                    return entry["path"]
        for entry in local_jars:
            if jar_has_client_assets(entry["path"]):
                return entry["path"]
    except Exception:
        pass
    return None


def collect_recipe_item_keys(recipes: List[dict]) -> set:
    """Collects all unique item display names referenced across all recipes and stations."""
    keys = {
        "Crafting Table",
        "Furnace",
        "Blast Furnace",
        "Smoker",
        "Stonecutter",
        "Smithing Table",
        "Campfire",
    }
    for r in recipes:
        for field in ("name", "image", "imageremark"):
            val = r.get(field)
            if val and isinstance(val, str) and val.strip():
                keys.add(val.strip())
        for ing_field in (
            "ingredients",
            "alternateIngredients",
            "alternateIngredients1",
            "alternateIngredients2",
            "alternateIngredients3",
        ):
            ing_list = r.get(ing_field)
            if isinstance(ing_list, list):
                for ing in ing_list:
                    if ing and isinstance(ing, str) and ing.strip():
                        keys.add(ing.strip())
    return keys


def _resolve_tag_from_jar(zf: zipfile.ZipFile, namelist: set, tag_name: str, visited: Optional[set] = None) -> Optional[str]:
    """Resolves a Minecraft item tag to its first concrete item ID inside the jar."""
    if visited is None:
        visited = set()
    if tag_name in visited:
        return None
    visited.add(tag_name)

    for prefix in ("data/minecraft/tags/item/", "data/minecraft/tags/items/"):
        path = f"{prefix}{tag_name}.json"
        if path in namelist:
            try:
                data = json.loads(zf.read(path).decode("utf-8"))
                for val in data.get("values", []):
                    val_str = val.get("id", "") if isinstance(val, dict) else str(val)
                    if not val_str:
                        continue
                    if val_str.startswith("#"):
                        sub_tag = val_str.lstrip("#").split(":")[-1]
                        resolved = _resolve_tag_from_jar(zf, namelist, sub_tag, visited)
                        if resolved:
                            return resolved
                    else:
                        return val_str.split(":")[-1]
            except Exception:
                pass
    return None


def render_icons_for_package(
    asset_jar_path: str,
    recipes: List[dict],
    icon_size: int = 64,
    include_all_items: bool = True,
    renderer_instance=None,
    progress_callback: Optional[Callable[[int, int, str], None]] = None,
) -> Dict[str, str]:
    """
    Renders inventory-style icons (via craftify-asset-studio's IsometricRenderer)
    for all items in the version & recipes, returning {display_name: base64_png}.
    """
    from craftify_asset_studio.renderer.isometric_renderer import IsometricRenderer

    owns_renderer = False
    renderer = renderer_instance
    if renderer is None:
        renderer = IsometricRenderer(asset_jar_path, icon_size=icon_size, ssaa=2)
        owns_renderer = True

    try:
        keys_to_render = collect_recipe_item_keys(recipes)

        # Build reverse lookup from English display name -> raw item_id
        en_to_raw: Dict[str, str] = {}
        for k, v in renderer.lang_en.items():
            if (k.startswith("block.minecraft.") or k.startswith("item.minecraft.")) and isinstance(v, str):
                parts = k.split(".")
                if len(parts) == 3:
                    raw_id = parts[2]
                    en_to_raw[v.lower()] = raw_id

        if include_all_items:
            for item_id in renderer.all_items:
                keys_to_render.add(format_item_name(item_id))
                en_label = renderer.lang_en.get(
                    f"block.minecraft.{item_id}",
                    renderer.lang_en.get(f"item.minecraft.{item_id}"),
                )
                if en_label:
                    keys_to_render.add(en_label)

        all_items_set = set(renderer.all_items)
        sorted_keys = sorted(keys_to_render)
        total = len(sorted_keys)

        raw_b64_cache: Dict[str, Optional[str]] = {}
        icons: Dict[str, str] = {}

        for idx, display_key in enumerate(sorted_keys):
            raw_candidate = display_key.lstrip("#").strip().lower().replace(" ", "_")
            if raw_candidate.endswith("_(trimmed)"):
                raw_candidate = raw_candidate.replace("_(trimmed)", "")

            if raw_candidate in TAG_ICON_FALLBACKS:
                raw_id = TAG_ICON_FALLBACKS[raw_candidate]
            elif raw_candidate in all_items_set:
                raw_id = raw_candidate
            elif display_key.lower() in en_to_raw:
                raw_id = en_to_raw[display_key.lower()]
            else:
                tag_resolved = _resolve_tag_from_jar(renderer.zf, renderer.namelist, raw_candidate)
                raw_id = tag_resolved if tag_resolved else raw_candidate

            if raw_id not in raw_b64_cache:
                try:
                    img = renderer.render_item(raw_id, target_size=icon_size)
                    if img is not None and img.getbbox() is not None:
                        buf = io.BytesIO()
                        img.save(buf, format="PNG", optimize=True)
                        raw_b64_cache[raw_id] = base64.b64encode(buf.getvalue()).decode("ascii")
                    else:
                        raw_b64_cache[raw_id] = None
                except Exception:
                    raw_b64_cache[raw_id] = None

            b64_val = raw_b64_cache.get(raw_id)
            if b64_val:
                icons[display_key] = b64_val

            if progress_callback and (idx % 25 == 0 or idx == total - 1):
                progress_callback(idx + 1, total, display_key)

        return icons
    finally:
        if owns_renderer and renderer is not None:
            renderer.close()


def extract_recipes_from_jar(jar_path: str, run_generator: bool = False, version: str = None) -> list:
    """Extracts raw recipe JSONs from a Minecraft jar file."""
    if not os.path.isfile(jar_path):
        raise FileNotFoundError(f"Jar file not found: {jar_path}")

    if not version:
        m = re.search(r"(\d+\.\d+(\.\d+)?|\d{2}w\d{2}[a-z])", os.path.basename(jar_path))
        version = m.group(1) if m else "1.21.1"

    recipe_jsons = []

    if run_generator:
        java_bin = find_java_executable()
        print(f"[Craftify] Running Minecraft Data Generator using {java_bin}...")
        with tempfile.TemporaryDirectory() as tmp_dir:
            cmd = [
                java_bin,
                "-DbundlerRepoDir=.",
                "-cp",
                os.path.abspath(jar_path),
                "net.minecraft.data.Main",
                "--reports",
                "--all",
            ]
            print(f"[Craftify] Command: {' '.join(cmd)}")
            try:
                proc = subprocess.run(
                    cmd,
                    cwd=tmp_dir,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=120,
                )
                print(f"[Craftify] Generator completed with return code: {proc.returncode}")
                gen_recipe_dir = os.path.join(tmp_dir, "generated", "data", "minecraft", "recipe")
                if not os.path.isdir(gen_recipe_dir):
                    gen_recipe_dir = os.path.join(tmp_dir, "generated", "data", "minecraft", "recipes")
                if os.path.isdir(gen_recipe_dir):
                    for fname in sorted(os.listdir(gen_recipe_dir)):
                        if fname.endswith(".json"):
                            with open(os.path.join(gen_recipe_dir, fname), "r", encoding="utf-8") as f:
                                recipe_jsons.append(json.load(f))
            except Exception as e:
                print(f"[Craftify] Warning: Data generator run failed ({e}). Falling back to direct jar extraction.")

    # Fallback or fast extraction directly from jar
    if not recipe_jsons:
        print(f"[Craftify] Extracting recipes directly from jar: {jar_path}...")
        with zipfile.ZipFile(jar_path, "r") as z:
            nested_jars = [n for n in z.namelist() if n.startswith("META-INF/versions/") and n.endswith(".jar")]
            if nested_jars:
                print(f"[Craftify] Found bundler inner jar: {nested_jars[0]}")
                nested_data = z.read(nested_jars[0])
                with tempfile.NamedTemporaryFile(suffix=".jar") as tmp_jar:
                    tmp_jar.write(nested_data)
                    tmp_jar.flush()
                    with zipfile.ZipFile(tmp_jar.name, "r") as nz:
                        recipe_jsons.extend(read_recipes_from_zip(nz))
            else:
                recipe_jsons.extend(read_recipes_from_zip(z))

    return recipe_jsons


def read_recipes_from_zip(z: zipfile.ZipFile) -> list:
    recipes = []
    for name in z.namelist():
        if (name.startswith("data/minecraft/recipe/") or name.startswith("data/minecraft/recipes/")) and name.endswith(".json"):
            try:
                content = json.loads(z.read(name).decode("utf-8"))
                recipes.append(content)
            except Exception:
                continue
    return recipes


def create_recipe_package(
    jar_path: str,
    output_path: str,
    version: str = None,
    run_generator: bool = False,
    client_jar_path: Optional[str] = None,
    icon_size: int = 64,
    include_icons: bool = True,
    include_all_items: bool = True,
    renderer_instance=None,
    progress_callback: Optional[Callable[[int, int, str], None]] = None,
):
    """Main function to create a .recipe package file with bundled inventory icons."""
    if not version:
        m = re.search(r"(\d+\.\d+(\.\d+)?|\d{2}w\d{2}[a-z])", os.path.basename(jar_path))
        version = m.group(1) if m else os.path.splitext(os.path.basename(jar_path))[0]

    print(f"[Craftify] Processing recipes for Minecraft {version} from {jar_path}...")
    raw_recipes = extract_recipes_from_jar(jar_path, run_generator=run_generator, version=version)
    print(f"[Craftify] Extracted {len(raw_recipes)} raw recipe definitions.")

    processed_recipes = []
    seen_keys = set()
    next_id = 1

    for raw in raw_recipes:
        recipe = process_recipe_json(raw, next_id, version)
        if not recipe:
            continue
        key = (recipe["name"], tuple(recipe["ingredients"]), recipe["output"], recipe["imageremark"])
        if key in seen_keys:
            continue
        seen_keys.add(key)
        processed_recipes.append(recipe)
        next_id += 1

    processed_recipes.sort(key=lambda r: r["name"])
    categories = sorted(list(set(r["category"] for r in processed_recipes if r["category"])))

    icons: Dict[str, str] = {}
    if include_icons:
        asset_jar = jar_path if renderer_instance is not None else resolve_asset_jar(jar_path, version, client_jar_path)
        if asset_jar or renderer_instance is not None:
            print(f"[Craftify] Rendering inventory icons for Minecraft {version} via IsometricRenderer ({asset_jar})...")
            try:
                icons = render_icons_for_package(
                    asset_jar_path=asset_jar,
                    recipes=processed_recipes,
                    icon_size=icon_size,
                    include_all_items=include_all_items,
                    renderer_instance=renderer_instance,
                    progress_callback=progress_callback,
                )
                print(f"[Craftify] Rendered and bundled {len(icons)} inventory icons into .recipe package.")
            except Exception as e:
                print(f"[Craftify] Warning: Icon rendering failed ({e}). Packaging recipes without embedded icons.")
        else:
            print("[Craftify] Note: No client assets found in jar; packaging recipes without embedded icons.")

    package = {
        "format_version": 2,
        "game_version": version,
        "edition": "Java",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "generator": "Craftify Extractor v2.0 (IsometricRenderer)",
        "recipe_count": len(processed_recipes),
        "icon_count": len(icons),
        "categories": categories,
        "recipes": processed_recipes,
        "icons": icons if icons else None,
    }

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(package, f, indent=2, ensure_ascii=False)

    print(
        f"[Craftify] Successfully created {output_path} with {len(processed_recipes)} recipes "
        f"and {len(icons)} version-isolated icons across {len(categories)} categories!"
    )
    return package


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Craftify Minecraft Recipe Extractor & Icon Packager")
    parser.add_argument("--jar", required=True, help="Path to server.jar or client jar")
    parser.add_argument("--client-jar", help="Optional path to client .jar if --jar is a server-only jar")
    parser.add_argument("--output", default="1.21.1.recipe", help="Output .recipe file path")
    parser.add_argument("--version", help="Minecraft version (e.g. 1.21.1, 26w14a, 26.3)")
    parser.add_argument("--icon-size", type=int, default=64, help="Rendered inventory icon size in pixels (default: 64)")
    parser.add_argument("--no-icons", action="store_true", help="Skip rendering and embedding inventory icons")
    parser.add_argument("--recipe-icons-only", action="store_true", help="Only render icons referenced by recipes")
    parser.add_argument("--run-generator", action="store_true", help="Run net.minecraft.data.Main generator")
    args = parser.parse_args()

    create_recipe_package(
        jar_path=args.jar,
        output_path=args.output,
        version=args.version,
        run_generator=args.run_generator,
        client_jar_path=args.client_jar,
        icon_size=args.icon_size,
        include_icons=not args.no_icons,
        include_all_items=not args.recipe_icons_only,
    )
