#!/usr/bin/env bash
# Craftify Recipe Extractor Wrapper
# Usage: ./scripts/extract_recipes.sh [path/to/server.jar] [version]

set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( dirname "$DIR" )"

JAR_PATH="$1"
VERSION="$2"

if [ -z "$JAR_PATH" ]; then
    # Try finding server or client jar in default locations
    POSSIBLE_JAR=$(find "$HOME/Library/Application Support/minecraft/versions" -name "*.jar" 2>/dev/null | grep -v "fabric-loader" | head -n 1)
    if [ -n "$POSSIBLE_JAR" ]; then
        JAR_PATH="$POSSIBLE_JAR"
        echo "[Craftify Extractor] Auto-detected Minecraft Jar: $JAR_PATH"
    else
        echo "Usage: $0 <path_to_server_or_client.jar> [optional_version_name]"
        exit 1
    fi
fi

OUTPUT_FILE="$PROJECT_ROOT/Craftify/Resources/$(basename "$JAR_PATH" .jar).recipe"

echo "[Craftify Extractor] Running extraction on $JAR_PATH..."
python3 "$DIR/extract_recipes.py" --jar "$JAR_PATH" --output "$OUTPUT_FILE" ${VERSION:+--version "$VERSION"}

echo "[Craftify Extractor] Successfully generated: $OUTPUT_FILE"
