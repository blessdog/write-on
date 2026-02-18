#!/bin/bash
set -euo pipefail

# create-dmg.sh — Build a drag-to-Applications DMG for Write On
#
# Usage: ./scripts/create-dmg.sh [path-to-app-bundle]
# Default app path: /Applications/Write On.app

APP_PATH="${1:-/Applications/Write On.app}"
DMG_NAME="WriteOn"
VOLUME_NAME="Write On"
DMG_SIZE="10m"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DMG="${PROJECT_DIR}/${DMG_NAME}.dmg"
TEMP_DMG="${PROJECT_DIR}/${DMG_NAME}-temp.dmg"
BG_IMAGE="${SCRIPT_DIR}/dmg-background.png"

# Verify app exists
if [ ! -d "$APP_PATH" ]; then
    echo "Error: App not found at '$APP_PATH'"
    echo "Usage: $0 [path-to-app-bundle]"
    exit 1
fi

echo "Creating DMG for: $APP_PATH"

# Clean up any previous temp files
rm -f "$TEMP_DMG" "$OUTPUT_DMG"

# Create writable DMG
hdiutil create -size "$DMG_SIZE" -fs HFS+ -volname "$VOLUME_NAME" "$TEMP_DMG"

# Mount it
MOUNT_DIR=$(hdiutil attach "$TEMP_DMG" -readwrite -noverify | grep "/Volumes/" | sed 's/.*\/Volumes/\/Volumes/')
echo "Mounted at: $MOUNT_DIR"

# Copy app bundle
cp -R "$APP_PATH" "$MOUNT_DIR/"

# Create Applications symlink
ln -s /Applications "$MOUNT_DIR/Applications"

# Copy background image if it exists
if [ -f "$BG_IMAGE" ]; then
    mkdir -p "$MOUNT_DIR/.background"
    cp "$BG_IMAGE" "$MOUNT_DIR/.background/background.png"
fi

# Set Finder window layout via AppleScript
echo "Configuring Finder window layout..."
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 740, 580}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 96
        if exists file ".background:background.png" then
            set background picture of theViewOptions to file ".background:background.png"
        end if
        set position of item "Write On.app" of container window to {160, 240}
        set position of item "Applications" of container window to {480, 240}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# Make sure writes are flushed
sync

# Unmount
hdiutil detach "$MOUNT_DIR"

# Convert to compressed read-only DMG
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT_DMG"

# Clean up temp DMG
rm -f "$TEMP_DMG"

echo ""
echo "DMG created: $OUTPUT_DMG"
echo "Size: $(du -h "$OUTPUT_DMG" | cut -f1)"
