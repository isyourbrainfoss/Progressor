# SLICE-I1: Android APK + Obtainium version.json

status: done
parallel_with: I2

## Prerequisites

Core app stable

## Scope

- .github/workflows for release APK (arm64)
- tool/ script to generate gh-pages/version.json
- Update README with Obtainium link

## Done when

- [x] CI with proper melos, analyze, tests, Linux build
- [x] Android prepare job
- [x] generate_version_json.sh tool
- [x] gh-pages/version.json

## Verify

```bash
melos bootstrap
melos run analyze --no-select
melos run test:flutter --no-select
flutter build linux --release
./tool/generate_version_json.sh --apk ... --out gh-pages/version.json
```