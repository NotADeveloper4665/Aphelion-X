# Architecture

| Layer | Code | Responsibility |
| --- | --- | --- |
| Shared player surface | `src/`, `index.html`, `public/login.html` | Existing WebRTC media, controller/keyboard input, and recovery lifecycle; calls the backend through `src/backend.ts`. |
| Native KDE shell | `kde-linux/` | Kirigami navigation, sign-in, catalog/console selection, settings, and Qt WebEngine player hosting. Calls the Rust sidecar through a bounded, versioned WebChannel bridge. |
| Electron shell | `electron/preload.cjs`, `electron/main.cjs`, `electron/security.cjs` | Windows frontend and Linux rollback; narrow renderer API, IPC validation, desktop lifecycle, and Rust sidecar supervision. |
| Rust service process | `src-tauri/src/bin/xjaus_backend.rs` | JSON requests over process stdio, authentication, Xbox API access, settings, stream ownership/cancellation, bounded dispatch, health and capability reporting. Linux builds from `src-tauri/Cargo.toml`; Windows builds the same entry point from `backend-windows/Cargo.toml`. |
| Retained Tauri runner | `src-tauri/src/lib.rs` | Additional native command bridge sharing Rust service modules. |
| Packaging | `package.json`, `scripts/build-linux-kde.cjs`, `scripts/packaging.cjs`, `scripts/build-windows.cjs` | Native Fedora package is the Linux development default; Electron Linux packaging remains an explicit rollback. Published release authorization stays separate. |

The Rust process owns credentials, auth generations, stream attempts, cancellation, settings, and Xbox API state. Both shells share the same request/response contract; the native shell must not implement a second session owner. Auth and stream attempt identities are distinct. Review admission, cancellation, late responses and logout across both bridges; rejecting a late response locally does not establish remote cleanup. Keep credentials on the trusted side of the bridge and sanitize diagnostic exports separately from UI errors. Read [privacy](../PRIVACY.md) before capturing fixtures or diagnostics.

`backend_status` keeps its existing top-level fields and adds an optional `health` object. `health.service` means the Rust service answered the request; it does not indicate Xbox connectivity. `health.authentication` is `authenticated` or `signed-out`. `health.session` reports the Rust-owned session lifecycle state, kind, and whether a backend session identifier is present; it never returns the identifier itself. `health.cleanup.state` is `clear`, `pending`, or `uncertain`, and `pendingOperations` counts detached cleanup operations still running. Uncertain cleanup remains distinct from a healthy/ready IPC process. These values do not claim WebRTC decoder, network, or rendered-frame health; those belong to the shared player and must be measured there.

See the [Aphelion-inspired architecture plan](APHELION-INSPIRED-ARCHITECTURE-PLAN.md) for the staged migration, compatibility constraints, and explicit non-goals.
