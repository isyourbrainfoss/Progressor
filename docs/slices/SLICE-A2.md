# SLICE-A2: Protocol docs + initial fixtures

status: pending
parallel_with: A1,A3

## Prerequisites

A1 partial

## Scope

- `docs/protocols/tindeq-progressor.md` (basic done)
- `fixtures/` with demo_pull.jsonl and minimal_pull.json (generate simple)
- Sensor sample models in core

## Done when

- [ ] Protocol doc complete with examples
- [ ] Fixture files exist and parseable (jsonl of time,force)
- [ ] Can load in tests

## Verify

```bash
ls fixtures/
dart run tool/ or flutter test packages/... (later)
```

## Fixture

Use simple generated or copy pattern from Flowlog demo_shot.

## Notes

Create a small script or manually make 10s of fake data for replay.
