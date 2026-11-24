#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PROJECT_DIR/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/YOMO.app"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PROJECT_DIR/Resources/Info.plist" 2>/dev/null || echo "1.0.0")"
DMG_NAME="YOMO-v${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
SRC_ZIP_NAME="YOMO-v${VERSION}-source.zip"
SRC_ZIP_PATH="$DIST_DIR/$SRC_ZIP_NAME"
CHECKSUM_PATH="$DIST_DIR/SHA256SUMS.txt"

STAGE_ROOT="$REPO_ROOT/tmp/yomo-release-stage-$$"
DMG_STAGE="$STAGE_ROOT/dmg"
SRC_STAGE="$STAGE_ROOT/YOMO-v${VERSION}"

cleanup() {
    rm -rf "$STAGE_ROOT"
}
trap cleanup EXIT

# 1. Build YOMO.app
"$SCRIPT_DIR/build-app.sh"

# 2. Build DMG installer (YOMO.app + /Applications symlink)
echo "💿 Creating $DMG_NAME..."
rm -f "$DIST_DIR"/YOMO-v*.dmg "$DIST_DIR"/YOMO-v*-source.zip
mkdir -p "$DMG_STAGE"
cp -R "$APP_BUNDLE" "$DMG_STAGE/YOMO.app"
ln -s /Applications "$DMG_STAGE/Applications"

rm -f "$DMG_PATH"
hdiutil create \
    -volname "YOMO ${VERSION}" \
    -srcfolder "$DMG_STAGE" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH" >/dev/null

# 3. Build clean Source ZIP (excluding .build, dist, .DS_Store, .git)
echo "🗜️  Creating $SRC_ZIP_NAME..."
mkdir -p "$SRC_STAGE"
for item in Package.swift README.md README_EN.md LICENSE .gitignore Resources Sources scripts docs; do
    if [ -e "$PROJECT_DIR/$item" ]; then
        cp -R "$PROJECT_DIR/$item" "$SRC_STAGE/"
    fi
done
find "$SRC_STAGE" -name ".DS_Store" -delete

rm -f "$SRC_ZIP_PATH"
(
    cd "$STAGE_ROOT"
    zip -r -q "$SRC_ZIP_PATH" "YOMO-v${VERSION}"
)

# 4. Generate SHA-256 checksums
echo "🔐 Generating SHA256SUMS.txt..."
(
    cd "$DIST_DIR"
    shasum -a 256 "$DMG_NAME" "$SRC_ZIP_NAME" > "$CHECKSUM_PATH"
)

echo ""
echo "✅ Release artifacts ready in $DIST_DIR:"
ls -lh "$DMG_PATH" "$SRC_ZIP_PATH" "$CHECKSUM_PATH"
cat "$CHECKSUM_PATH"
