#!/usr/bin/env bash
set -euo pipefail

# Builds the Linux bundle (if needed), builds the Flatpak, exports a distributable
# ostree repo, and generates progressor.flatpakrepo .
#
# The .flatpakrepo is designed to be hosted at the root of gh-pages.
# The actual repo contents are published under /repo to keep the site root clean.
#
# Usage:
#   ./flatpak/build-flatpak.sh
#
# After running:
#   mkdir -p gh-pages/repo
#   cp -r repo/* gh-pages/repo/
#   cp progressor.flatpakrepo gh-pages/
#   # then commit & push the gh-pages branch (or let CI do it)

echo "Building Progressor Flatpak repo..."

# 1. Ensure Flutter Linux bundle exists
BUNDLE_DIR="app/progressor/build/linux/x64/release/bundle"
if [ ! -x "$BUNDLE_DIR/progressor" ]; then
  echo "Building Flutter Linux release bundle..."
  (cd app/progressor && flutter build linux --release)
fi

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
cp flatpak/icon.png "$BUILD_CTX/"

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
#    We host the actual repo contents under /repo
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
echo
echo "To publish to GitHub Pages (gh-pages branch):"
echo "  mkdir -p gh-pages/repo"
echo "  cp -r $REPO_DIR/* gh-pages/repo/"
echo "  cp progressor.flatpakrepo gh-pages/"
echo "  (commit and push the gh-pages branch)"
echo
echo "Users can then run:"
echo "  flatpak remote-add --if-not-exists --user progressor https://isyourbrainfoss.github.io/Progressor/progressor.flatpakrepo"
echo "  flatpak install --user progressor com.isyourbrainfoss.Progressor"
echo
echo "For local testing of the generated repo (no network):"
echo "  flatpak --user remote-add --if-not-exists progressor-local \"file://$(pwd)/$REPO_DIR\""
echo "  flatpak install --user progressor-local com.isyourbrainfoss.Progressor"
