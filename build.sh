#!/usr/bin/env bash
set -euo pipefail

APP_NAME="QuickClip"
TEAM_ID="7GK92R38YK"

OUT_DIR="$HOME/dev/app"
ARCHIVE_PATH="$OUT_DIR/${APP_NAME}.xcarchive"
EXPORT_PLIST="$OUT_DIR/ExportOptions.plist"

PROJECT_PATH="./${APP_NAME}.xcodeproj"
# WORKSPACE_PATH="./${APP_NAME}.xcworkspace"

SCHEME="${APP_NAME}"
CONFIGURATION="Release"

mkdir -p "$OUT_DIR"

cat > "$EXPORT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
</dict>
</plist>
EOF

echo "==> Archive: ${ARCHIVE_PATH}"
if [[ -d "$PROJECT_PATH" ]]; then
  xcodebuild archive \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates
else
  echo "ERROR: Not found project: $PROJECT_PATH"
  echo "If you are using a workspace, edit the script to use -workspace."
  exit 1
fi

echo "==> Export to: ${OUT_DIR}"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$OUT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -allowProvisioningUpdates

echo
echo "✅ Done."
echo "Archive: $ARCHIVE_PATH"
echo "Exported artifacts in: $OUT_DIR"
echo "Look for: ${OUT_DIR}/${APP_NAME}.app"