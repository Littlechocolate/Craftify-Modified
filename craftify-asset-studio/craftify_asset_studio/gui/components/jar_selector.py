"""JAR Selector Header Component for CustomTkinter."""

import os
from typing import Callable, List, Optional
import customtkinter as ctk
from tkinter import filedialog
from ..themes import COLOR_PRIMARY, COLOR_PRIMARY_HOVER, FONT_FAMILY
from ...extractor.jar_scanner import JarScanner

class JarSelector(ctk.CTkFrame):
    """Header bar with JAR selection, local version detection, and status display."""

    def __init__(
        self,
        master,
        on_jar_selected: Callable[[str], None],
        on_extract_raw: Callable[[], None],
        **kwargs
    ):
        super().__init__(master, height=64, corner_radius=10, **kwargs)
        self.on_jar_selected = on_jar_selected
        self.on_extract_raw = on_extract_raw
        self.local_jars: List[dict] = JarScanner.find_local_minecraft_jars()

        self._init_ui()

    def _init_ui(self):
        # Configure grid
        self.grid_columnconfigure(2, weight=1)

        # 1. Logo / Title
        self.title_label = ctk.CTkLabel(
            self,
            text="Craftify Studio",
            font=ctk.CTkFont(family=FONT_FAMILY, size=18, weight="bold")
        )
        self.title_label.grid(row=0, column=0, padx=(16, 12), pady=12, sticky="w")

        # 2. Local Versions Dropdown
        version_names = [f"{j['version']} ({j['size_mb']} MB)" for j in self.local_jars]
        if not version_names:
            version_names = ["No Local Versions Found"]

        self.version_combo = ctk.CTkComboBox(
            self,
            values=version_names,
            width=220,
            command=self._on_version_picked
        )
        self.version_combo.grid(row=0, column=1, padx=6, pady=12, sticky="w")

        # 3. Path Display Entry
        self.path_entry = ctk.CTkEntry(
            self,
            placeholder_text="Select or drop a Minecraft client .jar file...",
            font=ctk.CTkFont(size=12)
        )
        self.path_entry.grid(row=0, column=2, padx=6, pady=12, sticky="ew")

        # 4. Browse Button
        self.browse_btn = ctk.CTkButton(
            self,
            text="Browse...",
            width=80,
            fg_color=COLOR_PRIMARY,
            hover_color=COLOR_PRIMARY_HOVER,
            command=self._on_browse_clicked
        )
        self.browse_btn.grid(row=0, column=3, padx=6, pady=12)

        # 5. Extract Raw Assets Button
        self.raw_btn = ctk.CTkButton(
            self,
            text="Extract Raw...",
            width=100,
            fg_color="transparent",
            border_width=1,
            text_color=("gray10", "gray90"),
            command=self.on_extract_raw
        )
        self.raw_btn.grid(row=0, column=4, padx=(6, 16), pady=12)

        # Preselect first detected jar if available
        if self.local_jars:
            self.set_jar_path(self.local_jars[0]["path"])

    def _on_browse_clicked(self):
        file_path = filedialog.askopenfilename(
            title="Select Minecraft .jar File",
            filetypes=[("Minecraft JAR Archive", "*.jar"), ("All Files", "*.*")]
        )
        if file_path:
            self.set_jar_path(file_path)
            self.on_jar_selected(file_path)

    def _on_version_picked(self, choice: str):
        for j in self.local_jars:
            if j["version"] in choice:
                self.set_jar_path(j["path"])
                self.on_jar_selected(j["path"])
                break

    def set_jar_path(self, path: str):
        self.path_entry.delete(0, "end")
        self.path_entry.insert(0, path)

    def get_jar_path(self) -> str:
        return self.path_entry.get().strip()
