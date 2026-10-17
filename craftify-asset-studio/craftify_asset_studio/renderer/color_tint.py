"""Biome and Model Color Tinting."""

from typing import Optional, Tuple
import numpy as np
from PIL import Image

TINT_GRASS = (121, 192, 90)       # #79C05A
TINT_FOLIAGE = (89, 201, 60)      # #59C93C
TINT_WATER = (63, 118, 228)       # #3F76E4
TINT_REDSTONE = (255, 30, 30)
TINT_BIRCH = (128, 167, 85)
TINT_SPRUCE = (97, 153, 97)
TINT_LILY_PAD = (32, 128, 48)

def apply_tint(image: Image.Image, tint: Tuple[int, int, int]) -> Image.Image:
    """Multiplies RGB channels of the image by tint color, preserving alpha."""
    arr = np.array(image, dtype=np.float32)
    r_factor = tint[0] / 255.0
    g_factor = tint[1] / 255.0
    b_factor = tint[2] / 255.0

    arr[:, :, 0] *= r_factor
    arr[:, :, 1] *= g_factor
    arr[:, :, 2] *= b_factor

    clipped = np.clip(arr, 0, 255).astype(np.uint8)
    return Image.fromarray(clipped)

def resolve_tint(model_id: str, tintindex: int) -> Optional[Tuple[int, int, int]]:
    """Determines the appropriate tint color based on model identifier and tintindex."""
    if tintindex < 0:
        return None

    raw = model_id.lower()
    if "birch_leaves" in raw:
        return TINT_BIRCH
    if "spruce_leaves" in raw:
        return TINT_SPRUCE
    if "leaves" in raw or "vine" in raw:
        return TINT_FOLIAGE
    if "water" in raw:
        return TINT_WATER
    if "redstone" in raw:
        return TINT_REDSTONE
    if "lily_pad" in raw:
        return TINT_LILY_PAD

    # Default tint for grass_block, tall_grass, fern, etc.
    return TINT_GRASS
