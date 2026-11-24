# XJAUS-KDE

[Español](README.es.md)

**Xbox Cloud Gaming and Xbox Remote Play on desktop Linux and Windows.**

XJAUS is an independent, controller-focused streaming client. It connects to Xbox Cloud Gaming and compatible Xbox consoles, with a Rust service handling authentication, Xbox API requests, settings, and stream-session ownership.

XJAUS-KDE draws on Aphelion’s streaming architecture for its Qt/KDE frontend and Rust service health reporting.

> **Linux update:** This branch adds a native KDE Kirigami frontend and Fedora RPM build path. The RPM is still a candidate: it needs a successful native build and real Xbox session validation. Published Linux packages remain available as the current release and rollback. Windows continues to use Electron.

## What it does

- Browse and launch eligible Xbox Cloud Gaming titles.
- Discover compatible home consoles and connect through Xbox Remote Play.
- Sign in with Microsoft device code authentication.
- Navigate with a game controller, with keyboard and pointer support.
- Adjust streaming preferences and view available diagnostics.
- Use the same Rust services and stream lifecycle from the native Linux shell and the existing desktop frontend.

Streaming availability depends on Microsoft account eligibility, region, network conditions, and service availability. Remote Play requires a compatible console configured for remote access.

## Platform status

| Platform | Current path | Status |
| --- | --- | --- |
| Fedora Linux | Qt Quick / KDE Kirigami app with the existing Rust backend and WebRTC player | RPM candidate; build and real-session validation pending |
| Other Linux packages | Existing Electron AppImage, RPM, and DEB | Published v1.2.4 packages |
| Windows | Electron frontend with Rust backend | Build configured; native Windows QA and signed installers are pending |

The native Linux shell owns sign-in, navigation, console/cloud selection, and settings. Qt WebEngine hosts the existing player so stream negotiation, controller handling, recovery, and teardown continue to use the established code. The Electron Linux package remains available as a rollback during the staged migration.

## Download the current release

The latest published release is **v1.2.4**. Its Linux packages use the existing Electron frontend; they are separate from the native KDE candidate in this branch.

- [Release notes and downloads](https://github.com/perjesus111-hub/xjaus/releases/tag/v1.2.4)
- [SHA256 checksums](https://github.com/perjesus111-hub/xjaus/releases/download/v1.2.4/SHA256SUMS)

## Build the native Fedora package

Build on Fedora 44 for a Fedora 44 target, or use a Fedora 44 container. The project needs Node/npm, Rust/Cargo, CMake, a C++20 compiler, Qt 6 WebEngine and WebChannel development packages, KDE Kirigami, RPM tools, and the shared Rust backend's WebKitGTK/libsecret development packages.

```bash
npm ci
npm run dist:linux
```

The Fedora RPM is written to `release/linux-kde/`. Detailed package requirements, source-build instructions, and rollout gates are in [kde-linux/README.md](kde-linux/README.md). The previous Electron Linux packager remains available as `npm run dist:linux:electron`.

The candidate has not yet been compiled in this workspace, and its Xbox streaming path has not yet been tested on a real session. Do not treat it as a release until those checks pass.

## Architecture and project principles

- **Rust owns service state.** Authentication credentials, Xbox API access, settings, stream attempts, cancellation, and cleanup stay in the Rust process.
- **Frontends share one contract.** The native shell and Electron call the same bounded, versioned backend interface; QML does not create a second session owner.
- **Changes roll out in stages.** Keep the existing Linux package as rollback until the native RPM builds and sign-in, Cloud Gaming, Remote Play, audio/video, input, recovery, and shutdown are validated.

See [architecture](docs/ARCHITECTURE.md), [privacy](PRIVACY.md), [contributing](CONTRIBUTING.md), and the [native KDE build guide](kde-linux/README.md).

## License and disclaimer

XJAUS is distributed under the GNU General Public License version 3. See [LICENSE](LICENSE) and preserve upstream notices. Xbox and Microsoft are trademarks of Microsoft Corporation. XJAUS is independent and is not affiliated with, sponsored by, or endorsed by Microsoft or Xbox. Third-party dependencies and bundled visual assets retain their respective licenses.
