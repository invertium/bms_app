# JBD BMS Flutter App

Android Flutter prototype for connecting to a JBD SP17S005 BMS over Bluetooth.

The project is configured so Flutter, Dart, Android SDK, Gradle, analysis,
tests, and APK builds run in Docker.

## Commands

```sh
make deps
make analyze
make test
make apk
```

The debug APK is written to:

```sh
build/app/outputs/flutter-apk/app-debug.apk
```

For physical-device installation:

```sh
make install-debug
```

See [docs/host-tools.md](docs/host-tools.md) for the few host-level tools that
are still useful for USB/ADB access.
