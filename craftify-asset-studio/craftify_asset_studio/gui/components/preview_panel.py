"""Item Details & 3D Render Preview Panel."""

import os
from typing import Callable, Optional
import customtkinter as ctk
from PIL import Image
from tkinter import filedialog
from ..themes import (
    COLOR_PRIMARY,
    COLOR_PRIMARY_HOVER,
    DARK_CARD_BG,
    FONT_FAMILY,
    FONT_MONO,
    LIGHT_CARD_BG
)
from ...classification.creative_tabs import TAB_DISPLAY_NAMES_ZH, TAB_ICONS

class PreviewPanel(ctk.CTkFrame):
    """Right sidebar displaying selected item details, high-res preview, and single export."""

    def __init__(self, master, on_export_single: Optional[Callable[[dict, Image.Image], None]] = None, **kwargs):
        super().__init__(master, width=320, corner_radius=10, **kwargs)
        self.on_export_single = on_export_single
        self.current_item: Optional[dict] = None
        self.current_image: Optional[Image.Image] = None

        self._init_ui()

    def _init_ui(self):
        self.grid_rowconfigure(2, weight=1)

        # 1. Header
        self.header_label = ctk.CTkLabel(
            self,
            text="Item Inspector",
            font=ctk.CTkFont(family=FONT_FAMILY, size=16, weight="bold")
        )
        self.header_label.pack(pady=(16, 8), padx=16, anchor="w")

        # 2. Image Preview Container
        self.preview_frame = ctk.CTkFrame(
            self,
            width=240,
            height=240,
            corner_radius=8,
            fg_color=("gray85", "gray15")
        )
        self.preview_frame.pack(padx=16, pady=8)
        self.preview_frame.pack_propagate(False)

        self.image_label = ctk.CTkLabel(
            self.preview_frame,
            text="No Item Selected",
            font=ctk.CTkFont(size=13)
        )
        self.image_label.place(relx=0.5, rely=0.5, anchor="center")

        # 3. Details Container
        self.details_frame = ctk.CTkScrollableFrame(self, fg_color="transparent")
        self.details_frame.pack(fill="both", expand=True, padx=12, pady=8)

        # Title EN
        self.name_en_label = ctk.CTkLabel(
            self.details_frame,
            text="",
            font=ctk.CTkFont(family=FONT_FAMILY, size=18, weight="bold"),
            anchor="w"
        )
        self.name_en_label.pack(fill="x", pady=(4, 1))

        # Title ZH
        self.name_zh_label = ctk.CTkLabel(
            self.details_frame,
            text="",
            font=ctk.CTkFont(family=FONT_FAMILY, size=14),
            text_color="gray60",
            anchor="w"
        )
        self.name_zh_label.pack(fill="x", pady=(0, 8))

        # Category Badge
        self.badge_btn = ctk.CTkButton(
            self.details_frame,
            text="Category",
            height=26,
            corner_radius=13,
            fg_color=("gray75", "gray25"),
            text_color=("gray10", "gray90"),
            state="disabled"
        )
        self.badge_btn.pack(anchor="w", pady=(0, 8))

        # ID
        self.id_label = ctk.CTkLabel(
            self.details_frame,
            text="ID: -",
            font=ctk.CTkFont(family=FONT_MONO, size=12),
            text_color=("gray30", "gray70"),
            anchor="w"
        )
        self.id_label.pack(fill="x", pady=2)

        # Model Type
        self.type_label = ctk.CTkLabel(
            self.details_frame,
            text="Type: -",
            font=ctk.CTkFont(size=12),
            text_color=("gray30", "gray70"),
            anchor="w"
        )
        self.type_label.pack(fill="x", pady=2)

        # Model Resource
        self.model_label = ctk.CTkLabel(
            self.details_frame,
            text="Model: -",
            font=ctk.CTkFont(family=FONT_MONO, size=11),
            text_color=("gray40", "gray60"),
            anchor="w",
            wraplength=260
        )
        self.model_label.pack(fill="x", pady=2)

        # 4. Action Buttons
        self.export_btn = ctk.CTkButton(
            self,
            text="Export This Icon...",
            fg_color=COLOR_PRIMARY,
            hover_color=COLOR_PRIMARY_HOVER,
            command=self._on_export_clicked
        )
        self.export_btn.pack(fill="x", padx=16, pady=(8, 16))

    def set_item(self, item_info: dict, rendered_image: Optional[Image.Image]):
        self.current_item = item_info
        self.current_image = rendered_image

        name_en = item_info.get("display_name", item_info.get("id", ""))
        name_zh = item_info.get("display_name_zh", "")
        cat = item_info.get("category", "")
        cat_zh = TAB_DISPLAY_NAMES_ZH.get(cat, cat)
        icon = TAB_ICONS.get(cat, "📦")
        item_id = item_info.get("id", "")
        model_id = item_info.get("model_id", "")
        is_block = item_info.get("is_block", True)

        self.name_en_label.configure(text=name_en)
        self.name_zh_label.configure(text=name_zh if name_zh and name_zh != name_en else "")
        self.badge_btn.configure(text=f"{icon} {cat} ({cat_zh})")
        self.id_label.configure(text=f"ID: minecraft:{item_id}")
        self.type_label.configure(text=f"Type: {'3D Block Model' if is_block else '2D Item Sprite'}")
        self.model_label.configure(text=f"Model: {model_id}")

        if rendered_image:
            # Scale for preview frame (220x220)
            preview_img = rendered_image.resize((220, 220), Image.Resampling.LANCZOS)
            ctk_img = ctk.CTkImage(light_image=preview_img, dark_image=preview_img, size=(220, 220))
            self.image_label.configure(image=ctk_img, text="")
        else:
            self.image_label.configure(image=None, text="Rendering...")

    def _on_export_clicked(self):
        if not self.current_item or not self.current_image:
            return

        item_id = self.current_item.get("id", "icon")
        file_path = filedialog.asksaveasfilename(
            title=f"Export Icon - {item_id}",
            defaultextension=".png",
            initialfile=f"{item_id}.png",
            filetypes=[("PNG Image", "*.png")]
        )
        if file_path:
            self.current_image.save(file_path, "PNG")
