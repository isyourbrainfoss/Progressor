# Progressor Slice Backlog

| ID | Title | Status | Can parallel with |
|----|-------|--------|-------------------|
| A1 | Melos workspace + flutter create scaffold | pending | — |
| A2 | Protocol docs + fixtures | pending | A1,A3 |
| A3 | progressor_core models + Pull/Test | pending | A2 |
| A4 | Drift SQLite schema + repos for sessions | pending | A3,A5 |
| A5 | Adaptive shell (nav, tabs: Live / History / Train / More) | pending | A4,A6 |
| A6 | Beautiful climbing theme (M3 dark + orange) | pending | A4 |
| B1 | SensorAdapter interface + ForceSample | pending | A6 |
| B2 | MockReplayAdapter + demo data | pending | B1,B3 |
| B3 | TindeqProgressorBleAdapter (full protocol) | pending | B2 |
| B4 | Merged / session sample stream helpers | pending | B3 |
| C1 | PullSession / TestSession state machine | pending | B4 |
| C2 | Live screen: big number, gauge, live plot, tare/start/stop | pending | C1,C3 |
| C3 | LiveForceChart (pretty custom painter) | pending | C2 |
| C4 | Protocol selector + guided flow (peak, repeaters, RFD, CF) | pending | C2,C5 |
| C5 | Auto-tare, auto-detect hang, threshold config | pending | C4 |
| D1 | History list with cards (PR highlights) | pending | D2 |
| D2 | Test detail + replay plot + compare | pending | D3 |
| D3 | CSV / JSON export + share | pending | D1 |
| E1 | Trend plots (max force over time, CF %) | pending | E2 |
| E2 | Fullscreen plot, zoom/pan | pending | E1 |
| E3 | Haptics + visual peaks | pending | E4 |
| F1 | Training library screen + protocol cards | pending | F2 |
| F2 | Goals: create/edit targets (max, CF ratio, streak) | pending | F1 |
| F3 | Best practice suggestions engine + personalized recs | pending | F2 |
| F4 | Progress dashboard (strength index, graphs) | pending | F3 |
| G1 | Gamification core: PR detector, streaks, XP | pending | G2 |
| G2 | Achievements / badges UI + notifications | pending | G1 |
| G3 | Confetti on new PRs, level ups | pending | G2 |
| H1 | Nextcloud sync (WebDAV + blob like Flowlog) | pending | H2 |
| H2 | Sync screen + settings + manual/auto sync | pending | H1 |
| I1 | Android build + version.json for Obtainium | pending | I2 |
| I2 | Flatpak manifest + build script + .flatpakrepo | pending | I1 |
| I3 | gh-pages deploy scripts + CI | pending | I2 |
| J1 | Tests for core + sensors + charts | pending | various |
| J2 | Polish, accessibility, desktop shortcuts | pending | J1 |
| J3 | Demo mode enhancements, onboarding | pending | J2 |

**Status legend:** pending | in_progress | done

Update after each slice completion.
