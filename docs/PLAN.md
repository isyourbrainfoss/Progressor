# Progressor Plan (Tindeq Progressor 200 Flutter App)

Full slice specs live in [`slices/`](slices/). Parallel waves: [`PARALLEL.md`](PARALLEL.md).

## Vision

State-of-the-art, beautiful adaptive Flutter app for the Tindeq Progressor 200 climbing dynamometer. Works seamlessly on Android phones, Linux desktop, and Linux mobile (e.g. postmarketOS). 

Replicates and surpasses the original Tindeq app:

- Precise live force measurement and multiple test protocols
- Rich history with pretty, interactive plots
- Guided best-practice finger training with goals and progress tracking
- Gamification: streaks, personal records, achievements, strength score
- Nextcloud sync (inspired by Flowlog) for seamless multi-device use
- Export, import, simulator mode for no-hardware use
- Installable via Obtainium (APK from gh-pages) and Flatpak

**Theme:** Modern climbing-inspired dark UI — deep slate/charcoal backgrounds, vibrant climbing orange (#FF6B35) and teal accents, clean typography, smooth animations, large readable numbers for force during hangs.

**Adaptive layout** (same breakpoints as Flowlog):
- <600dp or short: bottom nav
- 600dp+: sidebar rail
- Larger: split views, rich charts

## Stack (inspired by Flowlog)

- **UI:** Flutter 3 + Material 3, NavigationRail / bottom nav, provider or riverpod?
- **Core:** `progressor_core` — Drift/SQLite, Pull/Test models, session logic, CSV/JSON export, sync blobs, recommendations engine
- **Sensors:** `progressor_sensors` — flutter_blue_plus Tindeq adapter + MockReplayAdapter + simulator
- **Charts:** `progressor_charts` — high performance CustomPainter live force curves + history plots (supplemented by fl_chart for dashboards)

## Tindeq Protocol (from official client)

See `docs/protocols/tindeq-progressor.md`

Key UUIDs (128-bit):
- Service: 7e4e1701-1ea6-40c9-9dcc-13d34ffead57
- Data (notify): 7e4e1702-...
- Control: 7e4e1703-...

Commands (single byte for simple ones):
- 100: TARE
- 101: START_WEIGHT_MEAS
- 102: STOP
- 103/104: RFD modes
- etc.

Data notifications: TLV, RES_WEIGHT_MEAS (tag 1) carries float kg + u32 us timestamps (little endian). Multiple samples per packet.

## Test / Session Types

1. **Peak / Max Pull** — single max effort, capture peak, time-to-peak, RFD.
2. **RFD / Explosive** — dedicated rate of force development.
3. **Repeaters / Endurance** — configurable on/off (e.g. 7s/3s), compute Critical Force (CF), W', fatigue index.
4. **Endurance / CF Test** — sustained or repeaters protocol to find sustainable force.
5. **Custom / Free Logging** — freeform recording for workouts.
6. **Guided Workouts** — from library, auto prompts, logs performance.

Each "PullSession" or "Test" has:
- metadata: type, grip (edge mm?, hand L/R/both, notes, bodyweight)
- samples: List<ForceSample> (timeMs, forceN or kg, quality)
- computed metrics: peak, mean, CF estimate, etc.

## Key Features & Polish

- Live screen: big force number (kg or N toggle), smooth scrolling live plot, gauge, timer, start/stop/tare, protocol selector, target lines.
- Auto-detect hang start (threshold).
- History: beautiful cards, filter by type/date/PR, search.
- Detail: full replay plot, metrics table, overlay previous PR curve.
- Plots: live high-fps, zoomable history, multi-test compare, progress trend lines (max, CF over time).
- Training Hub: 
  - Curated protocols with instructions, "why", expected progress (e.g. "beginner max 40-60% BW on 20mm").
  - Goal setting: target max force, CF ratio, volume.
  - Personalized suggestions based on recent tests (e.g. "Your CF is 55% of max — focus endurance repeaters at 60-70%").
- Gamification:
  - Personal Records banner + confetti on beat.
  - Daily/weekly streak counter + calendar heat.
  - Achievements (badges): "Centurion" (100kg+), "Iron Fingers", "Consistent Climber" (30 day streak), "RFD Beast".
  - Strength Index score (composite of max, CF, RFD, consistency).
  - Levels / XP from sessions.
- Nextcloud Sync: identical pattern to Flowlog — WebDAV + encrypted blobs or plain, merge on pull, push local.
- Simulator: replay demo pulls, generate synthetic data, manual entry.
- Other: battery status, firmware, settings (units kg/N, sample rate), dark/light? but prefer dark, CSV/JSON export + share, import.

## MVP Path (slice based)

Similar to Flowlog: A (scaffold) → B (sensors + core) → C (live) → D (history) → E (plots/gamif) → F (training/suggestions) → G (sync) → H (packaging)

See PARALLEL.md and slices/.

## Packaging & Distribution (critical for user request)

- **Android:** Standard + arm64 APK published to gh-pages for Obtainium.
  - version.json with versionCode, sha, url.
- **Linux:** Flatpak manifest (com.isyourbrainfoss.progressor or com.progressor.progressor? use org.isyourbrainfoss.Progressor), build script, .flatpakrepo.
  - Support both x86_64 desktop and aarch64 mobile.
- GitHub Pages enabled.
- Releases with bundles.

## Development

```bash
# from tindeq root
export PATH="$PATH:$HOME/.pub-cache/bin"
dart pub get
melos bootstrap
melos run test
melos run analyze
melos run run:linux
```

See AGENT_GUIDE.md for slice workflow.

## Stretch / State-of-the-Art ideas (implement as time allows)

- Beautiful onboarding with climbing illustrations or Lottie if possible.
- Offline AI-lite suggestions (rule based + simple models).
- Multi-hand or two device sync (rare).
- Integration with training plans (calendar).
- Shareable profile cards (image export of PRs).
- Wear OS or desktop widgets? Later.
- Fullscreen plot mode.
- Haptics on peaks and thresholds.
- Accessibility: large text, screen reader, keyboard nav on desktop.

This will be the best open source Tindeq companion app.
