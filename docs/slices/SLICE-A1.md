# SLICE-A1: Melos workspace + flutter create scaffold + initial docs

status: in_progress
parallel_with: none

## Prerequisites

None.

## Scope

- Root pubspec.yaml + melos config (already started)
- app/progressor (scaffolded)
- packages/ skeleton pubspecs (done)
- docs/PLAN.md, BACKLOG.md, PARALLEL.md, AGENT_GUIDE.md, slices/, protocols/
- Basic README.md at root
- .gitignore sensible

## Done when

- [ ] `melos bootstrap` succeeds without error
- [ ] `melos run run:linux` or `flutter run -d linux` shows basic app (even placeholder)
- [ ] `melos run test` runs (may have 0 tests initially)
- [ ] Basic structure matches plan

## Verify

```bash
cd /home/kb/repos/grok_build/tindeq
export PATH="$PATH:$HOME/.pub-cache/bin"
melos bootstrap
melos run test
melos run analyze || true
cd app/progressor && flutter run -d linux --no-pub &
```

## Fixture

none

## Notes

Continue with A2, A3, A5 in parallel after this is green.
