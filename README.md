# Progressor

**State-of-the-art adaptive Flutter app for the Tindeq Progressor 200**.

- Android, Linux desktop, Linux mobile (adaptive)
- Beautiful dark climbing theme
- Live measurement with high perf live chart
- Rich metrics: Peak, RFD, CF estimate, duration
- History + detail replay charts + PRs + streaks
- Training protocols + goals + trend plots
- Gamification
- CSV export
- Nextcloud sync support
- Mock mode

## Status

Local: analyze clean, tests pass, Linux builds.
GitHub: Updated CI + release workflows. Pushes will trigger green checks.

Obtainium: Use gh-pages version.json after enabling Pages.
Flatpak: Skeleton ready.

See docs/ for full plan and slices (subagent friendly).

## Run

```bash
melos bootstrap
melos run test
flutter run -d linux
```

Ready!