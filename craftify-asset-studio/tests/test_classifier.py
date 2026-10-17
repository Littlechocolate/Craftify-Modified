"""Unit tests for Creative Inventory Classifier."""

import unittest
from craftify_asset_studio.classification import CreativeClassifier, CreativeTab

class TestCreativeClassifier(unittest.TestCase):
    def setUp(self):
        self.classifier = CreativeClassifier()

    def test_spawn_eggs(self):
        self.assertEqual(
            self.classifier.classify("creeper_spawn_egg"),
            CreativeTab.SPAWN_EGGS.value
        )
        self.assertEqual(
            self.classifier.classify("minecraft:allay_spawn_egg"),
            CreativeTab.SPAWN_EGGS.value
        )

    def test_colored_blocks(self):
        self.assertEqual(
            self.classifier.classify("red_wool"),
            CreativeTab.COLORED_BLOCKS.value
        )
        self.assertEqual(
            self.classifier.classify("blue_bed"),
            CreativeTab.COLORED_BLOCKS.value
        )
        self.assertEqual(
            self.classifier.classify("lime_concrete"),
            CreativeTab.COLORED_BLOCKS.value
        )
        self.assertEqual(
            self.classifier.classify("orange_stained_glass"),
            CreativeTab.COLORED_BLOCKS.value
        )

    def test_building_blocks(self):
        self.assertEqual(
            self.classifier.classify("stone"),
            CreativeTab.BUILDING_BLOCKS.value
        )
        self.assertEqual(
            self.classifier.classify("oak_stairs"),
            CreativeTab.BUILDING_BLOCKS.value
        )
        self.assertEqual(
            self.classifier.classify("stone_brick_slab"),
            CreativeTab.BUILDING_BLOCKS.value
        )
        self.assertEqual(
            self.classifier.classify("cobblestone_wall"),
            CreativeTab.BUILDING_BLOCKS.value
        )

    def test_natural_blocks(self):
        self.assertEqual(
            self.classifier.classify("grass_block"),
            CreativeTab.NATURAL_BLOCKS.value
        )
        self.assertEqual(
            self.classifier.classify("dirt"),
            CreativeTab.NATURAL_BLOCKS.value
        )
        self.assertEqual(
            self.classifier.classify("iron_ore"),
            CreativeTab.NATURAL_BLOCKS.value
        )
        self.assertEqual(
            self.classifier.classify("oak_log"),
            CreativeTab.NATURAL_BLOCKS.value
        )

    def test_functional_blocks(self):
        self.assertEqual(
            self.classifier.classify("crafting_table"),
            CreativeTab.FUNCTIONAL_BLOCKS.value
        )
        self.assertEqual(
            self.classifier.classify("furnace"),
            CreativeTab.FUNCTIONAL_BLOCKS.value
        )
        self.assertEqual(
            self.classifier.classify("chest"),
            CreativeTab.FUNCTIONAL_BLOCKS.value
        )
        self.assertEqual(
            self.classifier.classify("anvil"),
            CreativeTab.FUNCTIONAL_BLOCKS.value
        )

    def test_redstone_blocks(self):
        self.assertEqual(
            self.classifier.classify("redstone"),
            CreativeTab.REDSTONE_BLOCKS.value
        )
        self.assertEqual(
            self.classifier.classify("repeater"),
            CreativeTab.REDSTONE_BLOCKS.value
        )
        self.assertEqual(
            self.classifier.classify("piston"),
            CreativeTab.REDSTONE_BLOCKS.value
        )
        self.assertEqual(
            self.classifier.classify("observer"),
            CreativeTab.REDSTONE_BLOCKS.value
        )

    def test_combat_and_tools(self):
        self.assertEqual(
            self.classifier.classify("diamond_sword"),
            CreativeTab.COMBAT.value
        )
        self.assertEqual(
            self.classifier.classify("bow"),
            CreativeTab.COMBAT.value
        )
        self.assertEqual(
            self.classifier.classify("diamond_pickaxe"),
            CreativeTab.TOOLS_AND_UTILITIES.value
        )
        self.assertEqual(
            self.classifier.classify("fishing_rod"),
            CreativeTab.TOOLS_AND_UTILITIES.value
        )

    def test_food_and_ingredients(self):
        self.assertEqual(
            self.classifier.classify("apple"),
            CreativeTab.FOOD_AND_DRINKS.value
        )
        self.assertEqual(
            self.classifier.classify("cooked_beef"),
            CreativeTab.FOOD_AND_DRINKS.value
        )
        self.assertEqual(
            self.classifier.classify("iron_ingot"),
            CreativeTab.INGREDIENTS.value
        )
        self.assertEqual(
            self.classifier.classify("diamond"),
            CreativeTab.INGREDIENTS.value
        )

    def test_operator_utilities(self):
        self.assertEqual(
            self.classifier.classify("command_block"),
            CreativeTab.OPERATOR_UTILITIES.value
        )
        self.assertEqual(
            self.classifier.classify("barrier"),
            CreativeTab.OPERATOR_UTILITIES.value
        )

if __name__ == "__main__":
    unittest.main()
