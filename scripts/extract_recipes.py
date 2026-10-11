#!/usr/bin/env python3
"""
Craftify Minecraft Recipe Extractor
Directly extracts recipes from Minecraft server / client jars,
processes them, classifies them according to Minecraft's built-in in-game categories,
and packages them into Craftify .recipe files.
"""

import sys
import os
import re
import json
import shutil
import zipfile
import argparse
import tempfile
import subprocess
from datetime import datetime, timezone

# Minecraft built-in category mapping
MINECRAFT_BUILTIN_CATEGORIES = {
    "building": "Building Blocks",
    "blocks": "Building Blocks",
    "equipment": "Equipment",
    "redstone": "Redstone",
    "misc": "Miscellaneous",
    "food": "Food & Cooking"
}

def format_item_name(item_id: str) -> str:
    """Converts a minecraft identifier (e.g. 'minecraft:iron_pickaxe') to a human-readable title."""
    if not item_id:
        return ""
    raw = item_id.split(":")[-1]
    words = raw.replace("_", " ").split()
    # Capitalize words
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
            # e.g. "minecraft:planks" -> "Planks"
            return format_item_name(ing["tag"])
        if "id" in ing:
            return format_item_name(ing["id"])
    return ""

def process_recipe_json(raw_data: dict, recipe_id: int, version: str) -> dict:
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
        "remarks": remarks if remarks else None
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

def extract_recipes_from_jar(jar_path: str, run_generator: bool = False, version: str = None) -> list:
    """Extracts raw recipe JSONs from a Minecraft jar file."""
    if not os.path.isfile(jar_path):
        raise FileNotFoundError(f"Jar file not found: {jar_path}")

    # Detect version if not provided
    if not version:
        m = re.search(r"(\d+\.\d+(\.\d+)?)", os.path.basename(jar_path))
        version = m.group(1) if m else "1.21.1"

    recipe_jsons = []

    if run_generator:
        java_bin = find_java_executable()
        print(f"[Craftify] Running Minecraft Data Generator using {java_bin}...")
        with tempfile.TemporaryDirectory() as tmp_dir:
            cmd = [
                java_bin,
                "-DbundlerRepoDir=.",
                "-cp", os.path.abspath(jar_path),
                "net.minecraft.data.Main",
                "--reports",
                "--all"
            ]
            print(f"[Craftify] Command: {' '.join(cmd)}")
            try:
                proc = subprocess.run(cmd, cwd=tmp_dir, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120)
                print(f"[Craftify] Generator completed with return code: {proc.returncode}")
                # Look for generated recipes
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
            # Check for nested server jar in bundler
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
        # Match data/minecraft/recipe/*.json or data/minecraft/recipes/*.json
        if (name.startswith("data/minecraft/recipe/") or name.startswith("data/minecraft/recipes/")) and name.endswith(".json"):
            # Exclude bundle datapack overrides if redundant
            try:
                content = json.loads(z.read(name).decode("utf-8"))
                recipes.append(content)
            except Exception:
                continue
    return recipes

def create_recipe_package(jar_path: str, output_path: str, version: str = None, run_generator: bool = False):
    """Main function to create a .recipe package file."""
    if not version:
        m = re.search(r"(\d+\.\d+(\.\d+)?)", os.path.basename(jar_path))
        version = m.group(1) if m else "1.21.1"

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
        # Avoid exact duplicates
        key = (recipe["name"], tuple(recipe["ingredients"]), recipe["output"], recipe["imageremark"])
        if key in seen_keys:
            continue
        seen_keys.add(key)
        processed_recipes.append(recipe)
        next_id += 1

    # Sort alphabetically by name
    processed_recipes.sort(key=lambda r: r["name"])

    # Collect distinct categories present
    categories = sorted(list(set(r["category"] for r in processed_recipes if r["category"])))

    package = {
        "format_version": 1,
        "game_version": version,
        "edition": "Java",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "generator": "Craftify Extractor v1.0",
        "recipe_count": len(processed_recipes),
        "categories": categories,
        "recipes": processed_recipes
    }

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(package, f, indent=2, ensure_ascii=False)

    print(f"[Craftify] Successfully created {output_path} with {len(processed_recipes)} recipes across {len(categories)} categories!")
    return package

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Craftify Minecraft Recipe Extractor")
    parser.add_argument("--jar", required=True, help="Path to server.jar or client jar")
    parser.add_argument("--output", default="1.21.1.recipe", help="Output .recipe file path")
    parser.add_argument("--version", help="Minecraft version (e.g. 1.21.4)")
    parser.add_argument("--run-generator", action="store_true", help="Run net.minecraft.data.Main generator")
    args = parser.parse_args()

    create_recipe_package(args.jar, args.output, args.version, args.run_generator)
