#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="SakuraTranslator"
DISPLAY_NAME="Sakura Translator"
BUNDLE="$ROOT/dist/$APP_NAME.app"
EXEC="$BUNDLE/Contents/MacOS/$APP_NAME"
SRC="$ROOT/Sources"

echo "==> Clean dist"
rm -rf "$ROOT/dist"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

echo "==> Compile Sakura Translator"
swiftc \
  -parse-as-library \
  -O \
  -whole-module-optimization \
  -target arm64-apple-macos14.0 \
  -module-name SakuraTranslator \
  -framework SwiftUI \
  -framework AppKit \
  -framework Combine \
  -framework Foundation \
  -framework Carbon \
  -framework ApplicationServices \
  "$SRC"/*.swift \
  -o "$EXEC"

echo "==> Bundle metadata"
cp "$ROOT/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
  echo "    icon: AppIcon.icns"
fi

echo "==> Ad-hoc codesign"
codesign --force --deep --sign - "$BUNDLE"

echo "==> Verify"
file "$EXEC"
codesign -dv "$BUNDLE" 2>&1 | head -5
plutil -lint "$BUNDLE/Contents/Info.plist"
echo "Built: $BUNDLE ($DISPLAY_NAME)"
