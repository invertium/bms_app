# Host tools

The project is set up so Flutter, Dart, Android SDK, Gradle, analysis, tests,
and APK compilation run in Docker.

Install these host-level executables only where Docker cannot replace the OS.

## Required

- `docker`
- `docker compose`

## Recommended

- Docker Buildx plugin. Compose can fall back to the classic builder, but
  Buildx removes the warning shown during image builds.

On Arch/CachyOS:

```sh
sudo pacman -S docker-buildx
```

## Required for real Android device testing

- USB permissions for Android devices.
- Optional but recommended host executable: `adb`.

On Arch/CachyOS, install:

```sh
sudo pacman -S android-tools android-udev
```

After installing udev rules, reconnect the phone and run:

```sh
adb devices
```

You can also try Dockerized ADB with:

```sh
make devices
```

USB forwarding into containers can be host-specific. If `make devices` cannot
see the phone, use host `adb` for device installation and logs while keeping
Flutter builds/tests in Docker.

## Not required on the host

- Flutter SDK
- Dart SDK
- Android SDK
- Gradle
- Java/JDK

## Common commands

```sh
make deps
make analyze
make test
make apk
make install-debug
```
