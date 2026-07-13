# Progressor

State-of-the-art adaptive Flutter app for the **Tindeq Progressor 200** climbing dynamometer.

Works beautifully on:
- Android (Obtainium + GitHub releases)
- Linux desktop
- Linux mobile (Flatpak)

## Features (implemented + planned)

- **Live measurement**: Big readable force (kg), smooth live CustomPainter chart, tare, start/stop for Peak / RFD / Repeaters / Custom.
- **Multiple protocols** and guided best-practice training suggestions with goals.
- **Pretty plots** and history with PRs.
- **Gamification**: Streaks, strength index, achievements.
- **Nextcloud sync** (WebDAV) like Flowlog for phone ↔ desktop.
- **Mock / simulator mode** — works without hardware.
- **Export / import**.

Inspired by the excellent [Flowlog](https://github.com/isyourbrainfoss/Flowlog) architecture and slice-based development.

## Install

### Android (Obtainium recommended)

Install Obtainium from F-Droid or its releases, then add this app using the version.json for updates and APKs:

```
https://raw.githubusercontent.com/isyourbrainfoss/Progressor/gh-pages/version.json
```

One-tap add (if Obtainium installed):

```
https://apps.obtainium.imranr.dev/redirect.html?r=obtainium://add/https://raw.githubusercontent.com/isyourbrainfoss/Progressor/gh-pages/version.json
```

**Troubleshooting Obtainium:**
- If "App not installed" or signature error: uninstall any debug build first (`adb uninstall com.isyourbrainfoss.progressor` or via settings).
- Use the gh-pages version.json (not direct release URLs) for reliability on mobile.

### Linux (Flatpak)

```bash
flatpak remote-add --if-not-exists --user progressor https://isyourbrainfoss.github.io/Progressor/progressor.flatpakrepo
flatpak install --user progressor com.isyourbrainfoss.Progressor
```

Updates:

```bash
flatpak update --user com.isyourbrainfoss.Progressor
```

The GNOME runtime will be pulled from Flathub as needed.

To build locally (for development):

```bash
./flatpak/build-flatpak.sh
```

(Requires flatpak-builder and the GNOME SDK.)

```bash
flatpak run com.isyourbrainfoss.Progressor
```

## Development

```bash
cd /path/to/Progressor
export PATH="$PATH:$HOME/.pub-cache/bin"
melos bootstrap
melos run test
melos run run:linux
```

See `docs/PLAN.md` and slices for full roadmap and how to contribute with agents.

## License

GPL-3.0 or later (or MIT — TBD). Open for climbers.
