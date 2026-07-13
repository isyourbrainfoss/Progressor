#!/usr/bin/env bash
set -euo pipefail
ARCH=${1:-$(uname -m)}
echo "Building Flatpak for $ARCH"

# Requires flatpak-builder and GNOME runtime installed
# This is a skeleton; full build would bundle the linux release.

flatpak-builder --user --install --force-clean build-dir com.isyourbrainfoss.Progressor.yml || echo "Install flatpak-builder and run from correct context."
echo "See Flowlog flatpak/ for full reference implementation."
