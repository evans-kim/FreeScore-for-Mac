#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
version="$(tr -d '[:space:]' < VERSION)"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION must contain a semantic version such as 0.5.0" >&2
  exit 1
fi
swift build -c release --triple arm64-apple-macosx14.0
swift build -c release --triple x86_64-apple-macosx14.0
mkdir -p build/Assets
swift Scripts/generate-icon.swift build/Assets/AppIcon.png
iconset_dir="build/AppIcon.iconset"
rm -rf "$iconset_dir"
mkdir -p "$iconset_dir"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" build/Assets/AppIcon.png --out "$iconset_dir/icon_${size}x${size}.png" >/dev/null
done
cp "$iconset_dir/icon_32x32.png" "$iconset_dir/icon_16x16@2x.png"
sips -z 64 64 build/Assets/AppIcon.png --out "$iconset_dir/icon_32x32@2x.png" >/dev/null
cp "$iconset_dir/icon_256x256.png" "$iconset_dir/icon_128x128@2x.png"
cp "$iconset_dir/icon_512x512.png" "$iconset_dir/icon_256x256@2x.png"
cp build/Assets/AppIcon.png "$iconset_dir/icon_512x512@2x.png"
iconutil -c icns "$iconset_dir" -o build/Assets/AppIcon.icns
app_dir="build/FreeScore for Mac.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
lipo -create \
  .build/arm64-apple-macosx/release/FreeScore \
  .build/x86_64-apple-macosx/release/FreeScore \
  -output "$app_dir/Contents/MacOS/FreeScore"
cp build/Assets/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
cat > "$app_dir/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>FreeScore for Mac</string>
  <key>CFBundleDisplayName</key><string>FreeScore for Mac</string>
  <key>CFBundleIdentifier</key><string>com.evanskim.midiscore</string>
  <key>CFBundleExecutable</key><string>FreeScore</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>UTExportedTypeDeclarations</key><array><dict>
    <key>UTTypeIdentifier</key><string>com.evanskim.midiscore.project</string>
    <key>UTTypeDescription</key><string>FreeScore Project</string>
    <key>UTTypeConformsTo</key><array><string>public.json</string></array>
    <key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>mscore</string></array></dict>
  </dict></array>
</dict></plist>
PLIST
echo "$app_dir"
