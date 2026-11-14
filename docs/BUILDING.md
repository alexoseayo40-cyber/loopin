# Building Loopin

Loopin is a Flutter app (`app/`) with a C++ audio engine (`packages/loopin_engine/`) built on [Oboe](https://github.com/google/oboe) and connected with `dart:ffi`. It has no dependencies besides `ffi`: permissions, settings, external keys, file picking and sharing are done in Kotlin (`MainActivity.kt`).

## Requirements

- Git, [Flutter](https://docs.flutter.dev/get-started/install) **3.47.9** and Android Studio (Android SDK 36, NDK 28.2.13676358, CMake 3.22.1; the NDK and CMake are downloaded on the first build if missing).
- Android 8.0 (API 26) or later to run it.
- On Windows: turn on Developer Mode (Flutter needs symlinks) and long paths (`git config --global core.longpaths true` and the `LongPathsEnabled` registry key), and keep the project in a short path such as `C:\dev\loopin`: Oboe's paths go past 260 characters otherwise.

## Get the code and run it

```sh
git clone --recursive https://github.com/alexoseayo40-cyber/loopin.git
cd loopin/app
flutter run --release
```

If you cloned without `--recursive`: `git submodule update --init --recursive` (Oboe is a submodule).

The first build compiles Oboe and the engine for the phone and takes a while.

## Tests

From `app/`:

```sh
flutter analyze
flutter test
```

The UI tests use a fake engine (`app/test/support.dart`). The engine tests run on the PC, without a phone, and check the audio sample by sample:

```sh
cmake -S engine_tests -B build/engine_tests -DCMAKE_BUILD_TYPE=Release
cmake --build build/engine_tests -j
./build/engine_tests/loopin_engine_tests
```

(On Windows you need the Visual Studio Build Tools; the binary ends up in `build\engine_tests\Release\`.)

GitHub Actions runs all of this and builds an APK on every push (`.github/workflows/build.yml`).

## Useful tools

- `flutter test tool/screenshots_test.dart --update-goldens` (from `app/`): screenshots of every screen without a phone, in `app/tool/screenshots/`.
- `drum_demo app/assets/drums <folder>` (built with the engine tests): one WAV per drum style, to listen to them without a phone.
- `app/tool/make_icon.py` and `app/tool/make_drums.py`: generate the launcher icon PNGs and the drum sounds.

## Code rules

- `dart format` at 100 columns (`app/analysis_options.yaml`).
- Every user-visible text lives in `app/lib/l10n/strings.dart`.
- Inside the audio callback: no memory allocation, no locks, no file access. Commands go through a lock-free SPSC queue and state comes back through atomics. Everything is counted in samples. See [MOTOR.md](MOTOR.md) (in Spanish).
- Source files carry `SPDX-License-Identifier: GPL-3.0-or-later`.

## Signing

Release builds are signed with the maintainer's key, which never goes into the repository: `key.properties`, `*.jks` and `*.keystore` are in `.gitignore`. Without a key, `flutter build apk --release` signs with the debug key, which is fine for testing.
