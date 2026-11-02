#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -f Sources/LinguaMac/Resources/AppIcon.png ] || [ scripts/generate-icon.swift -nt Sources/LinguaMac/Resources/AppIcon.png ]; then
  swift scripts/generate-icon.swift
fi
xcodebuild -scheme LinguaMac -destination 'platform=macOS' -derivedDataPath build/DerivedData \
  -clonedSourcePackagesDirPath build/SourcePackages -configuration Release -skipMacroValidation build CODE_SIGNING_ALLOWED=NO
products="$PWD/build/DerivedData/Build/Products/Release"
app="$PWD/build/Lingua.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
python3 scripts/bundle-default-model.py "$app/Contents/Resources"
cp "$products/LinguaMac" "$app/Contents/MacOS/LinguaMac.new"
mv "$app/Contents/MacOS/LinguaMac.new" "$app/Contents/MacOS/LinguaMac"
# MLX's Cmlx resource bundle contains the compiled Metal library.
while IFS= read -r -d '' bundle; do
  ditto "$bundle" "$app/Contents/Resources/$(basename "$bundle")"
done < <(find "$products" -maxdepth 1 -type d -name '*.bundle' -print0)
if ! find "$app/Contents/Resources" -name '*.metallib' -print -quit | rg -q .; then
  echo "Missing MLX Metal library in packaged resources" >&2
  exit 1
fi
iconset="$PWD/build/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Sources/LinguaMac/Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" Sources/LinguaMac/Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LinguaMac</string>
<key>CFBundleIdentifier</key><string>app.lingua.mac</string>
<key>CFBundleName</key><string>Lingua</string>
<key>CFBundleLocalizations</key><array><string>zh-Hans</string><string>en</string><string>ja</string><string>ko</string></array>
<key>CFBundleDisplayName</key><string>Lingua</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$app"
# Notify Finder that the existing application package changed, including bundled weights.
touch "$app"
echo "Built: $app"
