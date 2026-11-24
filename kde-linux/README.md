# XJAUS Linux KDE frontend

This is the native Linux shell built with Qt Quick and KDE Kirigami. It starts the existing Rust sidecar directly and uses its bounded, versioned newline-delimited JSON protocol. The Rust backend remains shared with Electron; auth, session ownership, cancellation, and stream negotiation are not reimplemented in QML.

## Current migration slice

Implemented in this candidate:

- Rust backend startup, health/version/capability query, and sign-in status
- Microsoft device-code sign-in, cancellation, and sign-out
- Console and Remote Play target discovery, with native launch controls
- Cloud catalog discovery and native launch controls
- Load and save for streaming settings
- The existing WebRTC session, video, gamepad, keyboard, telemetry, and recovery code inside a restricted Qt WebEngine player surface

The Kirigami UI owns sign-in, navigation, console/cloud selection, and settings. Qt WebEngine hosts only the existing playback surface so the mature connection cancellation and teardown path stays shared. This candidate now has an opt-in Fedora RPM build; the current Linux release default remains available for rollback until the candidate builds and passes real-session validation. Windows continues using Electron.

## Build prerequisites

- Qt 6.5 or newer with Core, Gui, Qml, Quick, Quick Controls 2, WebChannel, and WebEngine development packages
- KDE Frameworks 6 Kirigami development package
- CMake 3.21 or newer and a C++20 compiler
- Node/npm, Rust/Cargo, and a separately built XJAUS Rust backend executable

## Build and launch

    cmake -S kde-linux -B build/kde-linux -DCMAKE_BUILD_TYPE=Release
    cmake --build build/kde-linux

For a source build, set `XJAUS_BACKEND` to the existing `xjaus_backend` executable before starting `xjaus-kde`. The RPM candidate resolves its bundled sidecar relative to `/usr/bin`. Do not point this frontend at an untrusted executable.

## Build an installable Fedora candidate

Install the locked Node dependencies once, then build the renderer, Rust sidecar, KDE app, and Fedora RPM together:

    npm ci
    npm run dist:linux:kde

The build needs Node/npm, the Qt 6/Kirigami/WebEngine development packages, CMake, a C++20 compiler, Rust/Cargo, RPM build tools, and the WebKitGTK/libsecret development packages used by the shared backend. The CI job installs these from Fedora 44 repositories.

This produces a Fedora RPM in `release/linux-kde/` and installs an XJAUS desktop entry, icon, Kirigami executable, web player assets, and Rust sidecar. CI uploads the RPM for seven days. Existing Linux package outputs and the release default remain unchanged until the playback gate below is met.

Tokens remain in the Rust sidecar. The UI accepts only Microsoft device-login HTTPS URLs already used by the app. Requests carry IPC API version 1; unversioned clients remain accepted by the backend, while unknown versions are rejected before dispatch. The Rust process remains the single owner of authentication, session, cancellation, settings, and Xbox API state.

## Progressive cutover

1. Build the Fedora RPM in CI and fix any compile/package failures.
2. Install it on Fedora KDE and validate sign-in/logout races, settings, Remote Play wake/stream, Cloud Gaming, video/audio, gamepad/keyboard, suspend/recovery, fullscreen, and diagnostics with a real Xbox session.
3. Keep the Electron Linux package available as rollback while the RPM is an opt-in candidate.
4. Change the Linux desktop entry point only after those checks pass. Windows remains Electron.

Keep each stage independently buildable and keep the Electron Linux package available until the candidate passes real-session validation.
