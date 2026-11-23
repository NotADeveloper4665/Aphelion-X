# XJAUS Linux KDE frontend prototype

This directory is an isolated native UI experiment. It uses Qt Quick and KDE Kirigami and talks to the existing Rust sidecar through its current newline-delimited JSON interface.

The first slice covers only backend startup, sign-in status, Microsoft device-code sign-in, cancellation, and sign-out. The Cloud catalog, console discovery, settings, controller navigation, and WebRTC player are not ported here. Keep using the existing Linux application for those flows. This target is not wired into release packaging and does not change the default app.

## Build prerequisites

- Qt 6.5 or newer with Core, Gui, Qml, Quick, and Quick Controls 2 development packages
- KDE Frameworks 6 Kirigami development package
- CMake 3.21 or newer and a C++20 compiler
- A separately built XJAUS Rust backend executable

## Build and launch

    cmake -S kde-linux -B build/kde-linux -DCMAKE_BUILD_TYPE=Release
    cmake --build build/kde-linux

Set XJAUS_BACKEND to the existing xjaus_backend executable before starting xjaus-kde. When packaged later, the app may resolve a bundled sidecar relative to its install path. Do not point this prototype at an untrusted executable.

The prototype keeps Microsoft device codes in the UI only long enough to display the sign-in step. Tokens remain in the Rust sidecar. It accepts only the Microsoft device-login HTTPS URLs already used by the app and has a deliberately small IPC command allowlist.

## Migration gate

Do not switch the Linux release entry point to this target until Cloud Gaming and Remote Play, sign-in and logout, settings, gamepad/keyboard navigation, diagnostics, suspend/recovery, and the WebRTC player have comparable behavior and evidence on supported Linux desktops. Until then, the existing UI remains the working fallback.
