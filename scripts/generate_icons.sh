#!/bin/bash
set -euo pipefail

# Generates all macOS app icon sizes from a single source image.
# Usage: ./scripts/generate_icons.sh <source_1024x1024.png>

SRC="${1:?Usage: $0 <source_image.png>}"
ICON_DIR="Repose/Assets.xcassets/AppIcon.appiconset"

declare -A ICONS=(
    ["icon_16x16@1x.png"]=16
    ["icon_16x16@2x.png"]=32
    ["icon_32x32@1x.png"]=32
    ["icon_32x32@2x.png"]=64
    ["icon_128x128@1x.png"]=128
    ["icon_128x128@2x.png"]=256
    ["icon_256x256@1x.png"]=256
    ["icon_256x256@2x.png"]=512
    ["icon_512x512@1x.png"]=512
    ["icon_512x512@2x.png"]=1024
)

for name in "${!ICONS[@]}"; do
    size="${ICONS[$name]}"
    sips --resampleWidth "$size" "$SRC" --out "$ICON_DIR/$name" 2>/dev/null
    echo "  $name (${size}x${size})"
done

echo "Done. All icons generated in $ICON_DIR"
