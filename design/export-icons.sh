#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "rsvg-convert not found. Install with: brew install librsvg" >&2
  exit 1
fi

OUT=../PlaceNotes/Assets.xcassets/AppIcon.appiconset

rsvg-convert -w 1024 -h 1024 AppIcon.svg      -o "$OUT/AppIcon.png"
rsvg-convert -w 1024 -h 1024 AppIcon-Dark.svg -o "$OUT/AppIcon-Dark.png"

echo "Exported AppIcon.png and AppIcon-Dark.png to $OUT"
