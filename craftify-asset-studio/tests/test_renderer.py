"""Unit tests for IsometricRenderer and ItemRenderer."""

import unittest
import numpy as np
from craftify_asset_studio.extractor import AssetManager, JarScanner
from craftify_asset_studio.renderer import IsometricRenderer

class TestRenderer(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        local_jars = JarScanner.find_local_minecraft_jars()
        if not local_jars:
            raise unittest.SkipTest("No local Minecraft JAR found for integration test")
        cls.jar_path = local_jars[0]["path"]
        cls.manager = AssetManager(cls.jar_path)
        cls.manager.open()
        cls.renderer = IsometricRenderer(cls.manager)

    @classmethod
    def tearDownClass(cls):
        cls.manager.close()

    def test_render_block_crafting_table(self):
        img = self.renderer.render("crafting_table", target_size=128)
        self.assertIsNotNone(img)
        self.assertEqual(img.size, (128, 128))
        self.assertEqual(img.mode, "RGBA")

    def test_render_slabs(self):
        img = self.renderer.render("oak_slab", target_size=128)
        self.assertIsNotNone(img)
        self.assertEqual(img.size, (128, 128))
        self.assertIsNotNone(img.getbbox())

    def test_render_fence_and_gate(self):
        img_fence = self.renderer.render("oak_fence", target_size=128)
        self.assertIsNotNone(img_fence)
        self.assertEqual(img_fence.size, (128, 128))
        self.assertIsNotNone(img_fence.getbbox())

        img_gate = self.renderer.render("oak_fence_gate", target_size=128)
        self.assertIsNotNone(img_gate)
        self.assertEqual(img_gate.size, (128, 128))
        self.assertIsNotNone(img_gate.getbbox())

    def test_render_stairs_and_walls(self):
        img_stairs = self.renderer.render("oak_stairs", target_size=128)
        self.assertIsNotNone(img_stairs)
        self.assertEqual(img_stairs.size, (128, 128))
        self.assertIsNotNone(img_stairs.getbbox())

        img_wall = self.renderer.render("cobblestone_wall", target_size=128)
        self.assertIsNotNone(img_wall)
        self.assertEqual(img_wall.size, (128, 128))
        self.assertIsNotNone(img_wall.getbbox())

    def test_render_trapdoor(self):
        img_trapdoor = self.renderer.render("oak_trapdoor", target_size=128)
        self.assertIsNotNone(img_trapdoor)
        self.assertEqual(img_trapdoor.size, (128, 128))
        self.assertIsNotNone(img_trapdoor.getbbox())

    def test_render_items_and_shield(self):
        for it in ("iron_sword", "potion", "apple", "shield"):
            img = self.renderer.render(it, target_size=128)
            self.assertIsNotNone(img, f"Failed to render {it}")
            self.assertEqual(img.size, (128, 128))
            self.assertIsNotNone(img.getbbox(), f"{it} has empty bbox")

    def test_item_discovery_and_categorization(self):
        self.assertGreater(len(self.renderer.block_items), 500)
        self.assertGreater(len(self.renderer.non_block_items), 300)
        self.assertGreater(len(self.renderer.all_items), 900)
        self.assertTrue(self.renderer.is_block_item("oak_fence"))
        self.assertFalse(self.renderer.is_block_item("iron_sword"))

    def test_deduplication(self):
        # Non-inventory pure placed block states must NOT be in all_items
        ghost_blockstates = [
            "wall_torch", "redstone_wall_torch", "soul_wall_torch",
            "attached_melon_stem", "attached_pumpkin_stem", "potted_poppy",
            "acacia_wall_sign", "oak_wall_hanging_sign", "black_wall_banner",
            "dragon_wall_head", "carrots", "potatoes", "beetroots"
        ]
        for g in ghost_blockstates:
            self.assertNotIn(g, self.renderer.all_items, f"Ghost blockstate '{g}' should not be in all_items!")

        # Set relations: block_items + non_block_items = all_items, mutually disjoint
        self.assertEqual(set(self.renderer.block_items) & set(self.renderer.non_block_items), set())
        self.assertEqual(set(self.renderer.block_items) | set(self.renderer.non_block_items), set(self.renderer.all_items))

    def test_spawn_egg_standardized_rendering(self):
        # Creeper spawn egg must be rendered with official green & black tint (not flat gray)
        img_creeper = self.renderer.render("creeper_spawn_egg", target_size=64)
        self.assertIsNotNone(img_creeper)
        self.assertIsNotNone(img_creeper.getbbox())
        arr = np.array(img_creeper)
        vis = arr[arr[:, :, 3] > 100]
        mean_rgb = vis[:, :3].mean(axis=0)
        # Green channel should strongly dominate red and blue
        self.assertGreater(mean_rgb[1], mean_rgb[0] * 1.5)
        self.assertGreater(mean_rgb[1], mean_rgb[2] * 1.5)

        for egg in ("blaze_spawn_egg", "allay_spawn_egg", "warden_spawn_egg"):
            img = self.renderer.render(egg, target_size=64)
            self.assertIsNotNone(img)
            self.assertIsNotNone(img.getbbox(), f"{egg} has empty bbox")

    def test_spawn_egg_26_3_full_brightness(self):
        import os
        jar_26_3 = "/Users/shift8/Documents/Antigravity/mc/26.3-Fabric.jar"
        if not os.path.exists(jar_26_3):
            return
        r263 = IsometricRenderer(jar_26_3)
        img = r263.render("creeper_spawn_egg", target_size=64)
        vis = np.array(img)[np.array(img)[:, :, 3] > 100]
        mean_rgb = vis[:, :3].mean(axis=0)
        raw_tex = r263.load_texture("item/creeper_spawn_egg")
        vis_raw = raw_tex[raw_tex[:, :, 3] > 100]
        mean_raw = vis_raw[:, :3].mean(axis=0)
        self.assertAlmostEqual(float(mean_rgb[1]), float(mean_raw[1]), places=2)
        r263.close()

    def test_head_and_skull_rendering(self):
        # Test 7-part dragon head, 6-part piglin head, and other standard skulls
        heads = ("dragon_head", "piglin_head", "player_head", "skeleton_skull", "zombie_head", "creeper_head")
        for h in heads:
            img = self.renderer.render(h, target_size=64)
            self.assertIsNotNone(img, f"Failed to render {h}")
            self.assertEqual(img.size, (64, 64))
            self.assertIsNotNone(img.getbbox(), f"{h} has empty bbox")

    def test_banner_rendering(self):
        # Banners must render with 3D pole, bar, and tinted flag
        for b in ("red_banner", "white_banner", "blue_banner"):
            img = self.renderer.render(b, target_size=64)
            self.assertIsNotNone(img, f"Failed to render {b}")
            self.assertEqual(img.size, (64, 64))
            self.assertIsNotNone(img.getbbox(), f"{b} has empty bbox")

    def test_copper_golem_rendering(self):
        # Dummy entity texture to test 9-part Copper Golem model
        dummy_tex = np.full((64, 64, 4), [180, 100, 60, 255], dtype=np.float32)
        self.renderer.texture_cache[("entity/copper_golem/copper_golem", False)] = dummy_tex
        cbuf = np.zeros((64, 64, 4), dtype=np.float32)
        dbuf = np.full((64, 64), -1e9, dtype=np.float64)
        self.renderer._render_special_model(
            {"model": {"type": "minecraft:copper_golem_statue", "texture": "entity/copper_golem/copper_golem"}},
            cbuf, dbuf
        )
        self.assertTrue(np.any(cbuf[:, :, 3] > 0), "Copper golem buffer should have non-zero alpha")

    def test_recipe_package_icon_bundling(self):
        import os
        import sys
        scripts_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../scripts"))
        if scripts_dir not in sys.path:
            sys.path.insert(0, scripts_dir)
        from extract_recipes import render_icons_for_package

        sample_recipes = [{
            "id": 1,
            "name": "Oak Planks",
            "image": "Oak Planks",
            "ingredients": ["Oak Log"] + [""] * 8,
            "category": "Building Blocks",
            "imageremark": "Crafting Table",
            "output": 4,
        }]
        icons = render_icons_for_package(
            asset_jar_path=self.jar_path,
            recipes=sample_recipes,
            icon_size=64,
            include_all_items=False,
            renderer_instance=self.renderer,
        )
        self.assertIn("Oak Planks", icons)
        self.assertIn("Oak Log", icons)
        self.assertIn("Crafting Table", icons)

if __name__ == "__main__":
    unittest.main()
