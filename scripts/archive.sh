#!/usr/bin/env bash
# Archive a Release build of PlaceNotes and export an IPA ready for upload to
# App Store Connect. Run from the repo root:
#
#   scripts/archive.sh                # bump build number, archive, export
#   scripts/archive.sh --no-bump      # archive without bumping CURRENT_PROJECT_VERSION
#   scripts/archive.sh --upload       # also upload IPA via xcrun altool (needs API key env vars)
#
# Requires: Xcode command-line tools, xcodegen, an App Store distribution
# signing identity in the login keychain. For --upload, set:
#   APP_STORE_CONNECT_API_KEY_ID
#   APP_STORE_CONNECT_API_ISSUER_ID
# and place the .p8 key at ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

BUILD_DIR="$ROOT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/PlaceNotes.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
EXPORT_OPTIONS="$SCRIPT_DIR/ExportOptions.plist"
SCHEME="PlaceNotes-Release"

bump_build=true
upload=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-bump) bump_build=false; shift ;;
        --upload) upload=true; shift ;;
        -h|--help)
            sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1 ;;
    esac
done

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen not found. Install with: brew install xcodegen" >&2
    exit 1
fi

if $bump_build; then
    current=$(awk '/CURRENT_PROJECT_VERSION:/ {print $2; exit}' project.yml)
    if [[ -z "$current" ]]; then
        echo "Could not read CURRENT_PROJECT_VERSION from project.yml" >&2
        exit 1
    fi
    next=$((current + 1))
    echo "==> Bumping CURRENT_PROJECT_VERSION: $current -> $next"
    sed -i '' -E "s/(CURRENT_PROJECT_VERSION: ).*/\\1$next/" project.yml
fi

marketing=$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)
build=$(awk '/CURRENT_PROJECT_VERSION:/ {print $2; exit}' project.yml)
echo "==> Building $marketing ($build)"

echo "==> xcodegen generate"
xcodegen generate

echo "==> Resetting build directory"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving Release"
xcodebuild \
    -project PlaceNotes.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    archive

echo "==> Exporting IPA"
xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -allowProvisioningUpdates

ipa=$(ls "$EXPORT_PATH"/*.ipa 2>/dev/null | head -1)
if [[ -z "$ipa" ]]; then
    echo "No .ipa produced in $EXPORT_PATH" >&2
    exit 1
fi
echo "==> IPA: $ipa"

if $upload; then
    : "${APP_STORE_CONNECT_API_KEY_ID:?Set APP_STORE_CONNECT_API_KEY_ID}"
    : "${APP_STORE_CONNECT_API_ISSUER_ID:?Set APP_STORE_CONNECT_API_ISSUER_ID}"
    echo "==> Uploading to App Store Connect"
    xcrun altool --upload-app \
        --type ios \
        --file "$ipa" \
        --apiKey "$APP_STORE_CONNECT_API_KEY_ID" \
        --apiIssuer "$APP_STORE_CONNECT_API_ISSUER_ID"
    echo "==> Upload submitted. Check App Store Connect for processing status."
fi

echo "==> Done."
