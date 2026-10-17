"""Unit tests for ModelResolver."""

import os
import unittest
from craftify_asset_studio.extractor import AssetManager, JarScanner
from craftify_asset_studio.model import ModelResolver

class TestModelResolver(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        local_jars = JarScanner.find_local_minecraft_jars()
        if not local_jars:
            raise unittest.SkipTest("No local Minecraft JAR found for integration test")
        cls.jar_path = local_jars[0]["path"]
        cls.manager = AssetManager(cls.jar_path)
        cls.manager.open()
        cls.resolver = ModelResolver(cls.manager)

    @classmethod
    def tearDownClass(cls):
        cls.manager.close()

    def test_resolve_cube_block(self):
        resolved = self.resolver.resolve("block/crafting_table")
        self.assertIsNotNone(resolved)
        self.assertIsNotNone(resolved.elements)
        self.assertGreater(len(resolved.elements), 0)
        self.assertIn("up", resolved.elements[0].faces)
        self.assertIn("up", resolved.textures)
        self.assertFalse(resolved.is_2d_item)

    def test_resolve_stair_block(self):
        resolved = self.resolver.resolve("block/oak_stairs")
        self.assertIsNotNone(resolved)
        self.assertIsNotNone(resolved.elements)
        self.assertEqual(len(resolved.elements), 2)  # Stairs have 2 cuboid elements

    def test_resolve_2d_item(self):
        resolved = self.resolver.resolve("item/apple")
        self.assertIsNotNone(resolved)
        self.assertTrue(resolved.is_2d_item)
        self.assertIn("item/apple", resolved.layers_2d)

if __name__ == "__main__":
    unittest.main()
