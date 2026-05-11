# App Icon Source

Source-of-truth SVGs for the iOS app icon. The shipped PNGs in
`PlaceNotes/Assets.xcassets/AppIcon.appiconset/` are exported from these.

## Files

- `AppIcon.svg` — Light variant (mid-day city)
- `AppIcon-Dark.svg` — Dark variant (night city, iOS 18 dark appearance)
- `export-icons.sh` — Re-export both PNGs at 1024×1024

## Re-exporting

Prerequisite (one-time):

    brew install librsvg

Then:

    ./design/export-icons.sh

The script overwrites `AppIcon.png` and `AppIcon-Dark.png` in the
asset catalog. Re-build the Xcode project to pick up changes.
