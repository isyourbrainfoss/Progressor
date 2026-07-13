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

Obtainium lets you install and auto-update directly from GitHub (no Play Store).

1. Install **Obtainium**:
   - From F-Droid, or download the latest APK from https://github.com/ImranR98/Obtainium/releases

2. Add Progressor to Obtainium:
   - Open Obtainium → tap the **+** button
   - Paste this URL:

     ```
     https://raw.githubusercontent.com/isyourbrainfoss/Progressor/gh-pages/version.json
     ```

   - Tap **Add** / **Check for updates**. It will download the latest APK.

One-tap link (opens Obtainium directly if installed):

```
https://apps.obtainium.imranr.dev/redirect.html?r=obtainium://add/https://raw.githubusercontent.com/isyourbrainfoss/Progressor/gh-pages/version.json
```

**Troubleshooting Obtainium:**
- "App not installed" or signature mismatch: uninstall any previous debug/dev build first:
  `adb uninstall com.isyourbrainfoss.progressor`
  or remove via Android Settings → Apps.
- Use the `gh-pages/version.json` (it points at the latest APKs and tracks versions reliably).
- If updates fail, check "Settings → Check for updates" or "Force update" in Obtainium for this app.
- Works on Android; Linux mobile via Flatpak below.

APKs are also attached to GitHub Releases for manual sideloading.

### Linux (Flatpak)

Flatpak is the recommended way for Linux desktop and mobile (e.g. postmarketOS, Ubuntu Touch with Flatpak).

Add the Progressor Flatpak remote and install:

```bash
# Add the remote (user scope, no sudo needed)
flatpak remote-add --if-not-exists --user progressor https://isyourbrainfoss.github.io/Progressor/progressor.flatpakrepo

# Install the app
flatpak install --user progressor com.isyourbrainfoss.Progressor
```

Run it:

```bash
flatpak run com.isyourbrainfoss.Progressor
```

**Updates:**

```bash
flatpak update --user com.isyourbrainfoss.Progressor
```

The required GNOME runtime is pulled automatically from Flathub on first install.

**Local Flatpak build (for development / packaging):**

Requires `flatpak` + `flatpak-builder` + GNOME SDK:

```bash
./flatpak/build-flatpak.sh
flatpak run com.isyourbrainfoss.Progressor
```

The build script produces a local repo and the `.flatpakrepo` file consumed by the remote URL above (also published to gh-pages).

### Other (from source)

```bash
git clone https://github.com/isyourbrainfoss/Progressor.git
cd Progressor
# see Development section
flutter build linux --release   # or flutter build apk --release
```

Binaries from CI are also available as workflow artifacts.

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
