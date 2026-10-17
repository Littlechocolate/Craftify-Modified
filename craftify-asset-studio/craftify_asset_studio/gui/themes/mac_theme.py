"""macOS UI Theme definitions and color constants for CustomTkinter."""

import darkdetect

COLOR_PRIMARY = "#0A84FF"         # macOS System Blue
COLOR_PRIMARY_HOVER = "#0071E3"
COLOR_SUCCESS = "#30D158"         # macOS System Green
COLOR_WARNING = "#FF9F0A"         # macOS System Orange
COLOR_DANGER = "#FF453A"          # macOS System Red

# Dark Mode Colors
DARK_BG = "#1E1E1E"
DARK_SIDEBAR_BG = "#181818"
DARK_CARD_BG = "#2C2C2E"
DARK_CARD_HOVER = "#3A3A3C"
DARK_TEXT = "#FFFFFF"
DARK_TEXT_SECONDARY = "#8E8E93"
DARK_BORDER = "#38383A"

# Light Mode Colors
LIGHT_BG = "#F5F5F7"
LIGHT_SIDEBAR_BG = "#EBEBEF"
LIGHT_CARD_BG = "#FFFFFF"
LIGHT_CARD_HOVER = "#E5E5EA"
LIGHT_TEXT = "#1D1D1F"
LIGHT_TEXT_SECONDARY = "#6E6E73"
LIGHT_BORDER = "#D1D1D6"

def is_dark_mode() -> bool:
    """Checks macOS system dark mode preference."""
    try:
        return darkdetect.isDark() or True
    except Exception:
        return True

FONT_FAMILY = "SF Pro Display"
FONT_MONO = "SF Mono"
