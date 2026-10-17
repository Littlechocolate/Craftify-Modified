"""Batch Export Configuration Dialog with Progress Bar."""

import os
import threading
from typing import Callable, List, Optional
import customtkinter as ctk
from tkinter import filedialog
from ..themes import COLOR_PRIMARY, COLOR_PRIMARY_HOVER, COLOR_SUCCESS, FONT_FAMILY
from ...classification.creative_tabs import ALL_TABS, TAB_DISPLAY_NAMES_ZH

class ExportDialog(ctk.CTkToplevel):
    """Modal dialog for configuring and running batch render exports."""

    def __init__(
        self,
        master,
        items: List[dict],
        render_fn: Callable[[str, int], Optional[object]],
        on_export_finished: Optional[Callable[[], None]] = None,
        **kwargs
    ):
        super().__init__(master, **kwargs)
        self.title("Batch Export Icons")
        self.geometry("540x580")
        self.resizable(False, False)
        self.items = items
        self.render_fn = render_fn
        self.on_export_finished = on_export_finished

        self.is_running = False
        self.should_cancel = False

        # Attempt to find Craftify repo Assets.xcassets default path
        candidate_craftify = os.path.abspath(
            os.path.join(os.path.dirname(__file__), "../../../Craftify/Assets.xcassets")
        )
        self.default_craftify_path = candidate_craftify if os.path.isdir(candidate_craftify) else ""

        self._init_ui()
        self.transient(master)
        self.grab_set()

    def _init_ui(self):
        # 1. Header
        header = ctk.CTkLabel(
            self,
            text="Batch Export & Render Settings",
            font=ctk.CTkFont(family=FONT_FAMILY, size=18, weight="bold")
        )
        header.pack(pady=(18, 12), padx=20, anchor="w")

        # 2. Output Directory Frame
        dir_frame = ctk.CTkFrame(self, fg_color="transparent")
        dir_frame.pack(fill="x", padx=20, pady=6)
        dir_frame.grid_columnconfigure(0, weight=1)

        dir_label = ctk.CTkLabel(dir_frame, text="Export Directory:", font=ctk.CTkFont(size=12, weight="bold"))
        dir_label.grid(row=0, column=0, sticky="w", pady=(0, 2))

        self.dir_entry = ctk.CTkEntry(dir_frame, placeholder_text="Choose destination folder...")
        self.dir_entry.insert(0, os.path.abspath("./output_icons"))
        self.dir_entry.grid(row=1, column=0, sticky="ew", padx=(0, 8))

        browse_btn = ctk.CTkButton(
            dir_frame,
            text="Browse...",
            width=80,
            command=self._on_browse_output
        )
        browse_btn.grid(row=1, column=1)

        # 3. Settings Grid
        settings_frame = ctk.CTkFrame(self, corner_radius=8)
        settings_frame.pack(fill="x", padx=20, pady=12)

        # Resolution
        res_label = ctk.CTkLabel(settings_frame, text="Resolution:")
        res_label.grid(row=0, column=0, padx=12, pady=10, sticky="w")
        self.res_segmented = ctk.CTkSegmentedButton(
            settings_frame,
            values=["64px", "128px", "256px", "300px", "512px"]
        )
        self.res_segmented.set("256px")
        self.res_segmented.grid(row=0, column=1, padx=12, pady=10, sticky="ew")

        # Category Filter
        cat_label = ctk.CTkLabel(settings_frame, text="Category Filter:")
        cat_label.grid(row=1, column=0, padx=12, pady=10, sticky="w")
        cat_options = ["All Categories"] + [f"{c} ({TAB_DISPLAY_NAMES_ZH.get(c, c)})" for c in ALL_TABS]
        self.cat_combo = ctk.CTkComboBox(settings_frame, values=cat_options, width=280)
        self.cat_combo.set("All Categories")
        self.cat_combo.grid(row=1, column=1, padx=12, pady=10, sticky="ew")

        # Checkbox: Group by Creative Category folders
        self.group_cat_var = ctk.BooleanVar(value=True)
        self.group_cat_check = ctk.CTkCheckBox(
            settings_frame,
            text="Organize output files by Creative Category folders",
            variable=self.group_cat_var
        )
        self.group_cat_check.grid(row=2, column=0, columnspan=2, padx=12, pady=(4, 10), sticky="w")

        # 4. Craftify Assets Integration
        craftify_frame = ctk.CTkFrame(self, corner_radius=8)
        craftify_frame.pack(fill="x", padx=20, pady=6)
        craftify_frame.grid_columnconfigure(0, weight=1)

        self.craftify_var = ctk.BooleanVar(value=bool(self.default_craftify_path))
        self.craftify_check = ctk.CTkCheckBox(
            craftify_frame,
            text="Directly export into Craftify Assets.xcassets format (.imageset)",
            variable=self.craftify_var,
            command=self._toggle_craftify
        )
        self.craftify_check.grid(row=0, column=0, columnspan=2, padx=12, pady=(10, 6), sticky="w")

        self.craftify_entry = ctk.CTkEntry(craftify_frame, placeholder_text="Path to Assets.xcassets...")
        if self.default_craftify_path:
            self.craftify_entry.insert(0, self.default_craftify_path)
        self.craftify_entry.grid(row=1, column=0, sticky="ew", padx=(12, 8), pady=(0, 10))

        self.craftify_browse = ctk.CTkButton(
            craftify_frame,
            text="Browse...",
            width=80,
            command=self._on_browse_craftify
        )
        self.craftify_browse.grid(row=1, column=1, padx=(0, 12), pady=(0, 10))
        self._toggle_craftify()

        # 5. Progress Section
        self.progress_bar = ctk.CTkProgressBar(self)
        self.progress_bar.set(0)
        self.progress_bar.pack(fill="x", padx=20, pady=(16, 6))

        self.status_label = ctk.CTkLabel(
            self,
            text="Ready to export.",
            font=ctk.CTkFont(size=12),
            text_color="gray60"
        )
        self.status_label.pack(anchor="w", padx=20, pady=(0, 12))

        # 6. Bottom Action Buttons
        btn_frame = ctk.CTkFrame(self, fg_color="transparent")
        btn_frame.pack(fill="x", padx=20, pady=(6, 16))

        self.cancel_btn = ctk.CTkButton(
            btn_frame,
            text="Cancel",
            fg_color="transparent",
            border_width=1,
            text_color=("gray20", "gray80"),
            command=self._on_cancel
        )
        self.cancel_btn.pack(side="left")

        self.start_btn = ctk.CTkButton(
            btn_frame,
            text="Start Export",
            fg_color=COLOR_PRIMARY,
            hover_color=COLOR_PRIMARY_HOVER,
            command=self._on_start_clicked
        )
        self.start_btn.pack(side="right")

    def _toggle_craftify(self):
        state = "normal" if self.craftify_var.get() else "disabled"
        self.craftify_entry.configure(state=state)
        self.craftify_browse.configure(state=state)

    def _on_browse_output(self):
        folder = filedialog.askdirectory(title="Select Output Directory")
        if folder:
            self.dir_entry.delete(0, "end")
            self.dir_entry.insert(0, folder)

    def _on_browse_craftify(self):
        folder = filedialog.askdirectory(title="Select Assets.xcassets Directory")
        if folder:
            self.craftify_entry.delete(0, "end")
            self.craftify_entry.insert(0, folder)

    def _on_start_clicked(self):
        if self.is_running:
            return

        out_dir = self.dir_entry.get().strip()
        if not out_dir:
            self.status_label.configure(text="Please choose an export directory.")
            return

        self.is_running = True
        self.should_cancel = False
        self.start_btn.configure(state="disabled")
        self.cancel_btn.configure(text="Stop")

        # Parse options
        res_str = self.res_segmented.get().replace("px", "")
        resolution = int(res_str) if res_str.isdigit() else 256
        selected_cat_raw = self.cat_combo.get()
        filter_cat = None
        if selected_cat_raw != "All Categories":
            filter_cat = selected_cat_raw.split(" (")[0]

        craftify_path = self.craftify_entry.get().strip() if self.craftify_var.get() else None

        # Start thread
        thread = threading.Thread(
            target=self._run_export,
            args=(out_dir, resolution, filter_cat, craftify_path, self.group_cat_var.get()),
            daemon=True
        )
        thread.start()

    def _run_export(
        self,
        output_dir: str,
        resolution: int,
        filter_category: Optional[str],
        craftify_path: Optional[str],
        group_by_cat: bool
    ):
        from ..exporter import CraftifyExporter, FileExporter
        exporter = FileExporter(output_dir)
        craftify_exp = CraftifyExporter(craftify_path) if craftify_path else None

        # Filter items
        target_items = [
            it for it in self.items
            if filter_category is None or it.get("category") == filter_category
        ]

        total = len(target_items)
        if total == 0:
            self.after(0, lambda: self.status_label.configure(text="No items to export."))
            self._finish_export(0)
            return

        success_count = 0
        catalog = []

        for idx, item in enumerate(target_items, 1):
            if self.should_cancel:
                break

            item_id = item.get("id", "")
            cat = item.get("category", "Building Blocks")
            model_id = item.get("model_id", f"block/{item_id}")
            display_name = item.get("display_name", item_id)

            self.after(0, lambda i=idx, n=display_name: self._update_progress(i, total, n))

            try:
                img = self.render_fn(model_id, resolution)
                if img:
                    out_path = exporter.export_icon(
                        img,
                        category=cat,
                        item_id=item_id,
                        display_name=display_name,
                        export_by_category=group_by_cat
                    )
                    if craftify_exp:
                        craftify_exp.export_imageset(img, display_name)

                    catalog.append({
                        "id": item_id,
                        "name": display_name,
                        "name_zh": item.get("display_name_zh", ""),
                        "category": cat,
                        "file_path": out_path
                    })
                    success_count += 1
            except Exception:
                pass

        exporter.write_catalog_json(catalog)
        self._finish_export(success_count)

    def _update_progress(self, current: int, total: int, current_name: str):
        fraction = current / total
        self.progress_bar.set(fraction)
        self.status_label.configure(
            text=f"[{current}/{total}] Rendering: {current_name}..."
        )

    def _finish_export(self, count: int):
        def ui_done():
            self.is_running = False
            self.start_btn.configure(state="normal")
            self.cancel_btn.configure(text="Close")
            self.status_label.configure(
                text=f"Export finished! Rendered {count} icons."
            )
            if self.on_export_finished:
                self.on_export_finished()

        self.after(0, ui_done)

    def _on_cancel(self):
        if self.is_running:
            self.should_cancel = True
            self.status_label.configure(text="Stopping export...")
        else:
            self.destroy()
