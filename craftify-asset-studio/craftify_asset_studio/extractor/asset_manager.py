"""Asset Manager for caching, reading, and exporting raw textures & models."""

import io
import json
import os
import zipfile
from typing import Dict, Optional, Set
from PIL import Image

class AssetManager:
    """Provides cached access to textures and model JSON files inside a Minecraft JAR."""

    def __init__(self, jar_path: str):
        self.jar_path = os.path.abspath(jar_path)
        self._zip: Optional[zipfile.ZipFile] = None
        self._texture_cache: Dict[str, Image.Image] = {}
        self._model_cache: Dict[str, dict] = {}
        self._missing_texture: Optional[Image.Image] = None

    def __enter__(self):
        self.open()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()

    def open(self):
        if self._zip is None:
            self._zip = zipfile.ZipFile(self.jar_path, "r")

    def close(self):
        if self._zip is not None:
            self._zip.close()
            self._zip = None
        self._texture_cache.clear()
        self._model_cache.clear()

    @property
    def zip_file(self) -> zipfile.ZipFile:
        if self._zip is None:
            self.open()
        return self._zip

    @staticmethod
    def normalize_resource_path(res_path: str) -> str:
        """Strips namespace and prefixes: 'minecraft:block/stone' -> 'block/stone'."""
        if not res_path:
            return ""
        if res_path.startswith("minecraft:"):
            res_path = res_path[len("minecraft:"):]
        return res_path.lstrip("/")

    def get_model_json(self, model_id: str) -> Optional[dict]:
        """Loads and parses a model JSON by identifier or path."""
        norm_id = self.normalize_resource_path(model_id)
        if norm_id in self._model_cache:
            return self._model_cache[norm_id]

        candidates = [
            norm_id,
            f"{norm_id}.json",
            f"assets/minecraft/models/{norm_id}.json",
            f"assets/minecraft/models/block/{norm_id}.json",
            f"assets/minecraft/models/item/{norm_id}.json"
        ]

        zf = self.zip_file
        namelist = zf.namelist()
        data = None

        for c in candidates:
            if c in namelist:
                try:
                    data = json.loads(zf.read(c).decode("utf-8"))
                    break
                except Exception:
                    pass

        self._model_cache[norm_id] = data
        return data

    def get_texture_image(self, texture_path: str) -> Image.Image:
        """Retrieves and caches a texture PIL Image (converting animated strips to frame 0)."""
        norm_path = self.normalize_resource_path(texture_path)
        if norm_path in self._texture_cache:
            return self._texture_cache[norm_path]

        if not norm_path.endswith(".png"):
            norm_path += ".png"

        candidates = [
            f"assets/minecraft/textures/{norm_path}",
            f"assets/minecraft/{norm_path}",
            norm_path
        ]

        zf = self.zip_file
        namelist = zf.namelist()
        img: Optional[Image.Image] = None

        for c in candidates:
            if c in namelist:
                try:
                    raw_data = zf.read(c)
                    img = Image.open(io.BytesIO(raw_data)).convert("RGBA")
                    # If animated texture strip (height > width and multiple of width)
                    w, h = img.size
                    if h > w and h % w == 0:
                        img = img.crop((0, 0, w, w))
                    break
                except Exception:
                    pass

        if img is None:
            img = self.get_missing_texture()

        self._texture_cache[norm_path] = img
        return img

    def get_missing_texture(self) -> Image.Image:
        """Returns standard 16x16 magenta-black missing texture checkerboard."""
        if self._missing_texture is not None:
            return self._missing_texture

        img = Image.new("RGBA", (16, 16), (0, 0, 0, 255))
        magenta = (248, 0, 248, 255)
        black = (0, 0, 0, 255)
        for y in range(16):
            for x in range(16):
                color = magenta if ((x < 8 and y < 8) or (x >= 8 and y >= 8)) else black
                img.putpixel((x, y), color)
        self._missing_texture = img
        return img

    def extract_raw_assets(self, output_dir: str, extract_models: bool = True, extract_textures: bool = True) -> int:
        """Extracts raw model JSON files and PNG texture files to target folder."""
        os.makedirs(output_dir, exist_ok=True)
        zf = self.zip_file
        extracted_count = 0

        for name in zf.namelist():
            should_extract = False
            if extract_models and name.startswith("assets/minecraft/models/") and name.endswith(".json"):
                should_extract = True
            elif extract_textures and name.startswith("assets/minecraft/textures/") and name.endswith(".png"):
                should_extract = True

            if should_extract:
                target_path = os.path.join(output_dir, name)
                os.makedirs(os.path.dirname(target_path), exist_ok=True)
                with open(target_path, "wb") as f:
                    f.write(zf.read(name))
                extracted_count += 1

        return extracted_count
