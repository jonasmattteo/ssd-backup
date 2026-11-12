#!/bin/zsh
# Baut SSD-Backup.app (Menüleisten-App) und installiert sie nach ~/Applications.
# Benötigt nur die Xcode Command Line Tools (xcode-select --install).
set -e
HERE="${0:A:h}"
BUILD="$HERE/build"
APP="$BUILD/SSD-Backup.app"
DEST="$HOME/Applications"

rm -rf "$BUILD"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -parse-as-library -swift-version 5 \
  -target "$(uname -m)-apple-macos15.0" \
  -o "$APP/Contents/MacOS/SSD-Backup" "$HERE/SSDBackup.swift"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>             <string>SSD-Backup</string>
  <key>CFBundleDisplayName</key>      <string>SSD-Backup</string>
  <key>CFBundleIdentifier</key>       <string>com.user.ssd-backup-app</string>
  <key>CFBundleExecutable</key>       <string>SSD-Backup</string>
  <key>CFBundlePackageType</key>      <string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key>          <string>1</string>
  <key>LSMinimumSystemVersion</key>   <string>15.0</string>
  <key>LSUIElement</key>              <true/>
  <key>NSHighResolutionCapable</key>  <true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
print "Gebaut: $APP"

if [[ "$1" != "--no-install" ]]; then
  mkdir -p "$DEST"
  pkill -x SSD-Backup 2>/dev/null && sleep 1 || true
  rm -rf "$DEST/SSD-Backup.app"
  cp -R "$APP" "$DEST/"
  print "Installiert: $DEST/SSD-Backup.app"
  open "$DEST/SSD-Backup.app"
fi
