#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "rsvg-convert not found. Install with: brew install librsvg" >&2
  exit 1
fi

ASSETS=../PlaceNotes/Assets.xcassets

rsvg-convert -w 1024 -h 1024 AppIcon.svg         -o "$ASSETS/AppIcon.appiconset/AppIcon.png"
rsvg-convert -w 1024 -h 1024 AppIcon-Night.svg   -o "$ASSETS/AppIcon-Night.appiconset/AppIcon-Night.png"
rsvg-convert -w 1024 -h 1024 AppIcon-Outdoor.svg -o "$ASSETS/AppIcon-Outdoor.appiconset/AppIcon-Outdoor.png"

rsvg-convert -w 256 -h 256 AppIcon.svg         -o "$ASSETS/AppIconPreview-Day.imageset/AppIconPreview-Day.png"
rsvg-convert -w 256 -h 256 AppIcon-Night.svg   -o "$ASSETS/AppIconPreview-Night.imageset/AppIconPreview-Night.png"
rsvg-convert -w 256 -h 256 AppIcon-Outdoor.svg -o "$ASSETS/AppIconPreview-Outdoor.imageset/AppIconPreview-Outdoor.png"

echo "Exported Day / Night / Outdoor icons (1024 appiconsets + 256 previews)"
