# Progressor — Agent Guide

## Picking up work

1. Check [`PARALLEL.md`](PARALLEL.md) for slices safe to run **right now**.
2. Open [`slices/SLICE-XX.md`](slices/) — confirm prerequisites are `done`.
3. Implement **only** paths listed under Scope.
4. Run the **Verify** command(s); fix until green.
5. Set `status: done` in the slice file header.
6. Update [`BACKLOG.md`](BACKLOG.md) status column for that row.

## Repo layout

| Path | Purpose |
|------|---------|
| `app/progressor/` | Flutter UI shell (adaptive) |
| `packages/progressor_core/` | Models, Drift DB, repositories, session logic, recommendations, sync |
| `packages/progressor_sensors/` | TindeqBleAdapter, MockReplay, sensor samples |
| `packages/progressor_charts/` | LiveForceChart, HistoryPlot, pretty painters |
| `fixtures/` | Demo pull streams (jsonl), golden data |
| `docs/protocols/` | Tindeq BLE protocol notes |
| `docs/slices/` | One spec per slice (A1–...) |
| `docs/PARALLEL.md` | Multi-agent wave guide |
| `docs/BACKLOG.md` | Master table |
| `docs/PLAN.md` | Architecture |
| `flatpak/` | Flatpak manifest + build |
| `tool/` | Scripts (build, prepare gh-pages, etc) |

## Commands

```bash
export PATH="$PATH:$HOME/.pub-cache/bin"
dart pub get
melos bootstrap
melos run test
melos run analyze
melos run run:linux
cd app/progressor && flutter run -d linux
```

For Android:
- Use USB debug or emulator.
- For Obtainium builds see packaging slices.

## Golden rules

- **No slice requires real hardware.** Always provide Mock + fixtures.
- Use host monotonic time for samples.
- Keep UI responsive: live plots on RepaintBoundary.
- Beautiful first: generous padding, clear hierarchy, nice typography, smooth 60fps curves.
- Follow Flowlog patterns for adaptive nav, sync, DB.
- Tests: unit for core/sensors, widget for UI.
- For gamification and suggestions, prefer pure Dart in core where possible.

## Slice index (initial)

Scaffold (A), Sensors+Core (B), Live (C), History (D), Polish+Plots (E), Training+Goals (F), Gamif (G), Sync (H), Packaging (I)

## Spawn prompt (copy-paste for subagents)

```text
Read docs/AGENT_GUIDE.md and docs/slices/SLICE-XX.md.
Implement only that slice. Run Verify. Set status: done.
Do not edit files outside Scope.
```

When spawning multiple: make sure scopes are disjoint per PARALLEL.md.
