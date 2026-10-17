"""Data structures for Minecraft Model JSON specifications."""

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

@dataclass
class ElementFace:
    texture_ref: str
    uv: Optional[List[float]] = None
    cullface: Optional[str] = None
    rotation: int = 0
    tintindex: int = -1

@dataclass
class ElementRotation:
    origin: List[float] = field(default_factory=lambda: [8.0, 8.0, 8.0])
    axis: str = "y"
    angle: float = 0.0
    rescale: bool = False

@dataclass
class ModelElement:
    from_pt: List[float] = field(default_factory=lambda: [0.0, 0.0, 0.0])
    to_pt: List[float] = field(default_factory=lambda: [16.0, 16.0, 16.0])
    faces: Dict[str, ElementFace] = field(default_factory=dict)
    rotation: Optional[ElementRotation] = None
    shade: bool = True

@dataclass
class GuiDisplay:
    rotation: List[float] = field(default_factory=lambda: [30.0, 225.0, 0.0])
    translation: List[float] = field(default_factory=lambda: [0.0, 0.0, 0.0])
    scale: List[float] = field(default_factory=lambda: [0.625, 0.625, 0.625])

@dataclass
class ResolvedModel:
    model_id: str
    elements: Optional[List[ModelElement]] = None
    textures: Dict[str, str] = field(default_factory=dict)
    gui: GuiDisplay = field(default_factory=GuiDisplay)
    is_2d_item: bool = False
    layers_2d: List[str] = field(default_factory=list)
