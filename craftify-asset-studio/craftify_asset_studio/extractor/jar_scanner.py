"""Minecraft JAR Scanner and Version Inspector."""

import json
import os
import zipfile
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

class JarScanner:
    """Scans Minecraft .jar files to index models, textures, language strings, and tags."""

    def __init__(self, jar_path: str):
        self.jar_path = os.path.abspath(jar_path)
        if not os.path.isfile(self.jar_path):
            raise FileNotFoundError(f"Minecraft JAR file not found at: {self.jar_path}")

        self.version_name = self._detect_version()
        self.block_model_paths: List[str] = []
        self.item_model_paths: List[str] = []
        self.texture_paths: Set[str] = set()
        self.lang_en: Dict[str, str] = {}
        self.lang_zh: Dict[str, str] = {}
        self.tag_mappings: Dict[str, List[str]] = {}

    def _detect_version(self) -> str:
        # Check if version.json exists in JAR
        try:
            with zipfile.ZipFile(self.jar_path, "r") as z:
                if "version.json" in z.namelist():
                    data = json.loads(z.read("version.json").decode("utf-8"))
                    if "id" in data:
                        return data["id"]
                    if "name" in data:
                        return data["name"]
        except Exception:
            pass

        # Fallback to parent directory or jar filename
        file_name = os.path.splitext(os.path.basename(self.jar_path))[0]
        return file_name

    def scan(self) -> Tuple[List[str], List[str], int]:
        """
        Scans the jar file and indexes all available assets.
        Returns (block_models, item_models, texture_count).
        """
        self.block_model_paths.clear()
        self.item_model_paths.clear()
        self.texture_paths.clear()

        with zipfile.ZipFile(self.jar_path, "r") as z:
            namelist = z.namelist()
            for name in namelist:
                if name.startswith("assets/") and name.endswith(".json"):
                    if "/models/block/" in name:
                        self.block_model_paths.append(name)
                    elif "/models/item/" in name:
                        self.item_model_paths.append(name)
                elif name.startswith("assets/") and name.endswith(".png"):
                    self.texture_paths.add(name)

            # Load language translations
            for lang_name, target_dict in [("en_us.json", self.lang_en), ("zh_cn.json", self.lang_zh)]:
                cand = f"assets/minecraft/lang/{lang_name}"
                if cand in namelist:
                    try:
                        target_dict.update(json.loads(z.read(cand).decode("utf-8")))
                    except Exception:
                        pass

            # Load item tags
            for name in namelist:
                if name.startswith("data/") and "/tags/item/" in name and name.endswith(".json"):
                    try:
                        tag_data = json.loads(z.read(name).decode("utf-8"))
                        values = tag_data.get("values", [])
                        tag_id = name.split("/tags/item/")[-1].replace(".json", "")
                        self.tag_mappings[tag_id] = values
                    except Exception:
                        pass

        return self.block_model_paths, self.item_model_paths, len(self.texture_paths)

    def get_display_name(self, item_id: str, lang: str = "en") -> str:
        """Resolves human-readable name for an item ID."""
        raw_id = item_id.split(":")[-1]
        keys = [
            f"block.minecraft.{raw_id}",
            f"item.minecraft.{raw_id}",
            raw_id
        ]
        lang_dict = self.lang_zh if lang == "zh" and self.lang_zh else self.lang_en
        for k in keys:
            if k in lang_dict:
                return lang_dict[k]
        # Fallback to Title Cased string: 'mossy_cobblestone' -> 'Mossy Cobblestone'
        return " ".join(word.capitalize() for word in raw_id.replace("_", " ").split())

    @staticmethod
    def find_local_minecraft_jars() -> List[Dict[str, str]]:
        """
        Scans macOS standard Minecraft directory:
        ~/Library/Application Support/minecraft/versions/
        Returns list of found JARs with version information.
        """
        results = []
        mac_mc_versions = Path.home() / "Library" / "Application Support" / "minecraft" / "versions"
        if not mac_mc_versions.exists():
            return results

        try:
            for item in sorted(mac_mc_versions.iterdir()):
                if item.is_dir():
                    jar_cand = item / f"{item.name}.jar"
                    if jar_cand.is_file():
                        results.append({
                            "version": item.name,
                            "path": str(jar_cand),
                            "size_mb": round(jar_cand.stat().st_size / (1024 * 1024), 1)
                        })
        except Exception:
            pass

        return results
