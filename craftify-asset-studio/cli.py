#!/usr/bin/env python3
"""
Craftify Asset Studio CLI
Command-line interface for extracting, rendering, and categorizing Minecraft block & item icons.
"""

import argparse
import os
import sys
import time
from typing import List, Optional

from craftify_asset_studio.classification import ALL_TABS, CreativeClassifier, TAB_DISPLAY_NAMES_ZH
from craftify_asset_studio.extractor import AssetManager, JarScanner
from craftify_asset_studio.exporter import CraftifyExporter, FileExporter
from craftify_asset_studio.renderer import IsometricRenderer

def main():
    parser = argparse.ArgumentParser(
        description="Craftify Asset Studio - Minecraft Model Extractor, Renderer & Creative Categorizer"
    )
    parser.add_argument(
        "--jar",
        type=str,
        help="Path to Minecraft .jar file (if omitted, auto-detects local installed versions)"
    )
    parser.add_argument(
        "--output",
        "-o",
        type=str,
        default="./output",
        help="Output directory (default: ./output)"
    )
    parser.add_argument(
        "--size",
        type=int,
        default=128,
        help="Icon render resolution in pixels (default: 128)"
    )
    parser.add_argument(
        "--category",
        "-c",
        type=str,
        choices=ALL_TABS + ["All"],
        default="All",
        help="Filter to a specific Creative Tab (default: All)"
    )
    parser.add_argument(
        "--extract-raw",
        action="store_true",
        help="Extract raw models and textures to output directory"
    )
    parser.add_argument(
        "--export-craftify",
        type=str,
        metavar="PATH",
        help="Export directly into Craftify Assets.xcassets directory"
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Limit number of items rendered (useful for testing)"
    )
    parser.add_argument(
        "--filter",
        type=str,
        choices=["all", "blocks", "items"],
        default="all",
        help="Export filter mode: all(blocks+items) | blocks(only blocks) | items(only items)"
    )
    parser.add_argument(
        "--export-atlas",
        type=str,
        default=None,
        help="Path to save full creative inventory atlas poster PNG"
    )
    parser.add_argument(
        "--no-supersample",
        action="store_true",
        help="Disable 2x supersampling for faster rendering"
    )

    args = parser.parse_args()

    # 1. Resolve JAR path
    jar_path = args.jar
    if not jar_path:
        local_jars = JarScanner.find_local_minecraft_jars()
        if local_jars:
            jar_path = local_jars[0]["path"]
            print(f"[*] Auto-detected local Minecraft JAR: {local_jars[0]['version']} ({jar_path})")
        else:
            print("[!] Error: No --jar specified and no local Minecraft JAR found in standard paths.")
            sys.exit(1)

    print(f"[*] Loading Minecraft JAR: {jar_path}")
    scanner = JarScanner(jar_path)
    block_models, item_models, texture_count = scanner.scan()
    print(f"[*] Found version: {scanner.version_name}")
    print(f"[*] Indexed {len(block_models)} block models, {len(item_models)} item models, {texture_count} textures")

    asset_manager = AssetManager(jar_path)
    asset_manager.open()

    # 2. Extract raw if requested
    if args.extract_raw:
        raw_out = os.path.join(args.output, "raw_assets")
        print(f"[*] Extracting raw models and textures to {raw_out}...")
        count = asset_manager.extract_raw_assets(raw_out)
        print(f"[+] Extracted {count} raw asset files.")

    # 3. Setup Classifier & Renderer
    classifier = CreativeClassifier(tag_mapping=scanner.tag_mappings)
    renderer = IsometricRenderer(asset_manager)
    exporter = FileExporter(args.output)
    craftify_exporter = CraftifyExporter(args.export_craftify) if args.export_craftify else None

    # Collect unique candidate items (combining items and blocks)
    candidates = []
    seen = set()

    # Add items first
    for path in item_models:
        item_id = os.path.splitext(os.path.basename(path))[0]
        if item_id not in seen:
            seen.add(item_id)
            candidates.append({"id": item_id, "model_id": f"item/{item_id}", "is_block": False})

    # Add blocks that might not have separate item models
    for path in block_models:
        block_id = os.path.splitext(os.path.basename(path))[0]
        if block_id not in seen:
            seen.add(block_id)
            candidates.append({"id": block_id, "model_id": f"block/{block_id}", "is_block": True})

    # Filter by category if requested
    filtered = []
    for cand in candidates:
        cat = classifier.classify(cand["id"], is_block=cand["is_block"])
        cand["category"] = cat
        cand["display_name"] = scanner.get_display_name(cand["id"], lang="en")
        cand["display_name_zh"] = scanner.get_display_name(cand["id"], lang="zh")

        if args.category == "All" or cat == args.category:
            filtered.append(cand)

    if args.filter == "blocks":
        filtered = [x for x in filtered if x["is_block"]]
    elif args.filter == "items":
        filtered = [x for x in filtered if not x["is_block"]]

    if args.limit:
        filtered = filtered[:args.limit]

    print(f"[*] Starting render batch of {len(filtered)} items (target size: {args.size}x{args.size})...")
    catalog_records = []
    start_time = time.time()
    success_count = 0

    for idx, item in enumerate(filtered, 1):
        item_id = item["id"]
        cat = item["category"]
        model_id = item["model_id"]
        display_name = item["display_name"]

        try:
            img = renderer.render(
                model_id,
                target_size=args.size,
                supersample=not args.no_supersample
            )
            if img:
                out_path = exporter.export_icon(
                    img,
                    category=cat,
                    item_id=item_id,
                    display_name=display_name
                )
                if craftify_exporter:
                    craftify_exporter.export_imageset(img, display_name)

                catalog_records.append({
                    "id": item_id,
                    "name": display_name,
                    "name_zh": item["display_name_zh"],
                    "category": cat,
                    "category_zh": TAB_DISPLAY_NAMES_ZH.get(cat, cat),
                    "file_path": out_path,
                    "model_id": model_id,
                    "is_block": item["is_block"]
                })
                success_count += 1
        except Exception as e:
            # Silent skip or trace
            pass

        if idx % 50 == 0 or idx == len(filtered):
            pct = (idx / len(filtered)) * 100.0
            print(f"  [{idx}/{len(filtered)}] ({pct:.1f}%) Rendered {success_count} icons...")

    elapsed = time.time() - start_time
    exporter.write_catalog_json(catalog_records)

    if args.export_atlas:
        print(f"[*] Generating creative inventory atlas poster: {args.export_atlas}")
        renderer.generate_creative_atlas_poster(args.export_atlas)
        print(f"[+] Creative inventory atlas poster saved to: {os.path.abspath(args.export_atlas)}")

    asset_manager.close()

    print(f"\n[+] Render batch complete in {elapsed:.2f}s!")
    print(f"[+] Successfully rendered and categorized: {success_count} items")
    print(f"[+] Output directory: {os.path.abspath(args.output)}")
    if craftify_exporter:
        print(f"[+] Craftify Assets exported to: {os.path.abspath(args.export_craftify)}")

if __name__ == "__main__":
    main()
