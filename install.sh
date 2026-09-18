#!/bin/zsh
# Install Sakura Translator to /Applications (removes older builds)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/dist/SakuraTranslator.app"
DST="/Applications/Sakura Translator.app"

pkill -f "SakuraTranslator" 2>/dev/null || true
pkill -f "Sakura Translator" 2>/dev/null || true
pkill -f "GlassTranslator" 2>/dev/null || true
pkill -f "Glass Translate" 2>/dev/null || true
sleep 1

rm -rf "$DST" "/Applications/Glass Translate.app" 2>/dev/null || true
ditto "$SRC" "$DST"
codesign --force --deep --sign - "$DST" 2>/dev/null || true
open "$DST"
echo "Installed: $DST"
