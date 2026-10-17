"""Model Resolver for resolving Minecraft model inheritance and texture variable references."""

from typing import Dict, List, Optional, Set
from ..extractor.asset_manager import AssetManager
from .json_model import ElementFace, ElementRotation, GuiDisplay, ModelElement, ResolvedModel

class ModelResolver:
    """Resolves model parent hierarchies, texture variables, elements, and GUI display properties."""

    def __init__(self, asset_manager: AssetManager):
        self.asset_manager = asset_manager

    def resolve(self, model_id: str) -> ResolvedModel:
        """
        Traverses parent hierarchy and resolves all properties into a clean ResolvedModel.
        """
        chain: List[dict] = []
        curr = model_id
        visited: Set[str] = set()

        while curr and curr not in visited:
            visited.add(curr)
            raw = self.asset_manager.get_model_json(curr)
            if not raw:
                # If model not found under given path, try block/ or item/ prefix
                if not curr.startswith("block/") and not curr.startswith("item/"):
                    raw = self.asset_manager.get_model_json(f"block/{curr}") or \
                          self.asset_manager.get_model_json(f"item/{curr}")
                if not raw:
                    break
            chain.append(raw)
            curr = raw.get("parent")

        # 1. Merge textures (parent textures overwritten by child textures)
        raw_textures: Dict[str, str] = {}
        for m in reversed(chain):
            if "textures" in m and isinstance(m["textures"], dict):
                raw_textures.update(m["textures"])

        # 2. Resolve variable references (e.g. #all -> #top -> block/stone)
        resolved_textures: Dict[str, str] = {}
        for k, v in raw_textures.items():
            if not isinstance(v, str):
                continue
            val = v
            seen_vars: Set[str] = set()
            while val.startswith("#") and val[1:] in raw_textures and val not in seen_vars:
                seen_vars.add(val)
                val = raw_textures[val[1:]]
            resolved_textures[k] = AssetManager.normalize_resource_path(val)

        # 3. Find elements (child elements override parent elements)
        raw_elements = None
        for m in chain:
            if "elements" in m and isinstance(m["elements"], list):
                raw_elements = m["elements"]
                break

        # 4. Find GUI display settings
        gui_display = GuiDisplay()
        for m in chain:
            if "display" in m and isinstance(m["display"], dict):
                if "gui" in m["display"] and isinstance(m["display"]["gui"], dict):
                    gui_raw = m["display"]["gui"]
                    gui_display = GuiDisplay(
                        rotation=gui_raw.get("rotation", [30.0, 225.0, 0.0]),
                        translation=gui_raw.get("translation", [0.0, 0.0, 0.0]),
                        scale=gui_raw.get("scale", [0.625, 0.625, 0.625])
                    )
                    break

        # Check if 2D item
        is_2d_item = False
        layers_2d = []
        if raw_elements is None:
            # Check for layer0, layer1, ...
            for i in range(10):
                layer_key = f"layer{i}"
                if layer_key in resolved_textures:
                    layers_2d.append(resolved_textures[layer_key])
            if layers_2d:
                is_2d_item = True

        # Parse elements
        parsed_elements = None
        if raw_elements is not None:
            parsed_elements = []
            for el_data in raw_elements:
                from_pt = el_data.get("from", [0.0, 0.0, 0.0])
                to_pt = el_data.get("to", [16.0, 16.0, 16.0])
                shade = el_data.get("shade", True)

                # Parse element rotation
                rotation = None
                if "rotation" in el_data and isinstance(el_data["rotation"], dict):
                    r_raw = el_data["rotation"]
                    rotation = ElementRotation(
                        origin=r_raw.get("origin", [8.0, 8.0, 8.0]),
                        axis=r_raw.get("axis", "y"),
                        angle=float(r_raw.get("angle", 0.0)),
                        rescale=bool(r_raw.get("rescale", False))
                    )

                # Parse faces
                faces_dict: Dict[str, ElementFace] = {}
                for face_name, face_raw in el_data.get("faces", {}).items():
                    tex_ref = face_raw.get("texture", "")
                    if tex_ref.startswith("#"):
                        tex_ref = resolved_textures.get(tex_ref[1:], "")
                    else:
                        tex_ref = resolved_textures.get(tex_ref, tex_ref)

                    faces_dict[face_name] = ElementFace(
                        texture_ref=AssetManager.normalize_resource_path(tex_ref),
                        uv=face_raw.get("uv"),
                        cullface=face_raw.get("cullface"),
                        rotation=int(face_raw.get("rotation", 0)),
                        tintindex=int(face_raw.get("tintindex", -1))
                    )

                parsed_elements.append(ModelElement(
                    from_pt=from_pt,
                    to_pt=to_pt,
                    faces=faces_dict,
                    rotation=rotation,
                    shade=shade
                ))

        return ResolvedModel(
            model_id=model_id,
            elements=parsed_elements,
            textures=resolved_textures,
            gui=gui_display,
            is_2d_item=is_2d_item,
            layers_2d=layers_2d
        )
