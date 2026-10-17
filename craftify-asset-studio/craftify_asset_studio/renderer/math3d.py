"""3D Transformations and Projections for Minecraft GUI rendering."""

import math
from typing import List, Tuple

def rotate_point_axis(
    p: List[float],
    origin: List[float],
    axis: str,
    angle_deg: float,
    rescale: bool = False
) -> List[float]:
    """Rotates a 3D point around an arbitrary axis passing through origin."""
    if angle_deg == 0:
        return list(p)

    angle = math.radians(angle_deg)
    cos_a = math.cos(angle)
    sin_a = math.sin(angle)
    x = p[0] - origin[0]
    y = p[1] - origin[1]
    z = p[2] - origin[2]

    if axis == "x":
        y1 = y * cos_a - z * sin_a
        z1 = y * sin_a + z * cos_a
        x1 = x
        if rescale and cos_a != 0:
            scale = 1.0 / cos_a
            y1 *= scale
            z1 *= scale
        return [x1 + origin[0], y1 + origin[1], z1 + origin[2]]
    elif axis == "y":
        x1 = x * cos_a + z * sin_a
        z1 = -x * sin_a + z * cos_a
        y1 = y
        if rescale and cos_a != 0:
            scale = 1.0 / cos_a
            x1 *= scale
            z1 *= scale
        return [x1 + origin[0], y1 + origin[1], z1 + origin[2]]
    elif axis == "z":
        x1 = x * cos_a - y * sin_a
        y1 = x * sin_a + y * cos_a
        z1 = z
        if rescale and cos_a != 0:
            scale = 1.0 / cos_a
            x1 *= scale
            y1 *= scale
        return [x1 + origin[0], y1 + origin[1], z1 + origin[2]]

    return list(p)

def transform_vec_euler(v: List[float], rot_x: float, rot_y: float, rot_z: float) -> Tuple[float, float, float]:
    """
    Applies Euler rotations matching Minecraft GUI:
    1. Z rotation
    2. Y rotation
    3. X rotation
    """
    x, y, z = v
    # 1. Z rotation
    rz = math.radians(rot_z)
    x1 = x * math.cos(rz) - y * math.sin(rz)
    y1 = x * math.sin(rz) + y * math.cos(rz)
    z1 = z

    # 2. Y rotation
    ry = math.radians(rot_y)
    x2 = x1 * math.cos(ry) + z1 * math.sin(ry)
    y2 = y1
    z2 = -x1 * math.sin(ry) + z1 * math.cos(ry)

    # 3. X rotation
    rx = math.radians(rot_x)
    x3 = x2
    y3 = y2 * math.cos(rx) - z2 * math.sin(rx)
    z3 = y2 * math.sin(rx) + z2 * math.cos(rx)

    return x3, y3, z3

def transform_point_gui(
    p: List[float],
    rotation: List[float],
    translation: List[float],
    scale: List[float]
) -> Tuple[float, float, float]:
    """Transforms a point from Minecraft block space ([0..16], centered at 8,8,8) to GUI view space."""
    x = (p[0] - 8.0) * scale[0]
    y = (p[1] - 8.0) * scale[1]
    z = (p[2] - 8.0) * scale[2]

    tx, ty, tz = transform_vec_euler([x, y, z], rotation[0], rotation[1], rotation[2])
    tx += translation[0]
    ty += translation[1]
    tz += translation[2]
    return tx, ty, tz

def get_face_corners_and_normal(
    from_pt: List[float],
    to_pt: List[float],
    face_name: str
) -> Tuple[Optional[List[List[float]]], List[float]]:
    """
    Returns 4 3D corner coordinates corresponding to texture UV:
    Index 0: Top-Left (u0, v0)
    Index 1: Top-Right (u1, v0)
    Index 2: Bottom-Right (u1, v1)
    Index 3: Bottom-Left (u0, v1)
    along with face normal vector.
    """
    x0, y0, z0 = from_pt
    x1, y1, z1 = to_pt

    if face_name == "up":
        # Y = y1 (top face)
        return [
            [x0, y1, z0],  # NW
            [x1, y1, z0],  # NE
            [x1, y1, z1],  # SE
            [x0, y1, z1]   # SW
        ], [0.0, 1.0, 0.0]
    elif face_name == "down":
        # Y = y0 (bottom face)
        return [
            [x0, y0, z1],
            [x1, y0, z1],
            [x1, y0, z0],
            [x0, y0, z0]
        ], [0.0, -1.0, 0.0]
    elif face_name == "north":
        # Z = z0 (north face)
        return [
            [x1, y1, z0],
            [x0, y1, z0],
            [x0, y0, z0],
            [x1, y0, z0]
        ], [0.0, 0.0, -1.0]
    elif face_name == "south":
        # Z = z1 (south face)
        return [
            [x0, y1, z1],
            [x1, y1, z1],
            [x1, y0, z1],
            [x0, y0, z1]
        ], [0.0, 0.0, 1.0]
    elif face_name == "west":
        # X = x0 (west face)
        return [
            [x0, y1, z0],
            [x0, y1, z1],
            [x0, y0, z1],
            [x0, y0, z0]
        ], [-1.0, 0.0, 0.0]
    elif face_name == "east":
        # X = x1 (east face)
        return [
            [x1, y1, z1],
            [x1, y1, z0],
            [x1, y0, z0],
            [x1, y0, z1]
        ], [1.0, 0.0, 0.0]

    return None, [0.0, 0.0, 0.0]
