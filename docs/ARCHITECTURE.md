# Architecture

XJAUS is an independent Xbox Cloud Gaming and Xbox Remote Play client. Its current architecture uses an Electron desktop shell, a TypeScript/Vite renderer, and a Rust sidecar for authentication and session control.

| Layer | Code | Responsibility |
| --- | --- | --- |
| Renderer | src/, index.html, public/login.html | UI, preferences, WebRTC media and input; calls the backend through src/backend.ts. |
| Electron trust boundary | electron/preload.cjs, electron/main.cjs, electron/security.cjs | Narrow renderer API, IPC validation, desktop lifecycle and Rust sidecar supervision. |
| Electron sidecar | src-tauri/src/bin/xjaus_backend.rs | JSON requests over process stdio, authentication and session lifecycle. Linux builds from src-tauri/Cargo.toml; Windows builds the same entry point from backend-windows/Cargo.toml. |
| Retained Tauri runner | src-tauri/src/lib.rs | Native command bridge sharing Rust service modules; not the Electron distribution. |
| Packaging | package.json, scripts/packaging.cjs, scripts/build-windows.cjs | Renderer assets and platform sidecar are inputs; package verification and release authorization are separate. |

## Boundaries to preserve

- Keep the renderer isolated from Node APIs. Route privileged operations through the explicit preload and main-process command allowlists.
- Keep WebRTC media in the current renderer/media path. The Rust sidecar coordinates authentication, signaling and session lifecycle; video/audio frames do not belong in JSON stdio IPC.
- Treat Cloud Gaming and Remote Play as separate flows for compatibility and validation.
- Keep authentication credentials on the trusted side of the bridge. Sanitize diagnostics separately from UI errors and never export tokens, cookies, device codes, or raw account/session data.
- Keep attempt IDs and generation IDs distinct from active stream identity. A late reply or local cancellation must not overwrite a newer attempt or be reported as confirmed remote cleanup.
- Treat the Electron main process as the current supervisor of the Rust sidecar. Do not add more processes or replace the media stack without a measured need and an incremental fallback.

Authentication and stream attempt identities are distinct. Review admission, cancellation, late responses and logout across both runners; rejecting a late response locally does not establish remote cleanup. Keep credentials on the trusted side of the bridge and sanitize diagnostic exports separately from UI errors. Read [privacy](../PRIVACY.md) before capturing fixtures or diagnostics.

The staged replacement principles, milestones, control-contract goals, compatibility rules, and open audit questions are in [the XJAUS Founding Architecture](FOUNDING-ARCHITECTURE.md). That document is a proposal, not an implementation or platform-validation claim.
