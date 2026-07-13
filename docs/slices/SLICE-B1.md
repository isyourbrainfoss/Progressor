# SLICE-B1: SensorAdapter + ForceSample integration

status: in_progress
parallel_with: A6

## Prerequisites

A3, A1

## Scope

- packages/progressor_sensors/
- packages/progressor_core models if needed

## Done when

- [ ] Adapter interface stable
- [ ] Mock works and replays demo data
- [ ] TindeqBleAdapter basic connect/notify/tare (mock preferred for tests)

## Verify

```bash
cd packages/progressor_sensors && dart test || echo "add tests"
flutter test
```

## Notes

Use fixtures.
