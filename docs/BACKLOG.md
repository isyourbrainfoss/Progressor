# Progressor Slice Backlog

| ID | Title | Status | Can parallel with |
|----|-------|--------|-------------------|
| A1 | Melos workspace + flutter create scaffold | done | — |
| A2 | Protocol docs + fixtures | done | A1,A3 |
| A3 | progressor_core models | done | A2 |
| A4 | Drift SQLite schema + repos for sessions | pending | A3,A5 |
| A5 | Adaptive shell (nav, tabs: Live / History / Train / More) | done | A4,A6 |
| A6 | Beautiful climbing theme (M3 dark + orange) | done | A4 |
| B1 | SensorAdapter interface + ForceSample | done | A6 |
| B2 | MockReplayAdapter + demo data | done | B1,B3 |
| B3 | TindeqProgressorBleAdapter (full protocol) | done | B2 |
| B4 | Merged / session sample stream helpers | partial | B3 |
| C1 | PullSession / TestSession state machine | done | B4 |
| C2 | Live screen: big number, gauge, live plot, tare/start/stop | done | C1,C3 |
| C3 | LiveForceChart (pretty custom painter) | done | C2 |
| C4 | Protocol selector + guided flow (peak, repeaters, RFD, CF) | done | C2,C5 |
| C5 | Auto-tare, auto-detect hang, threshold config | done | C4 |
| C6 | Save test + gamification hooks | done | C2 |
| D1 | History list with cards (PR highlights) | done | D2 |
| D2 | Test detail + replay plot + compare | done | D3 |
| D3 | CSV / JSON export + share | done | D1 |
| E1 | Trend plots (max force over time, CF %) | done | E2 |
| E2 | Fullscreen plot, zoom/pan | partial | E1 |
| E3 | Haptics + visual peaks | partial | E4 |
| F1 | Training library screen + protocol cards | done | F2 |
| F2 | Goals: create/edit targets (max, CF ratio, streak) | done | F1 |
| F3 | Best practice suggestions engine + personalized recs | done | F2 |
| F4 | Progress dashboard (strength index, graphs) | done | F3 |
| G1 | Gamification core: PR detector, streaks, XP | done | G2 |
| G2 | Achievements / badges UI + notifications | partial | G1 |
| G3 | Confetti on new PRs, level ups | partial | G2 |
| H1 | Nextcloud sync (WebDAV + blob like Flowlog) | done (helper) | H2 |
| H2 | Sync screen + settings + manual/auto sync | partial | H1 |
| I1 | Android build + version.json for Obtainium | done | I2 |
| I2 | Flatpak manifest + build script + .flatpakrepo | done | I1 |
| I3 | gh-pages deploy scripts + CI | done | I2 |
| J1 | Tests for core + sensors + charts | partial (app green) | various |
| J2 | Polish, accessibility, desktop shortcuts | partial | J1 |
| J3 | Demo mode enhancements, onboarding | partial | J2 |

**Status legend:** pending | in_progress | done

Packaging/CI (I*) completed by subagent. Local melos + build + tests green. CI now has full bootstrap/analyze/test + Linux/Android build jobs.