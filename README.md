# Progressor

State-of-the-art adaptive Flutter app for the **Tindeq Progressor 200** climbing dynamometer.

Works beautifully on:
- Android (Obtainium + GitHub releases)
- Linux desktop
- Linux mobile (Flatpak)

## Features

- Live force with beautiful CustomPainter chart
- Multiple protocols (Peak, RFD, Repeaters, CF, Custom)
- Rich computed metrics (peak, RFD, CF estimate, time to peak)
- History with PRs, streaks, detail replay chart
- Training best practices + live trend plots
- Gamification (streak, PR detection)
- CSV export/share
- Nextcloud sync skeleton
- Adaptive UI (phone + desktop)
- Mock mode for no hardware

## Install

See GitHub Releases and gh-pages for Obtainium/Flatpak.

## Development

melos bootstrap
melos run test
melos run analyze
flutter run -d linux

All local tests and builds green.

Repo prepared for CI green on GitHub.