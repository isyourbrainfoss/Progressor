#!/usr/bin/env bash
# Regenerate launcher / desktop icons from the SVG sources in branding/icon/.
# Requires: rsvg-convert (librsvg2-bin).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/branding/icon"
RES="$ROOT/app/progressor/android/app/src/main/res"
APP_ID="com.isyourbrainfoss.Progressor"
ICONS="$ROOT/flatpak/icons/hicolor"

# Legacy (pre-Android 8) launcher icon: 48dp.
declare -A LEGACY=([mdpi]=48 [hdpi]=72 [xhdpi]=96 [xxhdpi]=144 [xxxhdpi]=192)
# Adaptive icon layers: 108dp.
declare -A ADAPTIVE=([mdpi]=108 [hdpi]=162 [xhdpi]=216 [xxhdpi]=324 [xxxhdpi]=432)

for d in "${!LEGACY[@]}"; do
  mkdir -p "$RES/mipmap-$d"
  rsvg-convert -w "${LEGACY[$d]}" -h "${LEGACY[$d]}" "$SRC/icon.svg" -o "$RES/mipmap-$d/ic_launcher.png"
  rsvg-convert -w "${ADAPTIVE[$d]}" -h "${ADAPTIVE[$d]}" "$SRC/foreground.svg" -o "$RES/mipmap-$d/ic_launcher_foreground.png"
  rsvg-convert -w "${ADAPTIVE[$d]}" -h "${ADAPTIVE[$d]}" "$SRC/monochrome.svg" -o "$RES/mipmap-$d/ic_launcher_monochrome.png"
done

for s in 512 256 128 64; do
  mkdir -p "$ICONS/${s}x${s}/apps"
  rsvg-convert -w "$s" -h "$s" "$SRC/icon.svg" -o "$ICONS/${s}x${s}/apps/$APP_ID.png"
done
mkdir -p "$ICONS/scalable/apps"
cp "$SRC/icon.svg" "$ICONS/scalable/apps/$APP_ID.svg"

echo "Icons generated."
