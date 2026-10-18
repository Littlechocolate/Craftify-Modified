"""
High-Performance Minecraft 3D Isometric & 2D Item Software Rasterizer (Z-Buffer + SSAA).
Implements exact parametric UV bilinear interpolation, view-space backface culling,
gui_light directional shading, colormap tinting, and special entity block modeling.
"""

import io
import json
import math
import os
import zipfile
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from ..classification import (
    categorize_all_items_from_jar,
    CREATIVE_TABS_META,
    DYE_COLOR_RGB,
    SPAWN_EGG_COLORS,
    get_spawn_egg_tints,
)

def rot_x(deg: float) -> np.ndarray:
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    return np.array([[1.0, 0.0, 0.0], [0.0, c, -s], [0.0, s, c]], dtype=np.float64)

def rot_y(deg: float) -> np.ndarray:
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    return np.array([[c, 0.0, s], [0.0, 1.0, 0.0], [-s, 0.0, c]], dtype=np.float64)

def rot_z(deg: float) -> np.ndarray:
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]], dtype=np.float64)

DYE_COLORS_ORDER = [
    "white", "orange", "magenta", "light_blue", "yellow", "lime", "pink", "gray",
    "light_gray", "cyan", "purple", "blue", "brown", "green", "red", "black"
]

class IsometricRenderer:
    """
    High-precision, high-performance software rasterizer for Minecraft block models
    and 2D inventory items.
    """

    def __init__(self, jar_file_path: Any, icon_size: int = 64, ssaa: int = 2):
        if hasattr(jar_file_path, "jar_path"):
            self.jar_path = os.path.abspath(jar_file_path.jar_path)
            if hasattr(jar_file_path, "zip_file") and jar_file_path.zip_file is not None:
                self.zf = jar_file_path.zip_file
            else:
                self.zf = zipfile.ZipFile(self.jar_path, "r")
        else:
            self.jar_path = os.path.abspath(str(jar_file_path))
            self.zf = zipfile.ZipFile(self.jar_path, "r")
        self.icon_size = icon_size
        self.ssaa = ssaa
        self.render_size = icon_size * ssaa
        self.namelist = set(self.zf.namelist())

        self.model_cache: Dict[str, Dict[str, Any]] = {}
        self.resolved_model_cache: Dict[str, Dict[str, Any]] = {}
        self.texture_cache: Dict[Tuple[str, bool], Optional[np.ndarray]] = {}
        self.colormaps: Dict[str, np.ndarray] = {}
        self.lang_en: Dict[str, str] = {}
        self.lang_zh: Dict[str, str] = {}
        self._load_colormaps()
        self._load_languages()
        self.block_set, self.all_items = self._discover_all_items()
        self.block_items = sorted(self.block_set)
        self.non_block_items = sorted(set(self.all_items) - self.block_set)
        self.categories = categorize_all_items_from_jar(self.zf, self.all_items, self.block_set)

    def close(self):
        try:
            self.zf.close()
        except Exception:
            pass
        self.texture_cache.clear()
        self.model_cache.clear()
        self.resolved_model_cache.clear()

    def _discover_all_items(self) -> Tuple[Set[str], List[str]]:
        blockstates = {
            n.split("/")[-1][:-5]
            for n in self.namelist
            if n.startswith("assets/minecraft/blockstates/") and n.endswith(".json")
        }
        items_json = {
            n.split("/")[-1][:-5]
            for n in self.namelist
            if n.startswith("assets/minecraft/items/") and n.endswith(".json")
        }
        item_models_json = {
            n.split("/")[-1][:-5]
            for n in self.namelist
            if n.startswith("assets/minecraft/models/item/") and n.endswith(".json")
        }
        exclude = {"air", "cave_air", "void_air"}
        if items_json:
            all_valid = sorted(items_json - exclude)
            blocks_valid = (blockstates & items_json) - exclude
        elif item_models_json:
            base_models = {
                m for m in item_models_json
                if not any(m.startswith(p) and m[-2:].isdigit() for p in ("clock_", "compass_", "recovery_compass_", "light_"))
                and not any(s in m for s in ("_pulling_", "_in_hand", "_throwing", "_blocking", "_open_"))
                and not m.endswith("_trim")
                and not m.startswith("template_")
                and m != "generated"
                and m != "handheld"
                and m != "handheld_rod"
                and m != "handheld_mace"
            }
            all_valid = sorted(base_models - exclude)
            blocks_valid = (blockstates & base_models) - exclude
        else:
            all_valid = sorted(blockstates - exclude)
            blocks_valid = blockstates - exclude
        return blocks_valid, all_valid

    def is_block_item(self, item_name: str) -> bool:
        return item_name in self.block_set

    def _load_languages(self):
        en_path = "assets/minecraft/lang/en_us.json"
        if en_path in self.namelist:
            try:
                self.lang_en = json.loads(self.zf.read(en_path).decode("utf-8"))
            except Exception:
                pass
        zh_path = "assets/minecraft/lang/zh_cn.json"
        if zh_path in self.namelist:
            try:
                self.lang_zh = json.loads(self.zf.read(zh_path).decode("utf-8"))
            except Exception:
                pass

    def get_display_name(self, block_id: str) -> str:
        for prefix in ("block.minecraft.", "item.minecraft."):
            key = prefix + block_id
            if key in self.lang_zh:
                return f"{self.lang_zh[key]} ({self.lang_en.get(key, block_id)})"
            if key in self.lang_en:
                return self.lang_en[key]
        return block_id.replace("_", " ").title()

    def _load_colormaps(self):
        for cmap in ("grass", "foliage", "dry_foliage"):
            p = f"assets/minecraft/textures/colormap/{cmap}.png"
            if p in self.namelist:
                try:
                    img = Image.open(io.BytesIO(self.zf.read(p))).convert("RGBA")
                    self.colormaps[cmap] = np.array(img)
                except Exception:
                    pass

    @staticmethod
    def _clean_id(res_id: Any) -> str:
        if not res_id:
            return ""
        if isinstance(res_id, dict):
            res_id = res_id.get("sprite", "")
        if not isinstance(res_id, str):
            return ""
        if res_id.startswith("minecraft:"):
            return res_id[10:]
        return res_id

    def get_tint_color(self, tint_spec: Dict[str, Any]) -> Tuple[int, int, int]:
        if not tint_spec:
            return (255, 255, 255)
        ttype = tint_spec.get("type", "")
        if ttype == "minecraft:constant":
            val = tint_spec.get("value", -1) & 0xFFFFFF
            return ((val >> 16) & 0xFF, (val >> 8) & 0xFF, val & 0xFF)
        elif ttype in ("minecraft:grass", "minecraft:foliage", "minecraft:dry_foliage"):
            cmap_name = ttype.split(":")[-1]
            temp = max(0.0, min(1.0, float(tint_spec.get("temperature", 0.5))))
            down = max(0.0, min(1.0, float(tint_spec.get("downfall", 1.0)))) * temp
            x = min(255, max(0, int((1.0 - temp) * 255)))
            y = min(255, max(0, int((1.0 - down) * 255)))
            if cmap_name in self.colormaps:
                px = self.colormaps[cmap_name][y, x]
                return (int(px[0]), int(px[1]), int(px[2]))
            return (121, 192, 90)
        elif "default" in tint_spec:
            val = tint_spec.get("default", -1) & 0xFFFFFF
            return ((val >> 16) & 0xFF, (val >> 8) & 0xFF, val & 0xFF)
        return (255, 255, 255)

    def load_raw_model(self, model_id: str) -> Dict[str, Any]:
        model_id = self._clean_id(model_id)
        if model_id in self.model_cache:
            return self.model_cache[model_id]
        path = f"assets/minecraft/models/{model_id}.json"
        if path not in self.namelist:
            self.model_cache[model_id] = {}
            return {}
        try:
            data = json.loads(self.zf.read(path).decode("utf-8"))
            self.model_cache[model_id] = data
            return data
        except Exception:
            self.model_cache[model_id] = {}
            return {}

    def resolve_model(self, model_id: str) -> Dict[str, Any]:
        model_id = self._clean_id(model_id)
        if model_id in self.resolved_model_cache:
            return self.resolved_model_cache[model_id]

        chain = []
        parent_ids = []
        curr = model_id
        visited = set()
        while curr and curr not in visited:
            visited.add(curr)
            parent_ids.append(curr)
            if curr.startswith("builtin/"):
                chain.append({"_builtin": curr})
                break
            raw = self.load_raw_model(curr)
            if not raw:
                # Try fallback prefix
                if not curr.startswith("block/") and not curr.startswith("item/"):
                    raw = self.load_raw_model(f"block/{curr}") or self.load_raw_model(f"item/{curr}")
                if not raw:
                    break
            chain.append(raw)
            parent = raw.get("parent")
            curr = self._clean_id(parent) if parent else None

        textures: Dict[str, Any] = {}
        elements = None
        display: Dict[str, Any] = {}
        gui_light = "side"
        builtin = None

        for node in reversed(chain):
            if "_builtin" in node:
                builtin = node["_builtin"]
                continue
            if "gui_light" in node:
                gui_light = node["gui_light"]
            if "textures" in node:
                textures.update(node["textures"])
            if "elements" in node:
                elements = node["elements"]
            if "display" in node:
                for k, v in node["display"].items():
                    display[k] = v

        resolved_textures: Dict[str, str] = {}
        for k, v in textures.items():
            val = v
            depth = 0
            while isinstance(val, str) and val.startswith("#") and depth < 12:
                ref_key = val[1:]
                val = textures.get(ref_key, "")
                depth += 1
            resolved_textures[k] = self._clean_id(val)

        res = {
            "model_id": model_id,
            "parent_chain": parent_ids,
            "textures": resolved_textures,
            "elements": elements,
            "display": display,
            "gui_light": gui_light,
            "builtin": builtin,
        }
        self.resolved_model_cache[model_id] = res
        return res

    def load_texture(self, tex_id: Any, crop_square: bool = True) -> Optional[np.ndarray]:
        tex_id = self._clean_id(tex_id)
        if not tex_id:
            return None
        cache_key = (tex_id, crop_square)
        if cache_key in self.texture_cache:
            return self.texture_cache[cache_key]

        if tex_id.startswith("textures/"):
            path = f"assets/minecraft/{tex_id}"
            if not path.endswith(".png"):
                path += ".png"
        else:
            path = f"assets/minecraft/textures/{tex_id}.png"

        if path not in self.namelist:
            self.texture_cache[cache_key] = None
            return None

        try:
            img = Image.open(io.BytesIO(self.zf.read(path))).convert("RGBA")
            w, h = img.size
            if crop_square and h > w and (f"{path}.mcmeta" in self.namelist or h % w == 0):
                img = img.crop((0, 0, w, w))
            arr = np.array(img, dtype=np.float32)
            self.texture_cache[cache_key] = arr
            return arr
        except Exception:
            self.texture_cache[cache_key] = None
            return None

    def _get_face_geom(self, from_pt, to_pt, face_name: str, uv_override=None):
        """
        Exact Minecraft face geometry and default UV bounds.
        Corners are ordered so that vertex 0 is UV (u1, v1), vertex 1 is (u2, v1),
        vertex 2 is (u2, v2), vertex 3 is (u1, v2).
        """
        x1, y1, z1 = from_pt
        x2, y2, z2 = to_pt
        if face_name == "up":
            verts = np.array([[x1, y2, z1], [x2, y2, z1], [x2, y2, z2], [x1, y2, z2]], dtype=np.float64)
            normal = np.array([0.0, 1.0, 0.0])
            uv = [x1, z1, x2, z2]
        elif face_name == "down":
            verts = np.array([[x1, y1, z2], [x2, y1, z2], [x2, y1, z1], [x1, y1, z1]], dtype=np.float64)
            normal = np.array([0.0, -1.0, 0.0])
            uv = [x1, 16.0 - z2, x2, 16.0 - z1]
        elif face_name == "north":
            verts = np.array([[x2, y2, z1], [x1, y2, z1], [x1, y1, z1], [x2, y1, z1]], dtype=np.float64)
            normal = np.array([0.0, 0.0, -1.0])
            uv = [16.0 - x2, 16.0 - y2, 16.0 - x1, 16.0 - y1]
        elif face_name == "south":
            verts = np.array([[x1, y2, z2], [x2, y2, z2], [x2, y1, z2], [x1, y1, z2]], dtype=np.float64)
            normal = np.array([0.0, 0.0, 1.0])
            uv = [x1, 16.0 - y2, x2, 16.0 - y1]
        elif face_name == "west":
            verts = np.array([[x1, y2, z1], [x1, y2, z2], [x1, y1, z2], [x1, y1, z1]], dtype=np.float64)
            normal = np.array([-1.0, 0.0, 0.0])
            uv = [z1, 16.0 - y2, z2, 16.0 - y1]
        elif face_name == "east":
            verts = np.array([[x2, y2, z2], [x2, y2, z1], [x2, y1, z1], [x2, y1, z2]], dtype=np.float64)
            normal = np.array([1.0, 0.0, 0.0])
            uv = [16.0 - z2, 16.0 - y2, 16.0 - z1, 16.0 - y1]
        else:
            verts = np.zeros((4, 3), dtype=np.float64)
            normal = np.array([0.0, 1.0, 0.0])
            uv = [0.0, 0.0, 16.0, 16.0]

        if uv_override is not None:
            uv = list(uv_override)
        return verts, normal, uv

    def _compute_shade(self, normal_view: np.ndarray, gui_light: str = "side", shade_enabled: bool = True) -> float:
        if not shade_enabled or gui_light == "front":
            return 1.0
        nx, ny, nz = normal_view
        norm = math.sqrt(nx * nx + ny * ny + nz * nz)
        if norm > 1e-6:
            nx, ny, nz = nx / norm, ny / norm, nz / norm
        l1 = max(0.0, nx * (-0.42) + ny * 0.82 + nz * 0.38)
        l2 = max(0.0, nx * 0.15 + ny * 0.35 + nz * 0.65)
        shade = 0.44 + 0.42 * l1 + 0.18 * l2
        return max(0.45, min(1.0, shade))

    def render_elements_to_buffers(
        self,
        elements: List[Dict[str, Any]],
        textures: Dict[str, str],
        gui_transform: Dict[str, Any],
        tints: List[Dict[str, Any]],
        color_buf: np.ndarray,
        depth_buf: np.ndarray,
        gui_light: str = "side",
        extra_offset: Tuple[float, float, float] = (0.0, 0.0, 0.0),
        sub_rot_y: float = 0.0,
    ):
        rot_deg = gui_transform.get("rotation", [30, 225, 0])
        trans = gui_transform.get("translation", [0, 0, 0])
        scale = gui_transform.get("scale", [0.625, 0.625, 0.625])

        R_gui = rot_x(rot_deg[0]) @ rot_y(rot_deg[1]) @ rot_z(rot_deg[2])
        S_gui = np.array(scale, dtype=np.float64)
        T_gui = np.array(trans, dtype=np.float64)
        offset_vec = np.array(extra_offset, dtype=np.float64)
        R_sub = rot_y(sub_rot_y) if abs(sub_rot_y) > 1e-3 else None

        N = color_buf.shape[0]
        half_N = N / 2.0
        px_per_unit = N / 16.0

        face_draw_list = []

        for elem_idx, elem in enumerate(elements):
            from_pt = elem.get("from", [0, 0, 0])
            to_pt = elem.get("to", [16, 16, 16])
            shade_enabled = elem.get("shade", True)
            elem_rot = elem.get("rotation")
            faces = elem.get("faces", {})

            for face_name, face_spec in faces.items():
                tex_ref = face_spec.get("texture", "")
                clean_key = tex_ref.lstrip("#") if isinstance(tex_ref, str) else ""
                tex_id = textures.get(clean_key, self._clean_id(tex_ref))
                tex_arr = self.load_texture(tex_id)
                if tex_arr is None:
                    continue

                verts, normal, uv = self._get_face_geom(from_pt, to_pt, face_name, face_spec.get("uv"))
                if elem.get("shade_direction_override") == "up":
                    normal = np.array([0.0, 1.0, 0.0])

                if elem_rot:
                    origin = np.array(elem_rot.get("origin", [8, 8, 8]), dtype=np.float64)
                    axis = elem_rot.get("axis", "y")
                    angle = float(elem_rot.get("angle", 0))
                    rescale = elem_rot.get("rescale", False)
                    inv_cos = 1.0 / max(0.2, math.cos(math.radians(angle)))
                    if axis == "x":
                        R_el = rot_x(angle)
                        rs = [1.0, inv_cos, inv_cos] if rescale else [1.0, 1.0, 1.0]
                    elif axis == "y":
                        R_el = rot_y(angle)
                        rs = [inv_cos, 1.0, inv_cos] if rescale else [1.0, 1.0, 1.0]
                    else:
                        R_el = rot_z(angle)
                        rs = [inv_cos, inv_cos, 1.0] if rescale else [1.0, 1.0, 1.0]
                    verts = (verts - origin) @ R_el.T * np.array(rs) + origin
                    normal = normal @ R_el.T

                if R_sub is not None:
                    verts = (verts - 8.0) @ R_sub.T + 8.0
                    normal = normal @ R_sub.T

                verts = verts + offset_vec
                v_centered = verts - 8.0
                v_view = (v_centered @ R_gui.T) * S_gui + T_gui
                n_view = normal @ R_gui.T

                sx = half_N + v_view[:, 0] * px_per_unit
                sy = half_N - v_view[:, 1] * px_per_unit
                sz = v_view[:, 2] + elem_idx * 1e-3

                dx1, dy1 = sx[1] - sx[0], sy[1] - sy[0]
                dx3, dy3 = sx[3] - sx[0], sy[3] - sy[0]
                det = dx1 * dy3 - dx3 * dy1

                if det <= 1e-5:
                    continue

                shade = self._compute_shade(n_view, gui_light, shade_enabled)
                tint_rgb = (255, 255, 255)
                if "tintindex" in face_spec:
                    t_idx = face_spec["tintindex"]
                    if tints and 0 <= t_idx < len(tints):
                        tint_rgb = self.get_tint_color(tints[t_idx])
                    elif "stonecutter" not in tex_id:
                        tint_rgb = (121, 192, 90)

                uv_rot = face_spec.get("rotation", 0)
                avg_z = float(np.mean(sz))
                has_semi_alpha = bool(np.any((tex_arr[:, :, 3] > 0) & (tex_arr[:, :, 3] < 250)))
                face_draw_list.append((has_semi_alpha, avg_z, sx, sy, sz, uv, uv_rot, tex_arr, shade, tint_rgb))

        opaque_faces = [f for f in face_draw_list if not f[0]]
        trans_faces = sorted([f for f in face_draw_list if f[0]], key=lambda x: x[1])

        for _, _, sx, sy, sz, uv, uv_rot, tex_arr, shade, tint_rgb in (opaque_faces + trans_faces):
            self._rasterize_face(sx, sy, sz, uv, uv_rot, tex_arr, shade, tint_rgb, color_buf, depth_buf)

    def _rasterize_face(self, sx, sy, sz, uv, uv_rot, tex_arr, shade, tint_rgb, color_buf, depth_buf):
        N = color_buf.shape[0]
        x_min = max(0, int(math.floor(min(sx))))
        x_max = min(N - 1, int(math.ceil(max(sx))))
        y_min = max(0, int(math.floor(min(sy))))
        y_max = min(N - 1, int(math.ceil(max(sy))))
        if x_min > x_max or y_min > y_max:
            return

        x0, y0, z0 = sx[0], sy[0], sz[0]
        dx1, dy1, dz1 = sx[1] - x0, sy[1] - y0, sz[1] - z0
        dx3, dy3, dz3 = sx[3] - x0, sy[3] - y0, sz[3] - z0
        det = dx1 * dy3 - dx3 * dy1
        if abs(det) < 1e-6:
            return
        inv_det = 1.0 / det

        xs = np.arange(x_min, x_max + 1, dtype=np.float64) + 0.5
        ys = np.arange(y_min, y_max + 1, dtype=np.float64) + 0.5
        gx, gy = np.meshgrid(xs, ys)

        rx = gx - x0
        ry = gy - y0
        s = (rx * dy3 - ry * dx3) * inv_det
        t = (dx1 * ry - dy1 * rx) * inv_det

        eps = -1e-4
        mask = (s >= eps) & (s <= 1.0 - eps) & (t >= eps) & (t <= 1.0 - eps)
        if not np.any(mask):
            return

        s_c = np.clip(s[mask], 0.0, 0.999999)
        t_c = np.clip(t[mask], 0.0, 0.999999)
        z_vals = z0 + s_c * dz1 + t_c * dz3

        u1, v1, u2, v2 = uv
        corners_uv = [(u1, v1), (u2, v1), (u2, v2), (u1, v2)]
        if uv_rot == 90:
            corners_uv = [corners_uv[3], corners_uv[0], corners_uv[1], corners_uv[2]]
        elif uv_rot == 180:
            corners_uv = [corners_uv[2], corners_uv[3], corners_uv[0], corners_uv[1]]
        elif uv_rot == 270:
            corners_uv = [corners_uv[1], corners_uv[2], corners_uv[3], corners_uv[0]]

        cu0, cv0 = corners_uv[0]
        cu1, cv1 = corners_uv[1]
        cu3, cv3 = corners_uv[3]

        u_vals = cu0 + s_c * (cu1 - cu0) + t_c * (cu3 - cu0)
        v_vals = cv0 + s_c * (cv1 - cv0) + t_c * (cv3 - cv0)

        th, tw = tex_arr.shape[:2]
        tx = np.clip((u_vals * (tw / 16.0)).astype(np.int32), 0, tw - 1)
        ty = np.clip((v_vals * (th / 16.0)).astype(np.int32), 0, th - 1)

        sampled = tex_arr[ty, tx]
        alpha = sampled[:, 3]
        valid_a = alpha > 2.0
        if not np.any(valid_a):
            return

        my, mx = np.where(mask)
        my = my[valid_a] + y_min
        mx = mx[valid_a] + x_min
        z_vals = z_vals[valid_a]
        sampled = sampled[valid_a]

        cur_z = depth_buf[my, mx]
        z_pass = z_vals >= (cur_z - 1e-3)
        if not np.any(z_pass):
            return

        my = my[z_pass]
        mx = mx[z_pass]
        z_vals = z_vals[z_pass]
        sampled = sampled[z_pass]

        rgb = sampled[:, :3] * (np.array(tint_rgb, dtype=np.float32) / 255.0) * shade
        a = sampled[:, 3:4] / 255.0

        opaque_px = a[:, 0] >= 0.98
        if np.any(opaque_px):
            oy, ox = my[opaque_px], mx[opaque_px]
            depth_buf[oy, ox] = z_vals[opaque_px]
            color_buf[oy, ox, :3] = rgb[opaque_px]
            color_buf[oy, ox, 3] = 255.0

        semi_px = ~opaque_px
        if np.any(semi_px):
            sy_i, sx_i = my[semi_px], mx[semi_px]
            sa = a[semi_px]
            srgb = rgb[semi_px]
            dst_rgb = color_buf[sy_i, sx_i, :3]
            dst_a = color_buf[sy_i, sx_i, 3:4] / 255.0
            out_a = sa + dst_a * (1.0 - sa)
            out_rgb = (srgb * sa + dst_rgb * dst_a * (1.0 - sa)) / np.maximum(out_a, 1e-5)
            color_buf[sy_i, sx_i, :3] = out_rgb
            color_buf[sy_i, sx_i, 3:4] = out_a * 255.0
            depth_buf[sy_i, sx_i] = np.maximum(depth_buf[sy_i, sx_i], z_vals[semi_px])

    def render_2d_layer_icon(self, resolved_model: Dict[str, Any], tints: List[Dict[str, Any]], target_size: int) -> Image.Image:
        textures = resolved_model.get("textures", {})
        canvas = np.zeros((target_size, target_size, 4), dtype=np.float32)
        for layer_idx in range(5):
            key = f"layer{layer_idx}"
            if key not in textures:
                break
            tex_arr = self.load_texture(textures[key])
            if tex_arr is None:
                continue
            tint_rgb = (255, 255, 255)
            if tints and layer_idx < len(tints):
                tint_rgb = self.get_tint_color(tints[layer_idx])
            pil_layer = Image.fromarray(tex_arr.astype(np.uint8), "RGBA").resize(
                (target_size, target_size), Image.Resampling.NEAREST
            )
            l_arr = np.array(pil_layer, dtype=np.float32)
            l_rgb = l_arr[:, :, :3] * (np.array(tint_rgb, dtype=np.float32) / 255.0)
            l_a = l_arr[:, :, 3:4] / 255.0
            dst_a = canvas[:, :, 3:4] / 255.0
            out_a = l_a + dst_a * (1.0 - l_a)
            canvas[:, :, :3] = (l_rgb * l_a + canvas[:, :, :3] * dst_a * (1.0 - l_a)) / np.maximum(out_a, 1e-5)
            canvas[:, :, 3:4] = out_a * 255.0
        return Image.fromarray(np.clip(canvas, 0, 255).astype(np.uint8), "RGBA")

    def get_item_model_spec(self, item_name: str) -> Dict[str, Any]:
        item_path = f"assets/minecraft/items/{item_name}.json"
        if item_path in self.namelist:
            try:
                item_def = json.loads(self.zf.read(item_path).decode("utf-8"))
                return item_def.get("model", {})
            except Exception:
                pass
        item_model_path = f"assets/minecraft/models/item/{item_name}.json"
        if item_model_path in self.namelist:
            return {"type": "minecraft:model", "model": f"minecraft:item/{item_name}"}
        return {"type": "minecraft:model", "model": f"minecraft:block/{item_name}"}

    def extract_primary_leaf_model_id(self, spec: Dict[str, Any]) -> str:
        """从复杂的 select/condition/range_dispatch/special 物品定义中解析出用于 GUI 检视的主模型路径。"""
        mtype = spec.get("type", "minecraft:model")
        if mtype == "minecraft:model":
            return spec.get("model", "")
        elif mtype == "minecraft:special":
            return spec.get("base", "")
        elif mtype == "minecraft:select":
            if spec.get("property") == "minecraft:display_context":
                for c in spec.get("cases", []):
                    w = c.get("when", [])
                    if w == "gui" or (isinstance(w, list) and "gui" in w):
                        return self.extract_primary_leaf_model_id(c.get("model", {}))
            if "fallback" in spec:
                return self.extract_primary_leaf_model_id(spec["fallback"])
            if spec.get("cases"):
                return self.extract_primary_leaf_model_id(spec["cases"][0].get("model", {}))
        elif mtype == "minecraft:condition":
            return self.extract_primary_leaf_model_id(spec.get("on_false", spec.get("on_true", {})))
        elif mtype == "minecraft:range_dispatch":
            if spec.get("entries"):
                return self.extract_primary_leaf_model_id(spec["entries"][0].get("model", {}))
            if "fallback" in spec:
                return self.extract_primary_leaf_model_id(spec["fallback"])
        elif mtype == "minecraft:composite":
            if spec.get("models"):
                return self.extract_primary_leaf_model_id(spec["models"][0])
        return ""

    def render(
        self,
        item_name: str,
        target_size: Optional[int] = None,
        custom_gui_transform: Optional[Dict[str, Any]] = None,
        supersample: bool = True
    ) -> Image.Image:
        """
        Renders an item or block model into an inventory icon.
        """
        out_size = target_size or self.icon_size
        ssaa_factor = self.ssaa if supersample else 1
        render_res = out_size * ssaa_factor

        # Clean name
        clean_name = self._clean_id(item_name)
        if clean_name.startswith("item/"):
            clean_name = clean_name[5:]
        elif clean_name.startswith("block/"):
            clean_name = clean_name[6:]

        model_spec = self.get_item_model_spec(clean_name)

        color_buf = np.zeros((render_res, render_res, 4), dtype=np.float32)
        depth_buf = np.full((render_res, render_res), -1e9, dtype=np.float64)

        res_2d = self._dispatch_model_spec(
            model_spec, color_buf, depth_buf, out_size, custom_gui_transform=custom_gui_transform
        )
        if res_2d is not None:
            return res_2d

        img_hi = Image.fromarray(np.clip(color_buf, 0, 255).astype(np.uint8), "RGBA")
        if ssaa_factor > 1:
            return img_hi.resize((out_size, out_size), Image.Resampling.LANCZOS)
        return img_hi

    render_item = render

    def _dispatch_model_spec(
        self,
        spec: Dict[str, Any],
        color_buf: np.ndarray,
        depth_buf: np.ndarray,
        out_size: int,
        extra_offset: Tuple[float, float, float] = (0.0, 0.0, 0.0),
        custom_gui_transform: Optional[Dict[str, Any]] = None,
        sub_rot_y: float = 0.0,
    ) -> Optional[Image.Image]:
        mtype = spec.get("type", "minecraft:model")
        if mtype == "minecraft:select":
            if spec.get("property") == "minecraft:display_context":
                for case in spec.get("cases", []):
                    when_val = case.get("when", [])
                    if when_val == "gui" or (isinstance(when_val, list) and "gui" in when_val):
                        return self._dispatch_model_spec(
                            case.get("model", {}), color_buf, depth_buf, out_size, extra_offset, custom_gui_transform, sub_rot_y
                        )
            fallback = spec.get("fallback")
            if fallback:
                return self._dispatch_model_spec(fallback, color_buf, depth_buf, out_size, extra_offset, custom_gui_transform, sub_rot_y)
            cases = spec.get("cases", [])
            if cases:
                return self._dispatch_model_spec(cases[0].get("model", {}), color_buf, depth_buf, out_size, extra_offset, custom_gui_transform, sub_rot_y)
        elif mtype == "minecraft:condition":
            return self._dispatch_model_spec(
                spec.get("on_false", spec.get("on_true", {})), color_buf, depth_buf, out_size, extra_offset, custom_gui_transform, sub_rot_y
            )
        elif mtype == "minecraft:range_dispatch":
            entries = spec.get("entries", [])
            if entries:
                return self._dispatch_model_spec(entries[0].get("model", {}), color_buf, depth_buf, out_size, extra_offset, custom_gui_transform, sub_rot_y)
            if "fallback" in spec:
                return self._dispatch_model_spec(spec["fallback"], color_buf, depth_buf, out_size, extra_offset, custom_gui_transform, sub_rot_y)
        elif mtype == "minecraft:composite":
            for sub in spec.get("models", []):
                tf_obj = sub.get("transformation", {})
                trans = tf_obj.get("translation", [0.0, 0.0, 0.0])
                left_rot = tf_obj.get("left_rotation", [0.0, 0.0, 0.0, 1.0])
                child_rot_y = sub_rot_y
                if isinstance(left_rot, list) and len(left_rot) == 4:
                    qy, qw = float(left_rot[1]), float(left_rot[3])
                    if abs(qy) > 1e-3:
                        angle_rad = 2.0 * math.atan2(qy, qw)
                        child_rot_y += math.degrees(angle_rad)
                self._dispatch_model_spec(
                    sub,
                    color_buf,
                    depth_buf,
                    out_size,
                    (extra_offset[0] + trans[0] * 16.0, extra_offset[1] + trans[1] * 16.0, extra_offset[2] - trans[2] * 16.0),
                    custom_gui_transform,
                    child_rot_y,
                )
            return None
        elif mtype == "minecraft:special":
            return self._render_special_model(spec, color_buf, depth_buf, custom_gui_transform)
        elif mtype == "minecraft:model":
            model_id = spec.get("model", "")
            tints = spec.get("tints", [])
            clean_m = self._clean_id(model_id)
            resolved = self.resolve_model(model_id)
            if not tints and (clean_m.endswith("_spawn_egg") or "spawn_egg" in clean_m):
                textures = resolved.get("textures", {})
                l0 = self._clean_id(textures.get("layer0", ""))
                is_template_egg = (
                    l0 in ("item/spawn_egg", "spawn_egg", "minecraft:item/spawn_egg")
                    or "layer1" in textures
                    or any("template_spawn_egg" in p for p in resolved.get("parent_chain", []))
                )
                if is_template_egg:
                    egg_name = clean_m.split("/")[-1]
                    tints = get_spawn_egg_tints(egg_name)
            if resolved["builtin"] == "builtin/generated" or (not resolved["elements"] and "layer0" in resolved["textures"]):
                return self.render_2d_layer_icon(resolved, tints, out_size)
            if not resolved["elements"]:
                if "shield" in clean_m:
                    return self._render_special_model({"model": {"type": "minecraft:shield"}}, color_buf, depth_buf, custom_gui_transform)
                elif "copper_golem" in clean_m:
                    return self._render_special_model({"model": {"type": "minecraft:copper_golem_statue"}}, color_buf, depth_buf, custom_gui_transform)
                elif "chest" in clean_m:
                    tex = "ender" if "ender_chest" in clean_m else ("trapped" if "trapped_chest" in clean_m else "normal")
                    return self._render_special_model({"model": {"type": "minecraft:chest", "texture": tex}}, color_buf, depth_buf, custom_gui_transform)
                elif "shulker_box" in clean_m:
                    c = clean_m.replace("item/", "").replace("block/", "").replace("_shulker_box", "")
                    tex = f"shulker_{c}" if c and c != "shulker_box" else "shulker"
                    return self._render_special_model({"model": {"type": "minecraft:shulker_box", "texture": tex}}, color_buf, depth_buf, custom_gui_transform)
                elif "head" in clean_m or "skull" in clean_m:
                    for k in ("skeleton", "wither_skeleton", "zombie", "creeper", "piglin", "dragon"):
                        if k in clean_m:
                            return self._render_special_model({"model": {"type": "minecraft:head", "kind": k}}, color_buf, depth_buf, custom_gui_transform)
                    return self._render_special_model({"model": {"type": "minecraft:head", "kind": "player"}}, color_buf, depth_buf, custom_gui_transform)
                elif "banner" in clean_m:
                    for c in DYE_COLORS_ORDER:
                        if clean_m.startswith(c) or f"_{c}" in clean_m:
                            return self._render_special_model({"model": {"type": "minecraft:banner", "color": c}}, color_buf, depth_buf, custom_gui_transform)
                    return self._render_special_model({"model": {"type": "minecraft:banner", "color": "white"}}, color_buf, depth_buf, custom_gui_transform)
                elif "decorated_pot" in clean_m:
                    return self._render_special_model({"model": {"type": "minecraft:decorated_pot"}}, color_buf, depth_buf, custom_gui_transform)
                elif "conduit" in clean_m:
                    return self._render_special_model({"model": {"type": "minecraft:conduit"}}, color_buf, depth_buf, custom_gui_transform)
                elif "bed" in clean_m:
                    for c in DYE_COLORS_ORDER:
                        if c in clean_m:
                            return self._render_special_model({"model": {"type": "minecraft:bed", "color": c}}, color_buf, depth_buf, custom_gui_transform)
                    return self._render_special_model({"model": {"type": "minecraft:bed", "color": "red"}}, color_buf, depth_buf, custom_gui_transform)
            if resolved["elements"]:
                gui_tf = custom_gui_transform or resolved["display"].get(
                    "gui", {"rotation": [30, 225, 0], "translation": [0, 0, 0], "scale": [0.625, 0.625, 0.625]}
                )
                if abs(extra_offset[2]) > 0.1 or "bed_head" in model_id or "bed_foot" in model_id:
                    if not custom_gui_transform:
                        gui_tf = {"rotation": [30, 135, 0], "translation": [0, 2, 0], "scale": [0.50, 0.50, 0.50]}
                    if "bed_head" in model_id:
                        extra_offset = (0.0, 0.0, -8.0)
                    elif "bed_foot" in model_id:
                        extra_offset = (0.0, 0.0, 8.0)
                self.render_elements_to_buffers(
                    resolved["elements"],
                    resolved["textures"],
                    gui_tf,
                    tints,
                    color_buf,
                    depth_buf,
                    resolved["gui_light"],
                    extra_offset,
                    sub_rot_y=sub_rot_y,
                )
        return None

    def _build_entity_box_elem(
        self,
        ent_arr: np.ndarray,
        prefix: str,
        idx: int,
        x: float,
        y: float,
        z: float,
        dx: float,
        dy: float,
        dz: float,
        u0: int,
        v0: int,
        y_origin: float = 0.0,
        mirror: bool = False,
        elem_rot: Optional[Dict[str, Any]] = None,
        tex_dims: Optional[Tuple[int, int, int]] = None,
    ) -> Dict[str, Any]:
        """将 Minecraft EntityModel 的 CubeListBuilder.addBox(x,y,z,dx,dy,dz) 转换为 3D 渲染器立方体部件并精确切片六面 UV。"""
        tw, th, td = tex_dims if tex_dims else (int(round(dx)), int(round(dy)), int(round(dz)))
        up_p    = np.flipud(ent_arr[v0 : v0 + td, u0 + td : u0 + td + tw])
        down_p  = ent_arr[v0 : v0 + td, u0 + td + tw : u0 + td + 2 * tw]
        west_p  = ent_arr[v0 + td : v0 + td + th, u0 : u0 + td]
        north_p = ent_arr[v0 + td : v0 + td + th, u0 + td : u0 + td + tw]
        east_p  = ent_arr[v0 + td : v0 + td + th, u0 + td + tw : u0 + 2 * td + tw]
        south_p = ent_arr[v0 + td : v0 + td + th, u0 + 2 * td + tw : u0 + 2 * td + 2 * tw]

        if mirror:
            up_p = np.fliplr(up_p)
            down_p = np.fliplr(down_p)
            north_p = np.fliplr(north_p)
            south_p = np.fliplr(south_p)
            west_p, east_p = np.fliplr(east_p), np.fliplr(west_p)

        faces_map = {
            "up": up_p, "down": down_p,
            "north": north_p, "south": south_p,
            "west": west_p, "east": east_p,
        }
        elem_faces = {}
        for fname, patch in faces_map.items():
            if patch.size == 0:
                continue
            tkey = f"__{prefix}_{idx}_{fname}"
            self.texture_cache[(tkey, True)] = patch
            elem_faces[fname] = {"texture": tkey, "uv": [0, 0, 16, 16]}

        bx1 = 8.0 - (x + dx)
        bx2 = 8.0 - x
        by1 = y_origin - (y + dy)
        by2 = y_origin - y
        bz1 = 8.0 + z
        bz2 = 8.0 + z + dz

        elem: Dict[str, Any] = {
            "from": [bx1, by1, bz1],
            "to": [bx2, by2, bz2],
            "faces": elem_faces,
        }
        if elem_rot:
            elem["rotation"] = elem_rot
        return elem

    def _render_special_model(self, spec: Dict[str, Any], color_buf: np.ndarray, depth_buf: np.ndarray, custom_gui_tf=None):
        base_id = spec.get("base", "")
        resolved_base = self.resolve_model(base_id) if base_id else {"textures": {}, "display": {}}
        default_tf = resolved_base.get("display", {}).get(
            "gui", {"rotation": [30, 225, 0], "translation": [0, 0, 0], "scale": [0.625, 0.625, 0.625]}
        )
        gui_tf = custom_gui_tf or default_tf
        smodel = spec.get("model", {})
        stype = smodel.get("type", "")
        p_tex = resolved_base.get("textures", {}).get("particle", "")

        # 0. Shield
        if stype == "minecraft:shield":
            ent_arr = None
            for spath in ("entity/shield_base_nopattern", "entity/shield/shield_base_nopattern", "entity/shield_base"):
                ent_arr = self.load_texture(spath, crop_square=False)
                if ent_arr is not None:
                    break
            if ent_arr is not None:
                front_p = ent_arr[1:23, 1:13]
                back_p = ent_arr[1:23, 14:26]
                edge_p = ent_arr[1:23, 0:1]
                self.texture_cache[("__shield_front", True)] = front_p
                self.texture_cache[("__shield_back", True)] = back_p
                self.texture_cache[("__shield_edge", True)] = edge_p
                elems = [
                    {
                        "from": [2, -3, 7], "to": [14, 19, 8],
                        "faces": {
                            "north": {"texture": "__shield_front", "uv": [0, 0, 16, 16]},
                            "south": {"texture": "__shield_back",  "uv": [0, 0, 16, 16]},
                            "up":    {"texture": "__shield_edge",  "uv": [0, 0, 16, 16]},
                            "down":  {"texture": "__shield_edge",  "uv": [0, 0, 16, 16]},
                            "west":  {"texture": "__shield_edge",  "uv": [0, 0, 16, 16]},
                            "east":  {"texture": "__shield_edge",  "uv": [0, 0, 16, 16]},
                        }
                    },
                    {
                        "from": [7, 5, 8], "to": [9, 11, 14],
                        "faces": {
                            f: {"texture": "block/dark_oak_planks", "uv": [0, 0, 6, 6]}
                            for f in ("up", "down", "north", "south", "west", "east")
                        }
                    }
                ]
                tf = custom_gui_tf or {"rotation": [15, 205, -5], "translation": [0, 0, 0], "scale": [0.62, 0.62, 0.62]}
                self.render_elements_to_buffers(elems, {}, tf, [], color_buf, depth_buf)
                return None

        # 1. Shulker Box
        if stype == "minecraft:shulker_box":
            tex_name = self._clean_id(smodel.get("texture", "shulker"))
            ent_arr = self.load_texture(f"entity/shulker/{tex_name}", crop_square=False)
            if ent_arr is not None:
                top_patch = ent_arr[0:16, 16:32]
                side_patch = np.zeros((16, 16, 4), dtype=np.float32)
                side_patch[8:16, :] = ent_arr[44:52, 0:16]
                lid_slice = ent_arr[16:28, 0:16]
                lid_mask = lid_slice[:, :, 3:4] > 0
                side_patch[0:12, :] = np.where(lid_mask, lid_slice, side_patch[0:12, :])
                bottom_patch = ent_arr[28:44, 32:48]
                self.texture_cache[("__shulker_top_" + tex_name, True)] = top_patch
                self.texture_cache[("__shulker_side_" + tex_name, True)] = side_patch
                self.texture_cache[("__shulker_bot_" + tex_name, True)] = bottom_patch
                elems = [{
                    "from": [0, 0, 0], "to": [16, 16, 16],
                    "faces": {
                        "up":    {"texture": "#top",  "uv": [0, 0, 16, 16]},
                        "down":  {"texture": "#bot",  "uv": [0, 0, 16, 16]},
                        "north": {"texture": "#side", "uv": [0, 0, 16, 16]},
                        "south": {"texture": "#side", "uv": [0, 0, 16, 16]},
                        "west":  {"texture": "#side", "uv": [0, 0, 16, 16]},
                        "east":  {"texture": "#side", "uv": [0, 0, 16, 16]},
                    }
                }]
                tf = custom_gui_tf or {"rotation": [30, 225, 0], "translation": [0, 0, 0], "scale": [0.625, 0.625, 0.625]}
                self.render_elements_to_buffers(elems, {
                    "top": "__shulker_top_" + tex_name,
                    "side": "__shulker_side_" + tex_name,
                    "bot": "__shulker_bot_" + tex_name,
                }, tf, [], color_buf, depth_buf)
                return None

        # 2. Chest / Ender Chest / Trapped Chest
        elif stype == "minecraft:chest":
            tex_name = self._clean_id(smodel.get("texture", "normal"))
            ent_arr = self.load_texture(f"entity/chest/{tex_name}", crop_square=False)
            if ent_arr is not None:
                top_p = np.flipud(ent_arr[0:14, 28:42])
                front_p = np.zeros((14, 14, 4), dtype=np.float32)
                front_p[0:5, :] = np.flipud(ent_arr[14:19, 42:56])
                front_p[4:14, :] = np.flipud(ent_arr[33:43, 42:56])
                front_p[3:7, 6:8] = ent_arr[1:5, 1:3]
                side_p = np.zeros((14, 14, 4), dtype=np.float32)
                side_p[0:5, :] = np.flipud(ent_arr[14:19, 0:14])
                side_p[4:14, :] = np.flipud(ent_arr[33:43, 0:14])
                self.texture_cache[("__chest_top_" + tex_name, True)] = top_p
                self.texture_cache[("__chest_front_" + tex_name, True)] = front_p
                self.texture_cache[("__chest_side_" + tex_name, True)] = side_p
                elems = [{
                    "from": [1, 0, 1], "to": [15, 14, 15],
                    "faces": {
                        "up":    {"texture": "#top",   "uv": [0, 0, 16, 16]},
                        "down":  {"texture": "#top",   "uv": [0, 0, 16, 16]},
                        "north": {"texture": "#front", "uv": [0, 0, 16, 16]},
                        "south": {"texture": "#side",  "uv": [0, 0, 16, 16]},
                        "west":  {"texture": "#side",  "uv": [0, 0, 16, 16]},
                        "east":  {"texture": "#side",  "uv": [0, 0, 16, 16]},
                    }
                }]
                tf = custom_gui_tf or {"rotation": [30, 225, 0], "translation": [0, 0, 0], "scale": [0.625, 0.625, 0.625]}
                self.render_elements_to_buffers(elems, {
                    "top": "__chest_top_" + tex_name,
                    "front": "__chest_front_" + tex_name,
                    "side": "__chest_side_" + tex_name,
                }, tf, [], color_buf, depth_buf)
                return None

        # 3. Heads & Skulls
        elif stype in ("minecraft:head", "minecraft:player_head"):
            kind = smodel.get("kind", "player")
            head_tex_map = {
                "skeleton": "entity/skeleton/skeleton",
                "wither_skeleton": "entity/skeleton/wither_skeleton",
                "zombie": "entity/zombie/zombie",
                "creeper": "entity/creeper/creeper",
                "piglin": "entity/piglin/piglin",
                "dragon": "entity/enderdragon/dragon",
                "player": "entity/player/wide/steve",
            }
            ent_arr = self.load_texture(head_tex_map.get(kind, "entity/player/wide/steve"), crop_square=False)
            if ent_arr is not None:
                if kind == "dragon":
                    # 精确还原 DragonHeadModel.class 的 7 个 3D 部件：主头颅、上颚、下颚、双角(scale)、双鼻孔(nostril)
                    dragon_boxes = [
                        (-8,  -8, -10, 16, 16, 16, 112, 30, False),  # upper_head (主头骨+紫眼)
                        (-6,  -1, -24, 12,  5, 16, 176, 44, False),  # upper_lip (上颚长吻)
                        (-6,   4, -24, 12,  4, 16, 176, 65, False),  # jaw (下颚)
                        (-5, -12,  -4,  2,  4,  6,   0,  0, True),   # left scale (左龙角)
                        ( 3, -12,  -4,  2,  4,  6,   0,  0, False),  # right scale (右龙角)
                        (-5,  -3, -22,  2,  2,  4, 112,  0, True),   # left nostril (左鼻孔)
                        ( 3,  -3, -22,  2,  2,  4, 112,  0, False),  # right nostril (右鼻孔)
                    ]
                    elems = [
                        self._build_entity_box_elem(ent_arr, "dragon_head", i, *b[:8], y_origin=6.0, mirror=b[8])
                        for i, b in enumerate(dragon_boxes)
                    ]
                    tf = custom_gui_tf or {"rotation": [30, 225, 0], "translation": [-2.2, 1.8, 0], "scale": [0.43, 0.43, 0.43]}
                elif kind == "piglin":
                    # 精确还原 AbstractPiglinModel.addHead 的 6 个 3D 部件：头颅、猪鼻、左右獠牙、左右垂耳(±30°旋转)
                    piglin_boxes = [
                        (-5,   -8, -4, 10, 8, 8,  0, 0, False, None),
                        (-2,   -4, -5,  4, 4, 1, 31, 1, False, None),
                        ( 2,   -2, -5,  1, 2, 1,  2, 4, False, None),
                        (-3,   -2, -5,  1, 2, 1,  2, 0, False, None),
                        ( 4.5, -6, -2,  1, 5, 4, 51, 6, False, {"origin": [8.0 - 4.5, 6.0, 8.0], "axis": "z", "angle": -30}),
                        (-5.5, -6, -2,  1, 5, 4, 39, 6, False, {"origin": [8.0 + 4.5, 6.0, 8.0], "axis": "z", "angle": 30}),
                    ]
                    elems = [
                        self._build_entity_box_elem(ent_arr, "piglin_head", i, *b[:8], y_origin=0.0, mirror=b[8], elem_rot=b[9])
                        for i, b in enumerate(piglin_boxes)
                    ]
                    tf = custom_gui_tf or {"rotation": [30, 225, 0], "translation": [0, 2.5, 0], "scale": [0.85, 0.85, 0.85]}
                else:
                    # 标准 8x8x8 头颅 (骷髅、凋灵骷髅、僵尸、苦力怕、玩家头颅) 含六面独立展开与外层 Hat 叠加
                    elems = [
                        self._build_entity_box_elem(ent_arr, f"skull_{kind}", 0, -4, -8, -4, 8, 8, 8, 0, 0, y_origin=0.0)
                    ]
                    if kind in ("player", "zombie") and ent_arr.shape[1] >= 64 and ent_arr.shape[0] >= 16:
                        elems.append(
                            self._build_entity_box_elem(
                                ent_arr, f"skull_hat_{kind}", 1, -4.25, -8.25, -4.25, 8.5, 8.5, 8.5, 32, 0,
                                y_origin=0.0, tex_dims=(8, 8, 8)
                            )
                        )
                    tf = custom_gui_tf or {"rotation": [30, 225, 0], "translation": [0, 3, 0], "scale": [1.0, 1.0, 1.0]}
                self.render_elements_to_buffers(elems, {}, tf, [], color_buf, depth_buf)
                return None

        # 4. Banner
        elif stype == "minecraft:banner":
            color_name = smodel.get("color", "white")
            rgb_tint = DYE_COLOR_RGB.get(color_name, (255, 255, 255))
            banner_base = None
            for bp in ("entity/banner/banner_base", "entity/banner_base", "entity/banner/base"):
                banner_base = self.load_texture(bp, crop_square=False)
                if banner_base is not None:
                    break
            if banner_base is not None:
                # 精确还原 BannerModel.createBodyLayer 与 BannerFlagModel.createFlagLayer：
                # 1. flag (悬挂旗面): (-10, -44, -2, 20, 40, 1) at texOffs(0, 0)，叠加 DyeColor 染色
                # 2. bar  (顶部横杆): (-10, -44, -1, 20,  2, 2) at texOffs(0, 42)，原木色不染色
                # 3. pole (竖直旗杆): ( -1, -42, -1,  2, 42, 2) at texOffs(44, 0)，底部露出木杆
                tint_vec = np.array(rgb_tint, dtype=np.float32) / 255.0
                tinted_base = banner_base.copy()
                tinted_base[:, :, :3] = tinted_base[:, :, :3] * tint_vec
                el_flag = self._build_entity_box_elem(
                    tinted_base, f"banner_flag_{color_name}", 0,
                    -10.0, -44.0, -2.0, 20.0, 40.0, 1.0, 0, 0, y_origin=-14.0
                )
                el_bar = self._build_entity_box_elem(
                    banner_base, "banner_wood", 1,
                    -10.0, -44.0, -1.0, 20.0, 2.0, 2.0, 0, 42, y_origin=-14.0
                )
                el_pole = self._build_entity_box_elem(
                    banner_base, "banner_wood", 2,
                    -1.0, -42.0, -1.0, 2.0, 42.0, 2.0, 44, 0, y_origin=-14.0
                )
                elems = [el_pole, el_bar, el_flag]
                tf = custom_gui_tf or {"rotation": [30, 200, 0], "translation": [0.0, 0.2, 0.0], "scale": [0.355, 0.355, 0.355]}
                self.render_elements_to_buffers(elems, {}, tf, [], color_buf, depth_buf, gui_light="front")
                return None

        # 4b. Copper Golem Statue
        elif stype in ("minecraft:copper_golem", "minecraft:copper_golem_statue"):
            tex_path = self._clean_id(smodel.get("texture", "textures/entity/copper_golem/copper_golem.png"))
            ent_arr = self.load_texture(tex_path, crop_square=False)
            if ent_arr is None:
                for cand in (
                    "entity/copper_golem/copper_golem",
                    "textures/entity/copper_golem/copper_golem",
                    "entity/copper_golem/copper_golem.png",
                    "entity/copper_golem",
                ):
                    ent_arr = self.load_texture(cand, crop_square=False)
                    if ent_arr is not None:
                        tex_path = cand
                        break
            if ent_arr is not None:
                key_pfx = "cg_" + tex_path.split("/")[-1].replace(".png", "")
                # 精确还原 CopperGolemModel.createBodyLayer 的 9 个 3D 部件：
                # 躯干(body)、8x5x10头颅(head)、鼻子(nose)、避雷针杆(rod_stem)、避雷针顶球(rod_top)、左右手臂(arms)、左右腿(legs)
                cg_boxes = [
                    (-4.0, -11.0, -3.0, 8.0,  6.0,  6.0,  0, 15),  # body
                    (-4.0, -16.0, -5.0, 8.0,  5.0, 10.0,  0,  0),  # head (8x5x10)
                    (-1.0, -13.0, -6.0, 2.0,  3.0,  2.0, 56,  0),  # nose
                    (-1.0, -20.0, -1.0, 2.0,  4.0,  2.0, 37,  8),  # rod_stem
                    (-2.0, -24.0, -2.0, 4.0,  4.0,  4.0, 37,  0),  # rod_top
                    (-7.0, -12.0, -2.0, 3.0, 10.0,  4.0, 36, 16),  # right_arm
                    ( 4.0, -12.0, -2.0, 3.0, 10.0,  4.0, 50, 16),  # left_arm
                    (-4.0,  -5.0, -2.0, 4.0,  5.0,  4.0,  0, 27),  # right_leg
                    ( 0.0,  -5.0, -2.0, 4.0,  5.0,  4.0, 16, 27),  # left_leg
                ]
                elems = [
                    self._build_entity_box_elem(ent_arr, key_pfx, i, *b, y_origin=-4.0)
                    for i, b in enumerate(cg_boxes)
                ]
                tf = custom_gui_tf or {"rotation": [30, 225, 0], "translation": [0.0, 0.0, 0.0], "scale": [0.55, 0.55, 0.55]}
                self.render_elements_to_buffers(elems, {}, tf, [], color_buf, depth_buf)
                return None

        # 5. Decorated Pot
        elif stype == "minecraft:decorated_pot":
            ent_base = self.load_texture("entity/decorated_pot/decorated_pot_base", crop_square=False)
            ent_side = self.load_texture("entity/decorated_pot/decorated_pot_side", crop_square=False)
            if ent_side is not None and ent_base is not None:
                self.texture_cache[("__pot_top", True)] = ent_base[14:28, 0:14]
                self.texture_cache[("__pot_neck", True)] = ent_base[0:7, 0:6]
                self.texture_cache[("__pot_side", True)] = ent_side[0:16, 0:16]
                elems = [
                    {
                        "from": [1, 0, 1], "to": [15, 16, 15],
                        "faces": {
                            "up":    {"texture": "__pot_top",  "uv": [0, 0, 16, 16]},
                            "down":  {"texture": "__pot_top",  "uv": [0, 0, 16, 16]},
                            "north": {"texture": "__pot_side", "uv": [1, 0, 15, 16]},
                            "south": {"texture": "__pot_side", "uv": [1, 0, 15, 16]},
                            "west":  {"texture": "__pot_side", "uv": [1, 0, 15, 16]},
                            "east":  {"texture": "__pot_side", "uv": [1, 0, 15, 16]},
                        }
                    },
                    {
                        "from": [4, 16, 4], "to": [12, 20, 12],
                        "faces": {
                            "up":    {"texture": "__pot_top",  "uv": [4, 4, 12, 12]},
                            "north": {"texture": "__pot_neck", "uv": [0, 0, 16, 8]},
                            "south": {"texture": "__pot_neck", "uv": [0, 0, 16, 8]},
                            "west":  {"texture": "__pot_neck", "uv": [0, 0, 16, 8]},
                            "east":  {"texture": "__pot_neck", "uv": [0, 0, 16, 8]},
                        }
                    }
                ]
                tf = custom_gui_tf or {"rotation": [30, 225, 0], "translation": [0, -1, 0], "scale": [0.55, 0.55, 0.55]}
                self.render_elements_to_buffers(elems, {}, tf, [], color_buf, depth_buf)
                return None

        # 6. Conduit
        elif stype == "minecraft:conduit":
            ent_cage = self.load_texture("entity/conduit/cage", crop_square=False)
            if ent_cage is not None:
                self.texture_cache[("__conduit_cage", True)] = ent_cage[8:16, 8:16]
                elems = [{
                    "from": [4, 4, 4], "to": [12, 12, 12],
                    "faces": {
                        f: {"texture": "__conduit_cage", "uv": [0, 0, 16, 16]}
                        for f in ("up", "down", "north", "south", "west", "east")
                    }
                }]
                tf = custom_gui_tf or {"rotation": [30, 225, 0], "translation": [0, 0, 0], "scale": [0.85, 0.85, 0.85]}
                self.render_elements_to_buffers(elems, {}, tf, [], color_buf, depth_buf)
                return None

        # 7. Bed (Head + Foot + 4 Wooden Legs)
        elif stype == "minecraft:bed":
            c_name = self._clean_id(smodel.get("texture") or smodel.get("color") or "red")
            if "/" in c_name:
                c_name = c_name.split("/")[-1]
            ent_bed = self.load_texture(f"entity/bed/{c_name}", crop_square=False)
            if ent_bed is not None and ent_bed.shape[0] >= 44 and ent_bed.shape[1] >= 44:
                head_top = ent_bed[6:22, 6:22]
                foot_top = ent_bed[28:44, 6:22]
                head_end = np.rot90(ent_bed[0:6, 6:22], k=2)
                foot_end = np.flipud(ent_bed[22:28, 22:38]) if ent_bed.shape[1] >= 38 else np.flipud(ent_bed[22:28, 6:22])
                head_west = np.rot90(ent_bed[6:22, 0:6], k=1)
                head_east = np.rot90(ent_bed[6:22, 22:28], k=3)
                foot_west = np.rot90(ent_bed[28:44, 0:6], k=1)
                foot_east = np.rot90(ent_bed[28:44, 22:28], k=3)
                leg_outer = ent_bed[3:6, 53:56] if ent_bed.shape[1] >= 56 else ent_bed[6:9, 0:3]
                leg_pad_r = np.fliplr(ent_bed[9:12, 56:59]) if ent_bed.shape[1] >= 59 else leg_outer
                leg_pad_l = ent_bed[9:12, 56:59] if ent_bed.shape[1] >= 59 else leg_outer

                self.texture_cache[(f"__bed_htop_{c_name}", True)] = head_top
                self.texture_cache[(f"__bed_ftop_{c_name}", True)] = foot_top
                self.texture_cache[(f"__bed_hend_{c_name}", True)] = head_end
                self.texture_cache[(f"__bed_fend_{c_name}", True)] = foot_end
                self.texture_cache[(f"__bed_hwest_{c_name}", True)] = head_west
                self.texture_cache[(f"__bed_heast_{c_name}", True)] = head_east
                self.texture_cache[(f"__bed_fwest_{c_name}", True)] = foot_west
                self.texture_cache[(f"__bed_feast_{c_name}", True)] = foot_east
                self.texture_cache[(f"__bed_leg_out_{c_name}", True)] = leg_outer
                self.texture_cache[(f"__bed_leg_padr_{c_name}", True)] = leg_pad_r
                self.texture_cache[(f"__bed_leg_padl_{c_name}", True)] = leg_pad_l

                elems = [
                    {
                        "from": [0, 3, -8], "to": [16, 9, 8],
                        "faces": {
                            "up":    {"texture": f"__bed_htop_{c_name}",  "uv": [0, 0, 16, 16]},
                            "down":  {"texture": f"__bed_htop_{c_name}",  "uv": [0, 0, 16, 16]},
                            "north": {"texture": f"__bed_hend_{c_name}",  "uv": [0, 0, 16, 16]},
                            "south": {"texture": f"__bed_hend_{c_name}",  "uv": [0, 0, 16, 16]},
                            "west":  {"texture": f"__bed_hwest_{c_name}", "uv": [0, 0, 16, 16]},
                            "east":  {"texture": f"__bed_heast_{c_name}", "uv": [0, 0, 16, 16]},
                        }
                    },
                    {
                        "from": [0, 3, 8], "to": [16, 9, 24],
                        "faces": {
                            "up":    {"texture": f"__bed_ftop_{c_name}",  "uv": [0, 0, 16, 16]},
                            "down":  {"texture": f"__bed_ftop_{c_name}",  "uv": [0, 0, 16, 16]},
                            "north": {"texture": f"__bed_fend_{c_name}",  "uv": [0, 0, 16, 16]},
                            "south": {"texture": f"__bed_fend_{c_name}",  "uv": [0, 0, 16, 16]},
                            "west":  {"texture": f"__bed_fwest_{c_name}", "uv": [0, 0, 16, 16]},
                            "east":  {"texture": f"__bed_feast_{c_name}", "uv": [0, 0, 16, 16]},
                        }
                    },
                    {
                        "from": [0, 0, -8], "to": [3, 3, -5],
                        "faces": {
                            "up":    {"texture": f"__bed_leg_out_{c_name}",  "uv": [0, 0, 16, 16]},
                            "down":  {"texture": f"__bed_leg_out_{c_name}",  "uv": [0, 0, 16, 16]},
                            "north": {"texture": f"__bed_leg_padr_{c_name}", "uv": [0, 0, 16, 16]},
                            "south": {"texture": f"__bed_leg_padl_{c_name}", "uv": [0, 0, 16, 16]},
                            "west":  {"texture": f"__bed_leg_out_{c_name}",  "uv": [0, 0, 16, 16]},
                            "east":  {"texture": f"__bed_leg_padl_{c_name}", "uv": [0, 0, 16, 16]},
                        }
                    },
                    {
                        "from": [13, 0, -8], "to": [16, 3, -5],
                        "faces": {
                            "up":    {"texture": f"__bed_leg_out_{c_name}",  "uv": [0, 0, 16, 16]},
                            "down":  {"texture": f"__bed_leg_out_{c_name}",  "uv": [0, 0, 16, 16]},
                            "north": {"texture": f"__bed_leg_out_{c_name}",  "uv": [0, 0, 16, 16]},
                            "south": {"texture": f"__bed_leg_padr_{c_name}", "uv": [0, 0, 16, 16]},
                            "west":  {"texture": f"__bed_leg_padl_{c_name}", "uv": [0, 0, 16, 16]},
                            "east":  {"texture": f"__bed_leg_out_{c_name}",  "uv": [0, 0, 16, 16]},
                        }
                    },
                    {
                        "from": [0, 0, 21], "to": [3, 3, 24],
                        "faces": {
                            "up":    {"texture": f"__bed_leg_out_{c_name}",  "uv": [0, 0, 16, 16]},
                            "down":  {"texture": f"__bed_leg_out_{c_name}",  "uv": [0, 0, 16, 16]},
                            "north": {"texture": f"__bed_leg_padr_{c_name}", "uv": [0, 0, 16, 16]},
                            "south": {"texture": f"__bed_leg_out_{c_name}",  "uv": [0, 0, 16, 16]},
                            "west":  {"texture": f"__bed_leg_padr_{c_name}", "uv": [0, 0, 16, 16]},
                            "east":  {"texture": f"__bed_leg_padl_{c_name}", "uv": [0, 0, 16, 16]},
                        }
                    },
                    {
                        "from": [13, 0, 21], "to": [16, 3, 24],
                        "faces": {
                            "up":    {"texture": f"__bed_leg_out_{c_name}",  "uv": [0, 0, 16, 16]},
                            "down":  {"texture": f"__bed_leg_out_{c_name}",  "uv": [0, 0, 16, 16]},
                            "north": {"texture": f"__bed_leg_padl_{c_name}", "uv": [0, 0, 16, 16]},
                            "south": {"texture": f"__bed_leg_padr_{c_name}", "uv": [0, 0, 16, 16]},
                            "west":  {"texture": f"__bed_leg_padr_{c_name}", "uv": [0, 0, 16, 16]},
                            "east":  {"texture": f"__bed_leg_out_{c_name}",  "uv": [0, 0, 16, 16]},
                        }
                    },
                ]
                tf = custom_gui_tf or {"rotation": [30, 135, 0], "translation": [0, 2, 0], "scale": [0.50, 0.50, 0.50]}
                self.render_elements_to_buffers(elems, {}, tf, [], color_buf, depth_buf)
                return None

        if p_tex:
            elems = [{
                "from": [0, 0, 0], "to": [16, 16, 16],
                "faces": {f: {"texture": p_tex, "uv": [0, 0, 16, 16]} for f in ("up", "down", "north", "south", "west", "east")}
            }]
            self.render_elements_to_buffers(elems, {}, gui_tf, [], color_buf, depth_buf)
        return None

    def extract_assets_to_dir(self, target_dir: str, progress_cb=None) -> Dict[str, int]:
        out_root = Path(target_dir)
        out_root.mkdir(parents=True, exist_ok=True)
        prefixes = (
            "assets/minecraft/models/block/",
            "assets/minecraft/models/item/",
            "assets/minecraft/items/",
            "assets/minecraft/blockstates/",
            "assets/minecraft/textures/block/",
            "assets/minecraft/textures/item/",
            "assets/minecraft/textures/entity/",
            "assets/minecraft/textures/colormap/",
        )
        matched = [n for n in sorted(self.namelist) if n.startswith(prefixes) and not n.endswith("/")]
        counts = {"models": 0, "textures": 0, "items_and_blockstates": 0}
        total = len(matched)
        for idx, name in enumerate(matched):
            dest = out_root / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            with open(dest, "wb") as f:
                f.write(self.zf.read(name))
            if "/models/" in name:
                counts["models"] += 1
            elif "/textures/" in name:
                counts["textures"] += 1
            else:
                counts["items_and_blockstates"] += 1
            if progress_cb and (idx % 100 == 0 or idx == total - 1):
                progress_cb(idx + 1, total, f"正在提取: {name.split('/')[-1]}")
        return counts

    def export_categorized_renders(self, output_dir: str, icon_size: int = 64, filter_mode: str = "all", progress_cb=None) -> str:
        """按创造物品栏分类文件夹导出全部方块与物品的 PNG 物品栏渲染图，并生成 manifest.json。"""
        out_root = Path(output_dir)
        out_root.mkdir(parents=True, exist_ok=True)

        def _filter_list(items_list: List[str]) -> List[str]:
            if filter_mode == "blocks":
                return [x for x in items_list if x in self.block_set]
            elif filter_mode == "items":
                return [x for x in items_list if x not in self.block_set]
            return items_list

        total_tasks = sum(len(_filter_list(self.categories[k])) for k, _, _ in CREATIVE_TABS_META if k != "all_items")
        done = 0
        rendered_cache: Dict[str, Image.Image] = {}
        manifest = {
            "jar_file": os.path.basename(self.jar_path),
            "icon_size": icon_size,
            "filter_mode": filter_mode,
            "total_items": len(self.all_items),
            "total_blocks": len(self.block_items),
            "total_non_block_items": len(self.non_block_items),
            "categories": {},
        }

        for tab_key, tab_label, _ in CREATIVE_TABS_META:
            if tab_key == "all_items":
                continue
            items = _filter_list(self.categories.get(tab_key, []))
            if not items:
                continue
            tab_dir = out_root / tab_key
            tab_dir.mkdir(parents=True, exist_ok=True)
            manifest["categories"][tab_key] = {
                "label": tab_label,
                "count": len(items),
                "items": items,
            }
            for idx, it in enumerate(items):
                if it not in rendered_cache:
                    rendered_cache[it] = self.render_item(it, target_size=icon_size)
                img = rendered_cache[it]
                img.save(tab_dir / f"{idx + 1:03d}_{it}.png")
                done += 1
                if progress_cb and (done % 20 == 0 or done == total_tasks):
                    progress_cb(done, total_tasks, f"[{tab_key}] 渲染并保存: {it}.png")

        manifest_path = out_root / "creative_inventory_manifest.json"
        with open(manifest_path, "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)
        return str(manifest_path)

    def generate_creative_atlas_poster(self, output_png_path: str, max_per_tab: int = 27, cell_size: int = 54) -> str:
        """生成包含全部 11 个创造物品栏分类（方块 + 物品）的预览图集海报 (PNG)。"""
        cols = 9  # Minecraft 创造物品栏标准每行 9 格
        slot_pad = 6
        slot_pitch = cell_size + slot_pad
        margin_x = 32
        header_h = 88

        tabs_to_draw = [
            t for t in CREATIVE_TABS_META
            if t[0] != "all_items" and len(self.categories.get(t[0], [])) > 0
        ]

        total_h = header_h + 24
        for tab_key, _, _ in tabs_to_draw:
            items = self.categories[tab_key][:max_per_tab]
            rows = max(1, math.ceil(len(items) / cols))
            total_h += 42 + rows * slot_pitch + 18

        width = margin_x * 2 + cols * slot_pitch + 24
        poster = Image.new("RGBA", (width, total_h), (24, 26, 31, 255))
        draw = ImageDraw.Draw(poster)

        font_title = ImageFont.load_default()
        font_sub = ImageFont.load_default()
        for fp in ("/System/Library/Fonts/Helvetica.ttc", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"):
            if os.path.exists(fp):
                try:
                    font_title = ImageFont.truetype(fp, 15)
                    break
                except Exception:
                    pass
        for fp in ("/System/Library/Fonts/Helvetica.ttc", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
            if os.path.exists(fp):
                try:
                    font_sub = ImageFont.truetype(fp, 11)
                    break
                except Exception:
                    pass

        # 顶部标题栏
        draw.rounded_rectangle([16, 14, width - 16, header_h - 8], radius=10, fill=(36, 40, 48, 255), outline=(68, 75, 88, 255), width=2)
        title_text = f"Minecraft Full Creative Inventory Renders - {os.path.basename(self.jar_path)}"
        sub_text = (
            f"Total: {len(self.all_items)} ({len(self.block_items)} Blocks + {len(self.non_block_items)} Items) "
            f"| All {len(tabs_to_draw)} Creative Tabs"
        )
        draw.text((28, 24), title_text, fill=(245, 247, 250, 255), font=font_title)
        draw.text((28, 50), sub_text, fill=(168, 178, 195, 255), font=font_sub)

        curr_y = header_h + 10
        for tab_key, tab_label, badge_rgb in tabs_to_draw:
            full_list = self.categories[tab_key]
            items = full_list[:max_per_tab]
            rows = max(1, math.ceil(len(items) / cols))
            sec_h = 36 + rows * slot_pitch + 10

            draw.rounded_rectangle(
                [16, curr_y, width - 16, curr_y + sec_h],
                radius=8,
                fill=(33, 36, 43, 255),
                outline=(58, 63, 74, 255),
                width=1,
            )
            draw.rounded_rectangle(
                [26, curr_y + 9, 36, curr_y + 27],
                radius=3,
                fill=badge_rgb + (255,),
            )
            b_cnt = sum(1 for x in full_list if x in self.block_set)
            i_cnt = len(full_list) - b_cnt
            shown_note = f"Showing {len(items)} / {len(full_list)} ({b_cnt} blocks, {i_cnt} items)"
            header_str = f"{tab_key.upper().replace('_', ' ')}   -   {shown_note}"
            draw.text((46, curr_y + 11), header_str, fill=(235, 238, 245, 255), font=font_sub)

            grid_y0 = curr_y + 36
            for idx, item_name in enumerate(items):
                r, c = divmod(idx, cols)
                sx = margin_x + c * slot_pitch
                sy = grid_y0 + r * slot_pitch
                is_blk = item_name in self.block_set
                slot_fill = (54, 58, 68, 255) if is_blk else (46, 54, 66, 255)
                slot_outline = (78, 84, 96, 255) if is_blk else (72, 92, 114, 255)
                draw.rounded_rectangle(
                    [sx, sy, sx + cell_size, sy + cell_size],
                    radius=5,
                    fill=slot_fill,
                    outline=slot_outline,
                    width=1,
                )
                icon = self.render_item(item_name, target_size=cell_size - 8)
                poster.alpha_composite(icon, (sx + 4, sy + 4))

            curr_y += sec_h + 10

        Path(output_png_path).parent.mkdir(parents=True, exist_ok=True)
        poster.save(output_png_path)
        return output_png_path

