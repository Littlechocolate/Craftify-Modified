"""2D Layered Item Renderer."""

from typing import List, Optional
from PIL import Image
from ..extractor.asset_manager import AssetManager

class ItemRenderer:
    """Renders 2D layered items with pixel-perfect scaling."""

    def __init__(self, asset_manager: AssetManager):
        self.asset_manager = asset_manager

    def render(self, layer_paths: List[str], target_size: int = 128) -> Optional[Image.Image]:
        """Composites layers together and scales them to fit target_size with padding."""
        if not layer_paths:
            return None

        composite: Optional[Image.Image] = None
        for path in layer_paths:
            tex = self.asset_manager.get_texture_image(path)
            if tex is None:
                continue
            if composite is None:
                composite = tex.copy()
            else:
                # Ensure sizes match
                if composite.size != tex.size:
                    tex = tex.resize(composite.size, Image.Resampling.NEAREST)
                composite = Image.alpha_composite(composite, tex)

        if composite is None:
            return None

        # Scale with pixel-art integrity
        inner_size = int(target_size * 0.85)
        scaled = composite.resize((inner_size, inner_size), Image.Resampling.NEAREST)

        canvas = Image.new("RGBA", (target_size, target_size), (0, 0, 0, 0))
        offset_x = (target_size - inner_size) // 2
        offset_y = (target_size - inner_size) // 2
        canvas.paste(scaled, (offset_x, offset_y), scaled)
        return canvas
