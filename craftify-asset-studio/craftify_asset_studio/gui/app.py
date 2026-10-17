"""
High-Performance macOS Minecraft Block & Item Model Extractor & Inventory Renderer GUI.
Native Tkinter + ttk implementation featuring virtualized canvas scrolling (60 FPS),
background pre-rendering thread, interactive 3D rotation inspector, and Craftify iOS exporter.
Strictly implements the architecture and visual accuracy of V2 software rasterizer.
"""

import json
import math
import os
import platform
import threading
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
from typing import Dict, List, Optional, Tuple
from PIL import Image, ImageTk

from ..classification import CREATIVE_TABS_META, TAB_NAME_MAP
from ..exporter import CraftifyExporter
from ..extractor import JarScanner
from ..renderer import IsometricRenderer


class CraftifyStudioApp(tk.Tk):
    """Craftify Asset Studio macOS High-Performance GUI Application."""

    def __init__(self, start_jar: Optional[str] = None):
        super().__init__()
        self.title("Craftify Asset Studio - Minecraft 模型提取与创造物品栏 3D/2D 渲染器")
        self.geometry("1320x840")
        self.minsize(1080, 700)
        self.configure(bg="#1E2026")

        # macOS Retina high-DPI scaling
        if platform.system() == "Darwin":
            try:
                self.tk.call("tk", "scaling", 2.0)
            except Exception:
                pass

        self.renderer: Optional[IsometricRenderer] = None
        self.current_tab: str = "building_blocks"
        self.filtered_items: List[str] = []
        self.selected_item: Optional[str] = None
        self.icon_tk_cache: Dict[Tuple[str, int], ImageTk.PhotoImage] = {}
        self.icon_pil_cache: Dict[Tuple[str, int], Image.Image] = {}
        self.preview_tk_ref: Optional[ImageTk.PhotoImage] = None
        self.last_preview_pil: Optional[Image.Image] = None
        self.slot_hitboxes: Dict[Tuple[int, int, int, int], str] = {}
        self.is_rendering_bg: bool = False

        self._setup_styles()
        self._build_ui()

        # If starting jar is provided or local JAR exists, auto-load
        target_jar = start_jar
        if not target_jar or not os.path.isfile(target_jar):
            local_jars = JarScanner.find_local_minecraft_jars()
            if local_jars:
                target_jar = local_jars[0]["path"]

        if target_jar and os.path.isfile(target_jar):
            self.after(150, lambda: self.load_jar_file(target_jar))

    @property
    def filtered_blocks(self) -> List[str]:
        return self.filtered_items

    @filtered_blocks.setter
    def filtered_blocks(self, val: List[str]):
        self.filtered_items = val

    @property
    def selected_block(self) -> Optional[str]:
        return self.selected_item

    @selected_block.setter
    def selected_block(self, val: Optional[str]):
        self.selected_item = val

    def _setup_styles(self):
        style = ttk.Style(self)
        try:
            style.theme_use("clam")
        except Exception:
            pass
        style.configure("TFrame", background="#1E2026")
        style.configure("Panel.TFrame", background="#282B33")
        style.configure("TLabel", background="#1E2026", foreground="#E6E9F0", font=("Helvetica", 11))
        style.configure("Header.TLabel", background="#282B33", foreground="#FFFFFF", font=("Helvetica", 13, "bold"))
        style.configure("Sub.TLabel", background="#282B33", foreground="#9AA2B2", font=("Helvetica", 10))
        style.configure("TButton", background="#3B4252", foreground="#ECEFF4", padding=(10, 5), font=("Helvetica", 10, "bold"))
        style.map("TButton", background=[("active", "#4C566A")])
        style.configure("Accent.TButton", background="#5E81AC", foreground="#FFFFFF", padding=(12, 6), font=("Helvetica", 10, "bold"))
        style.map("Accent.TButton", background=[("active", "#81A1C1")])
        style.configure("TProgressbar", thickness=8)

    def _build_ui(self):
        # 1. Top Bar
        top_bar = ttk.Frame(self, style="Panel.TFrame", padding=(12, 10))
        top_bar.pack(side=tk.TOP, fill=tk.X)

        ttk.Button(top_bar, text="📂 打开 Minecraft .jar", style="Accent.TButton", command=self._on_open_jar).pack(side=tk.LEFT, padx=(0, 6))
        ttk.Button(top_bar, text="📦 提取模型贴图源文件", command=self._on_extract_assets).pack(side=tk.LEFT, padx=3)
        ttk.Button(top_bar, text="🖼️ 按创造分类导出全部 PNG", command=self._on_export_all).pack(side=tk.LEFT, padx=3)
        ttk.Button(top_bar, text="🗺️ 导出图集海报", command=self._on_export_atlas).pack(side=tk.LEFT, padx=3)
        ttk.Button(top_bar, text="📱 批量导出至 Craftify iOS", command=self._on_export_craftify_batch).pack(side=tk.LEFT, padx=3)
        ttk.Button(top_bar, text="📜 打包 .recipe (含图标)", command=self._on_export_recipe_package).pack(side=tk.LEFT, padx=3)

        # Type Filter Dropdown
        ttk.Label(top_bar, text="类型:", style="Sub.TLabel").pack(side=tk.LEFT, padx=(10, 2))
        self.type_filter_var = tk.StringVar(value="全部 (方块+物品)")
        type_cb = ttk.Combobox(
            top_bar,
            textvariable=self.type_filter_var,
            values=["全部 (方块+物品)", "仅方块 (Blocks)", "仅物品 (Items)"],
            width=13,
            state="readonly",
        )
        type_cb.pack(side=tk.LEFT, padx=2)
        type_cb.bind("<<ComboboxSelected>>", lambda *_: self._refresh_grid())

        # Search Bar
        ttk.Label(top_bar, text="🔍 搜索:", style="Sub.TLabel").pack(side=tk.LEFT, padx=(10, 2))
        self.search_var = tk.StringVar()
        self.search_var.trace_add("write", lambda *_: self._refresh_grid())
        search_entry = ttk.Entry(top_bar, textvariable=self.search_var, width=16)
        search_entry.pack(side=tk.LEFT, padx=2)

        # Size Dropdown
        ttk.Label(top_bar, text="尺寸:", style="Sub.TLabel").pack(side=tk.LEFT, padx=(8, 2))
        self.size_var = tk.StringVar(value="64")
        size_cb = ttk.Combobox(top_bar, textvariable=self.size_var, values=["48", "64", "80", "96"], width=4, state="readonly")
        size_cb.pack(side=tk.LEFT, padx=2)
        size_cb.bind("<<ComboboxSelected>>", lambda *_: self._refresh_grid())

        # Status Label
        self.status_var = tk.StringVar(value="请点击左上角「打开 Minecraft .jar」加载版本文件")
        ttk.Label(top_bar, textvariable=self.status_var, style="Sub.TLabel").pack(side=tk.RIGHT, padx=8)

        # 2. Main Three-Column Layout
        main_pane = ttk.Frame(self, padding=(10, 8))
        main_pane.pack(side=tk.TOP, fill=tk.BOTH, expand=True)

        # Left Column: Creative Tabs
        left_panel = ttk.Frame(main_pane, style="Panel.TFrame", padding=(10, 10), width=235)
        left_panel.pack(side=tk.LEFT, fill=tk.Y, padx=(0, 8))
        left_panel.pack_propagate(False)

        ttk.Label(left_panel, text="创造模式物品栏分类", style="Header.TLabel").pack(anchor=tk.W, pady=(0, 8))
        self.tab_buttons: Dict[str, tk.Button] = {}
        for tab_key, tab_label, _ in CREATIVE_TABS_META:
            btn = tk.Button(
                left_panel,
                text=f"{tab_label} (0)",
                anchor="w",
                bg="#323642",
                fg="#E6E9F0",
                activebackground="#5E81AC",
                activeforeground="#FFFFFF",
                relief=tk.FLAT,
                padx=10,
                pady=6,
                font=("Helvetica", 10, "bold"),
                command=lambda k=tab_key: self._select_tab(k),
            )
            btn.pack(fill=tk.X, pady=2)
            self.tab_buttons[tab_key] = btn

        # Progress Bar
        ttk.Label(left_panel, text="后台预渲染进度:", style="Sub.TLabel").pack(anchor=tk.W, pady=(14, 4))
        self.progress_var = tk.DoubleVar(value=0.0)
        self.progress_bar = ttk.Progressbar(left_panel, variable=self.progress_var, maximum=100.0)
        self.progress_bar.pack(fill=tk.X, pady=2)
        self.progress_label_var = tk.StringVar(value="就绪")
        ttk.Label(left_panel, textvariable=self.progress_label_var, style="Sub.TLabel", wraplength=210).pack(anchor=tk.W, pady=4)

        # Center Column: Virtualized Grid Canvas (Smooth 60 FPS)
        center_panel = ttk.Frame(main_pane, style="Panel.TFrame", padding=(6, 6))
        center_panel.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 8))

        self.grid_header_var = tk.StringVar(value="🧱 建筑方块 (Building Blocks)")
        ttk.Label(center_panel, textvariable=self.grid_header_var, style="Header.TLabel").pack(anchor=tk.W, padx=6, pady=(2, 6))

        canvas_frame = ttk.Frame(center_panel, style="Panel.TFrame")
        canvas_frame.pack(fill=tk.BOTH, expand=True)

        self.grid_canvas = tk.Canvas(canvas_frame, bg="#20232A", highlightthickness=0)
        self.scrollbar = ttk.Scrollbar(canvas_frame, orient=tk.VERTICAL, command=self._on_scroll_bar)
        self.grid_canvas.configure(yscrollcommand=self.scrollbar.set)

        self.scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.grid_canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        self.grid_canvas.bind("<Configure>", lambda e: self._redraw_visible_slots())
        self.grid_canvas.bind("<Button-1>", self._on_canvas_click)
        # Mousewheel binding
        self.grid_canvas.bind("<MouseWheel>", self._on_mousewheel)
        self.grid_canvas.bind("<Button-4>", lambda e: self._scroll_step(-3))
        self.grid_canvas.bind("<Button-5>", lambda e: self._scroll_step(3))

        # Right Column: 3D/2D Interactive Inspector & Model Details
        right_panel = ttk.Frame(main_pane, style="Panel.TFrame", padding=(12, 10), width=335)
        right_panel.pack(side=tk.RIGHT, fill=tk.Y)
        right_panel.pack_propagate(False)

        ttk.Label(right_panel, text="3D/2D 物品栏检视与模型解析", style="Header.TLabel").pack(anchor=tk.W, pady=(0, 6))

        self.preview_canvas = tk.Canvas(right_panel, width=220, height=220, bg="#1B1D24", highlightthickness=1, highlightbackground="#434C5E")
        self.preview_canvas.pack(pady=4)

        self.detail_title_var = tk.StringVar(value="未选择方块或物品")
        ttk.Label(right_panel, textvariable=self.detail_title_var, style="Header.TLabel", wraplength=305).pack(anchor=tk.W, pady=(6, 2))

        self.detail_id_var = tk.StringVar(value="ID: -")
        ttk.Label(right_panel, textvariable=self.detail_id_var, style="Sub.TLabel").pack(anchor=tk.W)

        # Live 3D Rotation Sliders (active for blocks & 3D models)
        rot_frame = ttk.Frame(right_panel, style="Panel.TFrame")
        rot_frame.pack(fill=tk.X, pady=(8, 4))

        self.rot_x_var = tk.DoubleVar(value=30.0)
        self.rot_y_var = tk.DoubleVar(value=225.0)
        self.scale_var = tk.DoubleVar(value=0.625)

        self._add_slider(rot_frame, "俯仰角 X (Pitch):", self.rot_x_var, -90, 90)
        self._add_slider(rot_frame, "偏航角 Y (Yaw):", self.rot_y_var, 0, 360)
        self._add_slider(rot_frame, "缩放比 (Scale):", self.scale_var, 0.30, 1.10)

        btn_row = ttk.Frame(right_panel, style="Panel.TFrame")
        btn_row.pack(fill=tk.X, pady=4)
        ttk.Button(btn_row, text="重置标准 GUI 视角", command=self._reset_preview_angles).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=(0, 2))
        ttk.Button(btn_row, text="💾 保存大图", command=self._save_single_preview).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=2)
        ttk.Button(btn_row, text="📱 导出至 iOS", command=self._export_single_to_craftify).pack(side=tk.LEFT, expand=True, fill=tk.X, padx=(2, 0))

        # Model & Texture Details Text Box
        ttk.Label(right_panel, text="模型继承链与绑定贴图:", style="Sub.TLabel").pack(anchor=tk.W, pady=(8, 2))
        self.info_text = tk.Text(
            right_panel, height=13, bg="#1B1D24", fg="#D8DEE9",
            font=("Menlo" if platform.system() == "Darwin" else "Monospace", 9),
            relief=tk.FLAT, padx=6, pady=6, wrap=tk.WORD
        )
        self.info_text.pack(fill=tk.BOTH, expand=True, pady=2)

    def _add_slider(self, parent, label_txt, var, vmin, vmax):
        row = ttk.Frame(parent, style="Panel.TFrame")
        row.pack(fill=tk.X, pady=2)
        ttk.Label(row, text=label_txt, style="Sub.TLabel", width=15).pack(side=tk.LEFT)
        sc = ttk.Scale(row, variable=var, from_=vmin, to=vmax, orient=tk.HORIZONTAL, command=lambda *_: self._update_live_preview())
        sc.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=4)

    def _on_open_jar(self):
        path = filedialog.askopenfilename(
            title="选择 Minecraft .jar 文件",
            filetypes=[("Minecraft JAR", "*.jar"), ("All Files", "*.*")],
        )
        if path:
            self.load_jar_file(path)

    def load_jar_file(self, jar_path: str):
        try:
            self.status_var.set(f"正在解析: {os.path.basename(jar_path)} ...")
            self.update_idletasks()
            self.renderer = IsometricRenderer(jar_path, icon_size=64, ssaa=2)
            self.icon_tk_cache.clear()
            self.icon_pil_cache.clear()

            for tab_key, tab_label, _ in CREATIVE_TABS_META:
                cnt = len(self.renderer.categories.get(tab_key, []))
                self.tab_buttons[tab_key].configure(text=f"{tab_label} ({cnt})")

            self.status_var.set(
                f"已加载 {os.path.basename(jar_path)} | 共 {len(self.renderer.all_items)} 项 "
                f"({len(self.renderer.block_items)} 方块 + {len(self.renderer.non_block_items)} 物品)"
            )
            self._select_tab("building_blocks")
            self._start_background_prerender()
        except Exception as e:
            messagebox.showerror("加载失败", f"无法解析该 .jar 文件:\n{e}")

    def _start_background_prerender(self):
        if not self.renderer:
            return
        all_it = list(self.renderer.all_items)
        total = len(all_it)

        def worker():
            for idx, it in enumerate(all_it):
                if not self.renderer:
                    break
                try:
                    if not self.winfo_exists():
                        break
                except Exception:
                    break
                key = (it, 64)
                if key not in self.icon_pil_cache:
                    try:
                        self.icon_pil_cache[key] = self.renderer.render_item(it, target_size=64)
                    except Exception:
                        pass
                if idx % 25 == 0 or idx == total - 1:
                    pct = (idx + 1) / max(1, total) * 100.0
                    try:
                        self.after(0, lambda p=pct, i=idx + 1, n=it: self._update_bg_progress(p, i, total, n))
                    except Exception:
                        break

        threading.Thread(target=worker, daemon=True).start()

    def _update_bg_progress(self, pct: float, done: int, total: int, cur_name: str):
        self.progress_var.set(pct)
        if done >= total:
            self.progress_label_var.set(f"✅ 全部 {total} 个方块与物品渲染完成")
        else:
            self.progress_label_var.set(f"正在渲染 ({done}/{total}): {cur_name}")
        self._redraw_visible_slots()

    def _select_tab(self, tab_key: str):
        self.current_tab = tab_key
        for k, btn in self.tab_buttons.items():
            btn.configure(bg="#5E81AC" if k == tab_key else "#323642")
        self._refresh_grid()

    def _refresh_grid(self):
        if not self.renderer:
            return
        raw_list = self.renderer.categories.get(self.current_tab, [])
        tf_val = self.type_filter_var.get()
        if "仅方块" in tf_val:
            raw_list = [x for x in raw_list if self.renderer.is_block_item(x)]
        elif "仅物品" in tf_val:
            raw_list = [x for x in raw_list if not self.renderer.is_block_item(x)]

        q = self.search_var.get().strip().lower()
        if q:
            self.filtered_items = [
                it for it in raw_list
                if q in it.lower() or q in self.renderer.get_display_name(it).lower()
            ]
        else:
            self.filtered_items = list(raw_list)

        b_cnt = sum(1 for x in self.filtered_items if self.renderer.is_block_item(x))
        i_cnt = len(self.filtered_items) - b_cnt
        tab_title = TAB_NAME_MAP.get(self.current_tab, self.current_tab)
        self.grid_header_var.set(f"{tab_title} — 共 {len(self.filtered_items)} 项 ({b_cnt} 方块, {i_cnt} 物品)")
        self.grid_canvas.yview_moveto(0.0)
        self._redraw_visible_slots()
        if self.filtered_items and self.selected_item not in self.filtered_items:
            self._select_item(self.filtered_items[0])

    def _on_scroll_bar(self, *args):
        self.grid_canvas.yview(*args)
        self._redraw_visible_slots()

    def _scroll_step(self, units: int):
        self.grid_canvas.yview_scroll(units, "units")
        self._redraw_visible_slots()

    def _on_mousewheel(self, event):
        if platform.system() == "Darwin":
            self.grid_canvas.yview_scroll(int(-1 * event.delta), "units")
        else:
            self.grid_canvas.yview_scroll(int(-1 * (event.delta / 120)), "units")
        self._redraw_visible_slots()

    def _redraw_visible_slots(self):
        self.grid_canvas.delete("all")
        if not self.renderer or not self.filtered_items:
            return

        icon_sz = int(self.size_var.get())
        slot_sz = icon_sz + 18
        pad = 8
        pitch = slot_sz + pad
        canvas_w = max(300, self.grid_canvas.winfo_width())
        cols = max(1, (canvas_w - 16) // pitch)
        total_rows = max(1, math.ceil(len(self.filtered_items) / cols))
        total_h = total_rows * (pitch + 16) + 20
        self.grid_canvas.configure(scrollregion=(0, 0, canvas_w, total_h))

        # Virtualized grid rendering: only draw visible viewport slots
        y0_frac, y1_frac = self.grid_canvas.yview()
        vis_y0 = y0_frac * total_h - (pitch + 20)
        vis_y1 = y1_frac * total_h + (pitch + 20)

        start_row = max(0, int(vis_y0 // (pitch + 16)))
        end_row = min(total_rows - 1, int(vis_y1 // (pitch + 16)) + 1)

        self.slot_hitboxes = {}
        for r in range(start_row, end_row + 1):
            for c in range(cols):
                idx = r * cols + c
                if idx >= len(self.filtered_items):
                    break
                it_name = self.filtered_items[idx]
                x = 12 + c * pitch
                y = 12 + r * (pitch + 16)

                is_sel = (it_name == self.selected_item)
                is_blk = self.renderer.is_block_item(it_name)
                bg_col = "#4C566A" if is_sel else ("#3B4252" if is_blk else "#2E3846")
                border_col = "#88C0D0" if is_sel else ("#434C5E" if is_blk else "#3E526A")
                bw = 2 if is_sel else 1

                self.grid_canvas.create_rectangle(
                    x, y, x + slot_sz, y + slot_sz,
                    fill=bg_col, outline=border_col, width=bw
                )

                tk_img = self._get_or_render_tk_icon(it_name, icon_sz)
                if tk_img:
                    self.grid_canvas.create_image(x + slot_sz // 2, y + slot_sz // 2, image=tk_img)

                short_lbl = it_name if len(it_name) <= 12 else it_name[:11] + "…"
                self.grid_canvas.create_text(
                    x + slot_sz // 2, y + slot_sz + 9,
                    text=short_lbl, fill="#D8DEE9", font=("Helvetica", 8)
                )
                self.slot_hitboxes[(x, y, x + slot_sz, y + slot_sz + 14)] = it_name

    def _get_or_render_tk_icon(self, it_name: str, icon_sz: int):
        key = (it_name, icon_sz)
        if key in self.icon_tk_cache:
            return self.icon_tk_cache[key]
        base_key = (it_name, 64)
        if base_key in self.icon_pil_cache:
            pil_img = self.icon_pil_cache[base_key]
            if icon_sz != 64:
                pil_img = pil_img.resize((icon_sz, icon_sz), Image.Resampling.LANCZOS)
        else:
            pil_img = self.renderer.render_item(it_name, target_size=icon_sz)
            if icon_sz == 64:
                self.icon_pil_cache[base_key] = pil_img
        tk_img = ImageTk.PhotoImage(pil_img)
        self.icon_tk_cache[key] = tk_img
        return tk_img

    def _on_canvas_click(self, event):
        cx = self.grid_canvas.canvasx(event.x)
        cy = self.grid_canvas.canvasy(event.y)
        for (x1, y1, x2, y2), it_name in self.slot_hitboxes.items():
            if x1 <= cx <= x2 and y1 <= cy <= y2:
                self._select_item(it_name)
                break

    def _select_item(self, it_name: str):
        self.selected_item = it_name
        self._redraw_visible_slots()
        if not self.renderer:
            return

        disp_name = self.renderer.get_display_name(it_name)
        is_blk = self.renderer.is_block_item(it_name)
        kind_str = "方块物品 (Block Item)" if is_blk else "非方块物品 (Standard Item)"
        self.detail_title_var.set(disp_name)
        self.detail_id_var.set(f"ID: minecraft:{it_name}  [{kind_str}]")

        spec = self.renderer.get_item_model_spec(it_name)
        leaf_model_id = self.renderer.extract_primary_leaf_model_id(spec) or f"item/{it_name}"
        resolved = self.renderer.resolve_model(leaf_model_id) if isinstance(leaf_model_id, str) else {}

        belong_tabs = [
            TAB_NAME_MAP[k] for k, _, _ in CREATIVE_TABS_META
            if k != "all_items" and it_name in self.renderer.categories.get(k, [])
        ]

        lines = [
            f"【资源 ID】 minecraft:{it_name}",
            f"【对象类型】 {kind_str}",
            f"【显示名称】 {disp_name}",
            f"【创造物品栏】 {', '.join(belong_tabs) if belong_tabs else '未归类'}",
            f"【定义模型类型】 {spec.get('type', 'minecraft:model')}",
        ]
        if resolved.get("parent_chain"):
            lines.append("【模型继承链】\n  " + " -> ".join(resolved["parent_chain"]))
        if resolved.get("textures"):
            lines.append("【绑定贴图文件】")
            for tk_k, tk_v in resolved["textures"].items():
                lines.append(f"  #{tk_k}: textures/{tk_v}.png")
        if resolved.get("elements"):
            lines.append(f"【渲染模式】 3D 等轴测光栅化 ({len(resolved['elements'])} 个 Element)")
        else:
            lines.append("【渲染模式】 2D 图层像素混合 / 特殊实体合成")

        self.info_text.configure(state=tk.NORMAL)
        self.info_text.delete("1.0", tk.END)
        self.info_text.insert(tk.END, "\n".join(lines))
        self.info_text.configure(state=tk.DISABLED)

        self._update_live_preview()

    _select_block = _select_item

    def _reset_preview_angles(self):
        self.rot_x_var.set(30.0)
        self.rot_y_var.set(225.0)
        self.scale_var.set(0.625)
        self._update_live_preview()

    def _update_live_preview(self):
        if not self.renderer or not self.selected_item:
            return
        custom_tf = {
            "rotation": [float(self.rot_x_var.get()), float(self.rot_y_var.get()), 0.0],
            "translation": [0.0, 0.0, 0.0],
            "scale": [float(self.scale_var.get())] * 3,
        }
        use_tf = None
        if abs(custom_tf["rotation"][0] - 30.0) > 0.5 or abs(custom_tf["rotation"][1] - 225.0) > 0.5 or abs(custom_tf["scale"][0] - 0.625) > 0.01:
            use_tf = custom_tf

        pil_hi = self.renderer.render_item(self.selected_item, target_size=192, custom_gui_transform=use_tf)
        self.last_preview_pil = pil_hi
        self.preview_tk_ref = ImageTk.PhotoImage(pil_hi)
        self.preview_canvas.delete("all")
        self.preview_canvas.create_image(110, 110, image=self.preview_tk_ref)

    def _save_single_preview(self):
        if not getattr(self, "last_preview_pil", None) or not self.selected_item:
            return
        out = filedialog.asksaveasfilename(
            title="保存高清渲染大图",
            initialfile=f"{self.selected_item}_render.png",
            defaultextension=".png",
            filetypes=[("PNG Image", "*.png")],
        )
        if out:
            self.last_preview_pil.save(out)
            messagebox.showinfo("保存成功", f"已保存至:\n{out}")

    def _export_single_to_craftify(self):
        if not getattr(self, "last_preview_pil", None) or not self.selected_item:
            return
        default_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../Craftify/Assets.xcassets"))
        initial = default_dir if os.path.isdir(default_dir) else os.getcwd()
        xcassets_dir = filedialog.askdirectory(title="选择 Craftify Assets.xcassets 目录", initialdir=initial)
        if not xcassets_dir:
            return

        it_name = self.selected_item
        en_name = self.renderer.lang_en.get(
            f"block.minecraft.{it_name}",
            self.renderer.lang_en.get(f"item.minecraft.{it_name}", it_name.replace("_", " ").title())
        )
        exporter = CraftifyExporter(xcassets_dir)
        # Render high-res 3x image (192px)
        img_3x = self.renderer.render_item(it_name, target_size=192)
        imageset_path = exporter.export_imageset(img_3x, en_name, preserve_existing=False)
        messagebox.showinfo("导出成功", f"已成功将 {en_name} 导出为 iOS .imageset:\n{imageset_path}")

    def _on_extract_assets(self):
        if not self.renderer:
            messagebox.showwarning("提示", "请先加载 Minecraft .jar 文件！")
            return
        out_dir = filedialog.askdirectory(title="选择模型与贴图提取保存目录")
        if not out_dir:
            return

        def run_extract():
            counts = self.renderer.extract_assets_to_dir(
                out_dir,
                progress_cb=lambda d, t, msg: self.after(0, lambda: (
                    self.progress_var.set(d / max(1, t) * 100.0),
                    self.progress_label_var.set(msg)
                )),
            )
            self.after(0, lambda: messagebox.showinfo(
                "提取完成",
                f"已成功从 JAR 提取文件至:\n{out_dir}\n\n"
                f"• 模型文件 (models): {counts['models']} 个\n"
                f"• 贴图文件 (textures): {counts['textures']} 个\n"
                f"• 物品与方块状态定义: {counts['items_and_blockstates']} 个"
            ))

        threading.Thread(target=run_extract, daemon=True).start()

    def _on_export_all(self):
        if not self.renderer:
            messagebox.showwarning("提示", "请先加载 Minecraft .jar 文件！")
            return
        out_dir = filedialog.askdirectory(title="选择按创造物品栏分类导出渲染图的目录")
        if not out_dir:
            return
        sz = int(self.size_var.get())
        tf_val = self.type_filter_var.get()
        f_mode = "blocks" if "仅方块" in tf_val else ("items" if "仅物品" in tf_val else "all")

        def run_export():
            manifest_p = self.renderer.export_categorized_renders(
                out_dir,
                icon_size=sz,
                filter_mode=f_mode,
                progress_cb=lambda d, t, msg: self.after(0, lambda: (
                    self.progress_var.set(d / max(1, t) * 100.0),
                    self.progress_label_var.set(msg)
                )),
            )
            self.after(0, lambda: messagebox.showinfo(
                "分类渲染导出完成",
                f"已按创造物品栏分类导出全部渲染图！\n目录: {out_dir}\n清单: {manifest_p}"
            ))

        threading.Thread(target=run_export, daemon=True).start()

    def _on_export_atlas(self):
        if not self.renderer:
            messagebox.showwarning("提示", "请先加载 Minecraft .jar 文件！")
            return
        out_file = filedialog.asksaveasfilename(
            title="保存创造物品栏分类图集海报",
            initialfile="minecraft_creative_tabs_atlas.png",
            defaultextension=".png",
            filetypes=[("PNG Image", "*.png")],
        )
        if not out_file:
            return

        def run_atlas():
            self.after(0, lambda: self.progress_label_var.set("正在生成创造物品栏全分类图集海报..."))
            self.renderer.generate_creative_atlas_poster(out_file)
            self.after(0, lambda: (
                self.progress_label_var.set("✅ 图集海报导出完成"),
                messagebox.showinfo("导出成功", f"创造物品栏分类图集已保存至:\n{out_file}")
            ))

        threading.Thread(target=run_atlas, daemon=True).start()

    def _on_export_craftify_batch(self):
        if not self.renderer:
            messagebox.showwarning("提示", "请先加载 Minecraft .jar 文件！")
            return
        default_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../Craftify/Assets.xcassets"))
        initial = default_dir if os.path.isdir(default_dir) else os.getcwd()
        xcassets_dir = filedialog.askdirectory(title="选择 Craftify Assets.xcassets 目录", initialdir=initial)
        if not xcassets_dir:
            return

        exporter = CraftifyExporter(xcassets_dir)
        all_it = self.filtered_items if self.filtered_items else list(self.renderer.all_items)
        total = len(all_it)

        def run_batch():
            for idx, it_name in enumerate(all_it):
                en_name = self.renderer.lang_en.get(
                    f"block.minecraft.{it_name}",
                    self.renderer.lang_en.get(f"item.minecraft.{it_name}", it_name.replace("_", " ").title())
                )
                img_3x = self.renderer.render_item(it_name, target_size=192)
                exporter.export_imageset(img_3x, en_name, preserve_existing=True)
                if idx % 10 == 0 or idx == total - 1:
                    pct = (idx + 1) / max(1, total) * 100.0
                    self.after(0, lambda p=pct, i=idx + 1, n=en_name: (
                        self.progress_var.set(p),
                        self.progress_label_var.set(f"正在导出至 iOS ({i}/{total}): {n}")
                    ))
            self.after(0, lambda: messagebox.showinfo(
                "导出完成",
                f"已成功将 {total} 个方块/物品图标导出至:\n{xcassets_dir}"
            ))

        threading.Thread(target=run_batch, daemon=True).start()

    def _on_export_recipe_package(self):
        if not self.renderer:
            messagebox.showwarning("提示", "请先加载 Minecraft .jar 文件！")
            return
        jar_p = self.renderer.jar_path
        scanner = JarScanner(jar_p)
        ver_name = scanner.version_name or "1.21.1"
        default_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../Craftify/RecipePacks"))
        initial_dir = default_dir if os.path.isdir(default_dir) else os.getcwd()
        out_file = filedialog.asksaveasfilename(
            title="打包导出 .recipe (自动包含物品栏渲染图标)",
            initialdir=initial_dir,
            initialfile=f"{ver_name}.recipe",
            defaultextension=".recipe",
            filetypes=[("Craftify Recipe Package", "*.recipe"), ("JSON", "*.json")],
        )
        if not out_file:
            return

        sz = int(self.size_var.get())

        def run_recipe_pkg():
            import sys as _sys
            scripts_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../../scripts"))
            if scripts_dir not in _sys.path:
                _sys.path.insert(0, scripts_dir)
            from extract_recipes import create_recipe_package

            def _prog(done: int, total: int, cur_key: str):
                pct = done / max(1, total) * 100.0
                self.after(0, lambda p=pct, d=done, t=total, k=cur_key: (
                    self.progress_var.set(p),
                    self.progress_label_var.set(f"正在打包 .recipe 图标 ({d}/{t}): {k}")
                ))

            pkg = create_recipe_package(
                jar_path=jar_p,
                output_path=out_file,
                version=ver_name,
                icon_size=sz,
                include_icons=True,
                include_all_items=True,
                renderer_instance=self.renderer,
                progress_callback=_prog,
            )
            r_cnt = pkg.get("recipe_count", 0)
            i_cnt = pkg.get("icon_count", 0)
            self.after(0, lambda: (
                self.progress_label_var.set(f"✅ .recipe 打包完成 ({r_cnt} 配方 + {i_cnt} 图标)"),
                messagebox.showinfo(
                    "打包成功",
                    f"已成功生成包含版本独立物品栏图标的 .recipe 包！\n\n"
                    f"• 版本: {ver_name}\n"
                    f"• 合成配方数: {r_cnt} 个\n"
                    f"• 内置渲染图标: {i_cnt} 个 ({sz}x{sz})\n"
                    f"• 保存路径: {out_file}"
                )
            ))

        threading.Thread(target=run_recipe_pkg, daemon=True).start()


def main():
    app = CraftifyStudioApp()
    app.mainloop()


if __name__ == "__main__":
    main()
