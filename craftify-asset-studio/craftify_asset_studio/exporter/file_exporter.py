"""File Exporter for organizing rendered icons into category directories."""

import json
import os
from typing import Callable, Dict, List, Optional
from PIL import Image

class FileExporter:
    """Exports rendered icons into directory trees grouped by Creative Inventory categories."""

    def __init__(self, output_root: str):
        self.output_root = os.path.abspath(output_root)

    def export_icon(
        self,
        image: Image.Image,
        category: str,
        item_id: str,
        display_name: str,
        export_by_category: bool = True
    ) -> str:
        """
        Saves a single rendered image.
        Returns the absolute output file path.
        """
        if export_by_category:
            target_dir = os.path.join(self.output_root, category)
        else:
            target_dir = self.output_root

        os.makedirs(target_dir, exist_ok=True)
        filename = f"{item_id}.png"
        file_path = os.path.join(target_dir, filename)
        image.save(file_path, "PNG")
        return file_path

    def write_catalog_json(self, catalog_data: List[dict], filename: str = "catalog.json") -> str:
        """Writes catalog metadata JSON summarizing all items, categories, and paths."""
        os.makedirs(self.output_root, exist_ok=True)
        catalog_path = os.path.join(self.output_root, filename)
        with open(catalog_path, "w", encoding="utf-8") as f:
            json.dump(catalog_data, f, indent=2, ensure_ascii=False)
        return catalog_path
