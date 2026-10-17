"""Direct Exporter for Craftify iOS app (Assets.xcassets compatible)."""

import json
import os
from typing import Optional
from PIL import Image

class CraftifyExporter:
    """Exports rendered icons directly into Craftify's Assets.xcassets format."""

    def __init__(self, xcassets_dir: str):
        self.xcassets_dir = os.path.abspath(xcassets_dir)

    def export_imageset(
        self,
        image_3x: Image.Image,
        asset_name: str,
        preserve_existing: bool = True
    ) -> str:
        """
        Creates an .imageset directory with @1x, @2x, @3x images and Contents.json.
        asset_name: e.g. "Crafting Table", "Mossy Cobblestone"
        """
        imageset_dir = os.path.join(self.xcassets_dir, f"{asset_name}.imageset")
        if preserve_existing and os.path.exists(imageset_dir):
            return imageset_dir

        os.makedirs(imageset_dir, exist_ok=True)

        w, h = image_3x.size
        # @1x is 1/3, @2x is 2/3, @3x is full
        w1, h1 = max(1, w // 3), max(1, h // 3)
        w2, h2 = max(1, (w * 2) // 3), max(1, (h * 2) // 3)

        img_1x = image_3x.resize((w1, h1), Image.Resampling.LANCZOS)
        img_2x = image_3x.resize((w2, h2), Image.Resampling.LANCZOS)

        file_1x = f"{asset_name}.png"
        file_2x = f"{asset_name} 1.png"
        file_3x = f"{asset_name} 2.png"

        img_1x.save(os.path.join(imageset_dir, file_1x), "PNG")
        img_2x.save(os.path.join(imageset_dir, file_2x), "PNG")
        image_3x.save(os.path.join(imageset_dir, file_3x), "PNG")

        contents_json = {
            "images": [
                {
                    "filename": file_1x,
                    "idiom": "universal",
                    "scale": "1x"
                },
                {
                    "filename": file_2x,
                    "idiom": "universal",
                    "scale": "2x"
                },
                {
                    "filename": file_3x,
                    "idiom": "universal",
                    "scale": "3x"
                }
            ],
            "info": {
                "author": "xcode",
                "version": 1
            }
        }

        with open(os.path.join(imageset_dir, "Contents.json"), "w", encoding="utf-8") as f:
            json.dump(contents_json, f, indent=2)

        return imageset_dir
