# SLICE-C6: Save test + gamification hooks

status: done
parallel_with: C2

## Prerequisites

C1, A4

## Scope

- Live stop saves PullTest via storage
- Basic PR detection on save
- Update strength index / streak

## Verify

```bash
flutter test
```

## Done when

- [x] History shows saved items
- [x] New PRs get special treatment
- [x] Gamification: streak increment stub + PR detection on save (in Live stop)
- [x] History improved to show simple metrics (duration, avg, streak banner, best peak, chronological PRs)
