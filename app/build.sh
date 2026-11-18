#!/bin/zsh
# Baut SSD-Backup.app (Menüleisten-App) und installiert sie nach ~/Applications.
# Benötigt nur die Xcode Command Line Tools (xcode-select --install).
#   build.sh                bauen + installieren
#   build.sh --no-install   nur bauen
#   build.sh --universal    für Apple Silicon und Intel (für Releases)
set -e
HERE="${0:A:h}"
BUILD="$HERE/build"
APP="$BUILD/SSD-Backup.app"
DEST="$HOME/Applications"
INSTALL=1; UNIVERSAL=0
for a in "$@"; do case $a in --no-install) INSTALL=0 ;; --universal) UNIVERSAL=1 ;; esac; done
VERSION=$(sed -n 's/^SSD_BACKUP_VERSION="\(.*\)".*/\1/p' "$HERE/../ssd-backup")
VERSION=${VERSION:-0.0.0}

rm -rf "$BUILD"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if (( UNIVERSAL )); then archs=(arm64 x86_64); else archs=($(uname -m)); fi
for arch in $archs; do
  swiftc -O -parse-as-library -swift-version 5 \
    -target "$arch-apple-macos15.0" \
    -o "$BUILD/SSD-Backup-$arch" "$HERE/SSDBackup.swift"
done
lipo -create "$BUILD"/SSD-Backup-*(N) -output "$APP/Contents/MacOS/SSD-Backup"
rm -f "$BUILD"/SSD-Backup-*(N)

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>             <string>SSD-Backup</string>
  <key>CFBundleDisplayName</key>      <string>SSD-Backup</string>
  <key>CFBundleIdentifier</key>       <string>com.user.ssd-backup-app</string>
  <key>CFBundleExecutable</key>       <string>SSD-Backup</string>
  <key>CFBundlePackageType</key>      <string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key>          <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>   <string>15.0</string>
  <key>LSUIElement</key>              <true/>
  <key>NSHighResolutionCapable</key>  <true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
print "Gebaut: $APP (Version $VERSION, ${(j:+:)archs})"

if (( INSTALL )); then
  mkdir -p "$DEST"
  pkill -x SSD-Backup 2>/dev/null && sleep 1 || true
  rm -rf "$DEST/SSD-Backup.app"
  cp -R "$APP" "$DEST/"
  print "Installiert: $DEST/SSD-Backup.app"
  open "$DEST/SSD-Backup.app"
fi
