#!/usr/bin/env bash
set -euo pipefail

# Builds the Flatpak from an existing Flutter Linux release bundle, exports a
# distributable ostree repo, and generates progressor.flatpakrepo.
#
# Expects the release bundle at:
#   app/progressor/build/linux/x64/release/bundle/progressor
#
# If the binary is missing and `flutter` is on PATH, builds it first.
# CI should always provide the prebuilt bundle artifact (no flutter needed).

echo "Building Progressor Flatpak repo..."

BUNDLE_DIR="app/progressor/build/linux/x64/release/bundle"
if [ ! -f "$BUNDLE_DIR/progressor" ]; then
  if command -v flutter >/dev/null 2>&1; then
    echo "Building Flutter Linux release bundle..."
    (cd app/progressor && flutter build linux --release)
  else
    echo "ERROR: Linux bundle missing at $BUNDLE_DIR/progressor" >&2
    echo "and flutter is not available. Build Linux first or restore the CI artifact." >&2
    exit 1
  fi
fi

# Artifact downloads often drop the executable bit.
chmod +x "$BUNDLE_DIR/progressor" || true

# 2. Prepare a self-contained build context dir that contains the yml + app files
#    (the manifest uses sources: {type: dir, path: .})
BUILD_CTX="flatpak/build-context"
rm -rf "$BUILD_CTX"
mkdir -p "$BUILD_CTX"

cp "$BUNDLE_DIR/progressor" "$BUILD_CTX/"
mkdir -p "$BUILD_CTX/bundle"
cp -r "$BUNDLE_DIR/data" "$BUILD_CTX/bundle/" 2>/dev/null || true
cp -r "$BUNDLE_DIR/lib" "$BUILD_CTX/bundle/" 2>/dev/null || true

# Copy the manifest and the metadata files the manifest installs
cp flatpak/com.isyourbrainfoss.Progressor.yml "$BUILD_CTX/"
cp flatpak/com.isyourbrainfoss.Progressor.desktop "$BUILD_CTX/"
cp flatpak/com.isyourbrainfoss.Progressor.metainfo.xml "$BUILD_CTX/"
cp -r flatpak/icons "$BUILD_CTX/icons"

# 3. Build the Flatpak and export to an ostree repo
REPO_DIR="repo"
rm -rf "$REPO_DIR" flatpak-build

echo "Running flatpak-builder (this may take a while the first time)..."
( cd "$BUILD_CTX" && \
  flatpak-builder --force-clean \
    --repo="../../$REPO_DIR" \
    ../../flatpak-build \
    com.isyourbrainfoss.Progressor.yml )

# 4. Generate the .flatpakrepo file (hosted at gh-pages root)
cat > progressor.flatpakrepo << 'EOF'
[Flatpak Repo]
Title=Progressor
Url=https://isyourbrainfoss.github.io/Progressor/repo
Homepage=https://github.com/isyourbrainfoss/Progressor
EOF

echo
echo "Flatpak repo generated."
echo "  Repo contents : $REPO_DIR/"
echo "  .flatpakrepo  : progressor.flatpakrepo"
