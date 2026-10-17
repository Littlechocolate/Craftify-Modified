"""Item Gallery and Category Navigation View."""

import math
from typing import Callable, Dict, List, Optional
import customtkinter as ctk
from PIL import Image

from ..themes import (
    COLOR_PRIMARY,
    COLOR_PRIMARY_HOVER,
    DARK_CARD_BG,
    DARK_CARD_HOVER,
    FONT_FAMILY,
    LIGHT_CARD_BG,
    LIGHT_CARD_HOVER
)
from ...classification.creative_tabs import ALL_TABS, TAB_DISPLAY_NAMES_ZH, TAB_ICONS

ITEMS_PER_PAGE = 48

class GalleryView(ctk.CTkFrame):
    """Gallery browser with category navigation sidebar, search filtering, and paginated grid."""

    def __init__(
        self,
        master,
        on_item_selected: Callable[[dict], None],
        get_thumbnail: Callable[[dict], Optional[Image.Image]],
        **kwargs
    ):
        super().__init__(master, corner_radius=10, **kwargs)
        self.on_item_selected = on_item_selected
        self.get_thumbnail = get_thumbnail

        self.all_items: List[dict] = []
        self.filtered_items: List[dict] = []
        self.selected_category: str = "All"
        self.type_filter: str = "All"  # "All", "Blocks", "Items"
        self.search_query: str = ""
        self.current_page: int = 1
        self.category_buttons: Dict[str, ctk.CTkButton] = {}
        self.thumbnail_cache: Dict[str, ctk.CTkImage] = {}

        self._init_ui()

    def _init_ui(self):
        self.grid_rowconfigure(0, weight=1)
        self.grid_columnconfigure(1, weight=1)

        # ----------------- 1. Left Sidebar (Categories) -----------------
        self.sidebar_frame = ctk.CTkScrollableFrame(self, width=220, corner_radius=8)
        self.sidebar_frame.grid(row=0, column=0, sticky="nsew", padx=(10, 5), pady=10)

        sidebar_title = ctk.CTkLabel(
            self.sidebar_frame,
            text="Creative Tabs",
            font=ctk.CTkFont(family=FONT_FAMILY, size=14, weight="bold")
        )
        sidebar_title.pack(anchor="w", padx=8, pady=(4, 8))

        # "All Items" Button
        self.btn_all = ctk.CTkButton(
            self.sidebar_frame,
            text="📦 All Items (0)",
            anchor="w",
            height=32,
            fg_color=COLOR_PRIMARY,
            hover_color=COLOR_PRIMARY_HOVER,
            command=lambda: self._select_category("All")
        )
        self.btn_all.pack(fill="x", pady=2)
        self.category_buttons["All"] = self.btn_all

        # Individual Creative Tabs
        for cat in ALL_TABS:
            icon = TAB_ICONS.get(cat, "📦")
            cat_zh = TAB_DISPLAY_NAMES_ZH.get(cat, cat)
            label = f"{icon} {cat_zh}"
            btn = ctk.CTkButton(
                self.sidebar_frame,
                text=f"{label} (0)",
                anchor="w",
                height=32,
                fg_color="transparent",
                text_color=("gray20", "gray80"),
                hover_color=("gray85", "gray25"),
                command=lambda c=cat: self._select_category(c)
            )
            btn.pack(fill="x", pady=2)
            self.category_buttons[cat] = btn

        # ----------------- 2. Center Content Area -----------------
        self.content_frame = ctk.CTkFrame(self, corner_radius=8)
        self.content_frame.grid(row=0, column=1, sticky="nsew", padx=(5, 10), pady=10)
        self.content_frame.grid_rowconfigure(1, weight=1)
        self.content_frame.grid_columnconfigure(0, weight=1)

        # 2.1 Top Search & Filter Bar
        self.top_bar = ctk.CTkFrame(self.content_frame, height=44, fg_color="transparent")
        self.top_bar.grid(row=0, column=0, sticky="ew", padx=12, pady=(10, 6))
        self.top_bar.grid_columnconfigure(0, weight=1)

        self.search_entry = ctk.CTkEntry(
            self.top_bar,
            placeholder_text="Search items by ID or name (e.g. stone, 橡木, sword)...",
            height=32
        )
        self.search_entry.grid(row=0, column=0, sticky="ew", padx=(0, 10))
        self.search_entry.bind("<KeyRelease>", self._on_search_changed)

        self.type_segmented = ctk.CTkSegmentedButton(
            self.top_bar,
            values=["All", "Blocks", "Items"],
            command=self._on_type_filter_changed
        )
        self.type_segmented.set("All")
        self.type_segmented.grid(row=0, column=1)

        # 2.2 Scrollable Item Grid
        self.grid_scroll = ctk.CTkScrollableFrame(self.content_frame, corner_radius=6)
        self.grid_scroll.grid(row=1, column=0, sticky="nsew", padx=12, pady=6)
        # Configure 4 columns
        for c in range(4):
            self.grid_scroll.grid_columnconfigure(c, weight=1)

        # 2.3 Bottom Pagination Bar
        self.pagination_frame = ctk.CTkFrame(self.content_frame, height=40, fg_color="transparent")
        self.pagination_frame.grid(row=2, column=0, sticky="ew", padx=12, pady=(4, 10))

        self.prev_btn = ctk.CTkButton(
            self.pagination_frame,
            text="◀ Previous",
            width=90,
            height=28,
            command=self._prev_page
        )
        self.prev_btn.pack(side="left")

        self.page_label = ctk.CTkLabel(
            self.pagination_frame,
            text="Page 1 of 1 (0 items)",
            font=ctk.CTkFont(size=12)
        )
        self.page_label.pack(side="left", padx=16)

        self.next_btn = ctk.CTkButton(
            self.pagination_frame,
            text="Next ▶",
            width=90,
            height=28,
            command=self._next_page
        )
        self.next_btn.pack(side="left")

    def set_items(self, items: List[dict]):
        self.all_items = items
        self.thumbnail_cache.clear()
        self._update_category_counts()
        self._apply_filters()

    def _update_category_counts(self):
        counts = {cat: 0 for cat in ALL_TABS}
        for item in self.all_items:
            cat = item.get("category")
            if cat in counts:
                counts[cat] += 1

        self.btn_all.configure(text=f"📦 All Items ({len(self.all_items)})")
        for cat in ALL_TABS:
            btn = self.category_buttons.get(cat)
            if btn:
                icon = TAB_ICONS.get(cat, "📦")
                cat_zh = TAB_DISPLAY_NAMES_ZH.get(cat, cat)
                btn.configure(text=f"{icon} {cat_zh} ({counts.get(cat, 0)})")

    def _select_category(self, category: str):
        self.selected_category = category
        for cat, btn in self.category_buttons.items():
            if cat == category:
                btn.configure(
                    fg_color=COLOR_PRIMARY,
                    text_color="#FFFFFF"
                )
            else:
                btn.configure(
                    fg_color="transparent",
                    text_color=("gray20", "gray80")
                )
        self.current_page = 1
        self._apply_filters()

    def _on_search_changed(self, event=None):
        self.search_query = self.search_entry.get().strip().lower()
        self.current_page = 1
        self._apply_filters()

    def _on_type_filter_changed(self, choice: str):
        self.type_filter = choice
        self.current_page = 1
        self._apply_filters()

    def _apply_filters(self):
        filtered = []
        for item in self.all_items:
            # 1. Category
            if self.selected_category != "All" and item.get("category") != self.selected_category:
                continue

            # 2. Type
            is_block = item.get("is_block", True)
            if self.type_filter == "Blocks" and not is_block:
                continue
            if self.type_filter == "Items" and is_block:
                continue

            # 3. Search Query
            if self.search_query:
                item_id = item.get("id", "").lower()
                name_en = item.get("display_name", "").lower()
                name_zh = item.get("display_name_zh", "").lower()
                if self.search_query not in item_id and \
                   self.search_query not in name_en and \
                   self.search_query not in name_zh:
                    continue

            filtered.append(item)

        self.filtered_items = filtered
        self._render_page()

    def _render_page(self):
        # Clear existing cards in grid
        for child in self.grid_scroll.winfo_children():
            child.destroy()

        total_items = len(self.filtered_items)
        total_pages = max(1, math.ceil(total_items / ITEMS_PER_PAGE))
        self.current_page = max(1, min(self.current_page, total_pages))

        start_idx = (self.current_page - 1) * ITEMS_PER_PAGE
        end_idx = min(start_idx + ITEMS_PER_PAGE, total_items)
        page_items = self.filtered_items[start_idx:end_idx]

        # Update pagination controls
        self.page_label.configure(
            text=f"Page {self.current_page} of {total_pages} ({total_items} items)"
        )
        self.prev_btn.configure(state="normal" if self.current_page > 1 else "disabled")
        self.next_btn.configure(state="normal" if self.current_page < total_pages else "disabled")

        if not page_items:
            no_items_label = ctk.CTkLabel(
                self.grid_scroll,
                text="No items match your filter criteria.",
                font=ctk.CTkFont(size=14),
                text_color="gray50"
            )
            no_items_label.grid(row=0, column=0, columnspan=4, pady=60)
            return

        # Render cards in 4 columns
        cols = 4
        for idx, item in enumerate(page_items):
            row = idx // cols
            col = idx % cols
            card = self._create_item_card(item)
            card.grid(row=row, column=col, padx=4, pady=4, sticky="nsew")

    def _create_item_card(self, item: dict) -> ctk.CTkFrame:
        card = ctk.CTkFrame(
            self.grid_scroll,
            corner_radius=6,
            fg_color=("gray90", "gray20")
        )

        item_id = item.get("id", "")
        name = item.get("display_name", item_id)
        name_zh = item.get("display_name_zh", "")
        label_text = name_zh if name_zh and name_zh != name else name

        # Card button spanning the card
        btn = ctk.CTkButton(
            card,
            text=f"{label_text}\n{item_id}",
            font=ctk.CTkFont(size=11),
            fg_color="transparent",
            hover_color=("gray80", "gray28"),
            text_color=("gray15", "gray85"),
            compound="top",
            height=88,
            command=lambda it=item: self.on_item_selected(it)
        )

        # Get or render thumbnail (48x48)
        img_ctk = self._get_cached_ctk_image(item)
        if img_ctk:
            btn.configure(image=img_ctk)

        btn.pack(fill="both", expand=True, padx=2, pady=2)
        return card

    def _get_cached_ctk_image(self, item: dict) -> Optional[ctk.CTkImage]:
        item_id = item.get("id", "")
        if item_id in self.thumbnail_cache:
            return self.thumbnail_cache[item_id]

        pil_img = self.get_thumbnail(item)
        if pil_img:
            thumb = pil_img.resize((48, 48), Image.Resampling.LANCZOS)
            ctk_img = ctk.CTkImage(light_image=thumb, dark_image=thumb, size=(48, 48))
            self.thumbnail_cache[item_id] = ctk_img
            return ctk_img
        return None

    def _prev_page(self):
        if self.current_page > 1:
            self.current_page -= 1
            self._render_page()

    def _next_page(self):
        total_pages = math.ceil(len(self.filtered_items) / ITEMS_PER_PAGE)
        if self.current_page < total_pages:
            self.current_page += 1
            self._render_page()
