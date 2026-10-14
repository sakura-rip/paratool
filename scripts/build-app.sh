#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
version="${APP_VERSION:-0.1.0}"
build_number="${APP_BUILD:-1}"
if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' || ! "$build_number" =~ '^[0-9]+$' ]]; then
  print -u2 'APP_VERSION must be X.Y.Z and APP_BUILD must be an integer.'
  exit 1
fi
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
swift build -c release --disable-sandbox --cache-path "$PWD/.build/cache" --config-path "$PWD/.build/config" --security-path "$PWD/.build/security"
app="$PWD/dist/Paratool.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/Paratool "$app/Contents/MacOS/Paratool"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Paratool</string>
<key>CFBundleDisplayName</key><string>Paratool</string>
<key>CFBundleIdentifier</key><string>app.paratool.mac</string>
<key>CFBundleExecutable</key><string>Paratool</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSDesktopFolderUsageDescription</key><string>撮影したスクリーンショットを左下に表示するため、保存先を読み取ります。</string>
<key>NSDocumentsFolderUsageDescription</key><string>スクリーンショットの保存先に指定されたフォルダを読み取ります。</string>
<key>NSDownloadsFolderUsageDescription</key><string>スクリーンショットの保存先に指定されたフォルダを読み取ります。</string>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
plutil -lint "$app/Contents/Info.plist"
printf 'Built: %s\n' "$app"
