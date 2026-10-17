#!/usr/bin/env python3
"""
Craftify Asset Studio Launcher
Run this script to launch the macOS GUI application:
    python3 run.py
"""

import sys
import os

# Ensure current package is on sys.path
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

from craftify_asset_studio.gui.app import main

if __name__ == "__main__":
    main()
