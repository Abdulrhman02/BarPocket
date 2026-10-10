#!/bin/zsh
set -euo pipefail

source_dir="${0:A:h}"
app_dir="${source_dir}/dist/BarPocket.app"
target_arch="${TARGET_ARCH:-$(uname -m)}"
signing_identity="${CODESIGN_IDENTITY:--}"

if [[ "$target_arch" != "arm64" && "$target_arch" != "x86_64" ]]; then
  print -u2 "Unsupported architecture: $target_arch"
  exit 1
fi

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
module_cache_dir="$(mktemp -d "${source_dir}/dist/.module-cache.XXXXXX")"
trap 'rm -r "$module_cache_dir"' EXIT
/usr/bin/xcrun swiftc -O -swift-version 5 -target "${target_arch}-apple-macosx13.0" \
  -module-cache-path "$module_cache_dir" \
  -framework AppKit -framework ApplicationServices -framework ServiceManagement \
  "$source_dir/main.swift" "$source_dir/SingleInstance.swift" -o "$app_dir/Contents/MacOS/BarPocket"
cp "$source_dir/BarPocket.icns" "$app_dir/Contents/Resources/BarPocket.icns"
cp "$source_dir/PocketLight.png" "$app_dir/Contents/Resources/PocketLight.png"
cp "$source_dir/PocketDark.png" "$app_dir/Contents/Resources/PocketDark.png"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>BarPocket</string>
<key>CFBundleDisplayName</key><string>BarPocket</string>
<key>CFBundleIdentifier</key><string>com.abdul.barpocket</string>
<key>CFBundleExecutable</key><string>BarPocket</string>
<key>CFBundleIconFile</key><string>BarPocket</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.7.1</string>
<key>CFBundleVersion</key><string>8</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign "$signing_identity" "$app_dir"
print "$app_dir"
