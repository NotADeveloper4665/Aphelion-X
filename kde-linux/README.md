# XJAUS Linux KDE frontend

This is a separate native Linux UI built with Qt Quick and KDE Kirigami. It starts the existing Rust sidecar directly and uses its bounded newline-delimited JSON protocol. The Rust backend remains shared with Electron; this project does not fork auth, streaming, or session state into a second implementation.

## Current migration slice

Implemented in this target:

- Rust backend startup, health/version/capability query, and sign-in status
- Microsoft device-code sign-in, cancellation, and sign-out
- Read-only console presence, Remote Play target, and Cloud catalog views
- Load and save for streaming settings

The console/catalog views do not start games yet, and the WebRTC player, wake flow, controller/keyboard input, recovery UI, and complete diagnostics are still in the existing app. This target is not wired into release packaging and does not change the Linux default. Windows continues using Electron.

## Build prerequisites

- Qt 6.5 or newer with Core, Gui, Qml, Quick, and Quick Controls 2 development packages
- KDE Frameworks 6 Kirigami development package
- CMake 3.21 or newer and a C++20 compiler
- A separately built XJAUS Rust backend executable

## Build and launch

    cmake -S kde-linux -B build/kde-linux -DCMAKE_BUILD_TYPE=Release
    cmake --build build/kde-linux

Set `XJAUS_BACKEND` to the existing `xjaus_backend` executable before starting `xjaus-kde`. When packaged later, the app may resolve a bundled sidecar relative to its install path. Do not point this frontend at an untrusted executable.

Tokens remain in the Rust sidecar. The UI accepts only Microsoft device-login HTTPS URLs already used by the app. Requests carry IPC API version 1; unversioned clients remain accepted by the backend, while unknown versions are rejected before dispatch. The Rust process remains the single owner of authentication, session, cancellation, settings, and Xbox API state.

## Progressive cutover

1. Complete native console/cloud actions and the game launch flow while keeping the existing renderer as the proven playback implementation.
2. Connect the native flow to playback with an explicit, bounded interface and preserve cancellation, cleanup, and recovery behavior.
3. Validate sign-in/logout races, settings compatibility, Remote Play, Cloud Gaming, WebRTC playback, gamepad/keyboard, suspend/recovery, and diagnostics on supported Linux desktops.
4. Add native Linux packaging as an opt-in candidate with an easy Electron rollback.
5. Change the Linux desktop entry point only after those checks pass. Windows remains Electron.

Keep each stage independently buildable and keep the Electron Linux package available until the candidate passes real-session validation.