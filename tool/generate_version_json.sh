#!/usr/bin/env bash
# tool/generate_version_json.sh
# Generate gh-pages/version.json for Obtainium and gh-pages from a built APK.
# Follows Flowlog/Obtainium pattern.
#
# Usage examples:
#   ./tool/generate_version_json.sh \
#     --apk app/progressor/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
#     --out gh-pages/version.json
#
#   # with explicit url for release:
#   ./tool/generate_version_json.sh --apk ... --url https://.../app-arm64-v8a-release.apk

set -euo pipefail

APK=""
OUT="gh-pages/version.json"
URL="https://github.com/isyourbrainfoss/Progressor/releases"
VERSION=""
VERSION_CODE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apk) APK="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --url) URL="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --versionCode) VERSION_CODE="$2"; shift 2 ;;
    -h|--help)
      echo "tool/generate_version_json.sh --apk <path> [--out <path>] [--url <download-url>] [--version x.y.z] [--versionCode N]"
      exit 0
      ;;
    *) echo "Unknown arg $1"; exit 1 ;;
  esac
done

# Extract version from app/progressor/pubspec.yaml
PUBSPEC="app/progressor/pubspec.yaml"
if [[ -z "$VERSION" ]]; then
  VERSION=$(grep '^version:' "$PUBSPEC" | head -1 | sed 's/version: *//' | cut -d+ -f1 | tr -d ' ')
fi
if [[ -z "$VERSION" ]]; then VERSION="0.1.0"; fi

if [[ "$VERSION_CODE" -eq 0 ]]; then
  VC_LINE=$(grep '^version:' "$PUBSPEC" | head -1 | sed 's/version: *//')
  if [[ "$VC_LINE" == *+* ]]; then
    VERSION_CODE=$(echo "$VC_LINE" | cut -d+ -f2 | tr -d ' ' || echo 1)
  else
    # fallback semver to code e.g. 0.1.0 => 100
    MAJOR=$(echo "$VERSION" | cut -d. -f1)
    MINOR=$(echo "$VERSION" | cut -d. -f2)
    PATCH=$(echo "$VERSION" | cut -d. -f3)
    VERSION_CODE=$(( ${MAJOR:-0}*10000 + ${MINOR:-0}*100 + ${PATCH:-0} ))
  fi
fi

SHA="placeholder"
if [[ -n "$APK" && -f "$APK" ]]; then
  if command -v sha256sum >/dev/null; then
    SHA=$(sha256sum "$APK" | awk '{print $1}')
  elif command -v shasum >/dev/null; then
    SHA=$(shasum -a 256 "$APK" | awk '{print $1}')
  elif command -v openssl >/dev/null; then
    SHA=$(openssl dgst -sha256 "$APK" | awk '{print $2}')
  fi
  # If caller gave base URL, append conventional filename unless full url given
  if [[ "$URL" != *.apk ]]; then
    APK_BASENAME=$(basename "$APK")
    if [[ "$URL" == *"download/"* ]]; then
      URL="${URL%/}/$APK_BASENAME"
    else
      URL="${URL%/}/download/v${VERSION}/${APK_BASENAME}"
    fi
  fi
else
  if [[ -n "$APK" ]]; then
    echo "WARNING: APK $APK not found, sha remains placeholder" >&2
  fi
fi

mkdir -p "$(dirname "$OUT")"
cat > "$OUT" <<EOF
{
  "name": "Progressor",
  "version": "$VERSION",
  "versionCode": $VERSION_CODE,
  "sha256sum": "$SHA",
  "url": "$URL"
}
EOF

echo "Generated $OUT:"
cat "$OUT"
