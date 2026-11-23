# XJAUS Founding Architecture

**Status:** Design proposal 0.1  
**Date:** 2026-11-23  
**Decision owner:** Solo maintainer

This document adapts the progressive-replacement principles used in Aphelion to XJAUS. It is a plan, not a claim that the proposed contracts, audits, or validation have been completed. It describes how XJAUS can evolve without replacing its working Xbox Cloud Gaming or Xbox Remote Play paths all at once.

## 1. Purpose and scope

XJAUS is an independent desktop client for Xbox Cloud Gaming and Xbox Remote Play. Its current stack is Electron, a TypeScript/Vite renderer, and a Rust sidecar. The renderer owns the controller-oriented UI and WebRTC media path. The Electron main process starts the Rust sidecar and exposes a restricted IPC bridge. The Rust code handles authentication and stream/session control. Linux and Windows builds use different Cargo manifests around shared Rust modules; a Tauri runner is retained in the source tree.

The goal is to improve reliability, security, observability, and maintainability while preserving the existing user-visible connection flows. Aphelion is a separate Linux streaming-host project. XJAUS should borrow its engineering principles—explicit ownership, contracts, evidence, small extraction gates—not Syzygy host code or assumptions about capture, encoders, FEC, or Moonlight protocol handling.

**Core migration rule:** keep the existing path available until a replacement passes equivalent checks on the affected platform and session type. Ship one bounded change at a time, and make rollback practical.

## 2. Founding principles

1. **Keep both products usable:** Cloud Gaming and Remote Play are distinct service flows. A change to one must not silently change the other.
2. **Preserve compatible interfaces:** retain current renderer commands and sidecar behavior during internal refactors. Add compatibility adapters before removing old call paths.
3. **Keep media out of control IPC:** JSON stdio IPC coordinates authentication, signaling, and session lifecycle. WebRTC media belongs to the existing media path; do not move video or audio frames through the control bridge.
4. **Make ownership explicit:** assign every connection attempt, generation, stream resource, credential, and cleanup action to a component.
5. **Fail closed on uncertain auth or session state:** a local timeout or cancellation does not prove that Microsoft rejected or cleaned up a remote operation.
6. **Do not widen privileges to fix packaging:** retain Electron isolation, sandboxing, URL restrictions, bounded IPC, and platform security controls.
7. **Measure before optimizing:** distinguish requested stream settings from negotiated video properties and measured decoder or presentation behavior.
8. **Replace progressively:** keep the existing implementation as the reference path until the new path is validated and rollback has been rehearsed.
9. **Keep the scope maintainable:** do not split processes or rewrite the renderer, Rust backend, or WebRTC stack without a specific tested benefit.
10. **Use evidence, not authorship, to judge code:** AI-assisted changes require the same reviewable diffs and reproducible validation as other changes.

## 3. Current architecture and boundaries

The current architecture documented and observed in the repository is:

| Component | Current responsibility | Boundary to preserve |
|---|---|---|
| Renderer (src/) | UI, preferences, WebRTC media and input; calls src/backend.ts | Must not gain Node access or receive raw credentials through new shortcuts |
| Electron main (electron/main.cjs) | App/window lifecycle, sidecar process, newline-delimited request/reply IPC, request bounds, shutdown handling | Remains the process supervisor and trusted desktop boundary |
| Preload/security (electron/preload.cjs, electron/security.cjs) | Narrow command allowlist, sender validation, external URL and clipboard checks | Keep command access explicit and least-privilege |
| Rust sidecar (src-tauri/src/bin/xjaus_backend.rs) | JSON requests over stdio; auth and session/stream control | Preserve its current command semantics while internals are extracted |
| Shared Rust services (src-tauri/src/) | Service logic reused by Electron sidecar builds | Avoid duplicating cloud/home behavior across platform runners |
| Tauri runner (src-tauri/src/lib.rs) | Retained native command bridge to shared Rust services | Keep behavior aligned where it remains supported; do not treat it as the Electron production runner |
| Microsoft/Xbox services and WebRTC peer | External identity, catalog, console, signaling and media endpoints | Treat remote behavior and cleanup as externally observable, not locally guaranteed |

The renderer currently contains the WebRTC media path. XJAUS is a client of Xbox services; it does not own the host capture/encode/network pipeline described in Aphelion. Do not transplant host-side encoder workers, Moonlight pairing, FEC, or host capture abstractions into this project.

### 3.1 Connection identity and lifecycle

Every connection attempt must remain distinguishable from the active stream. Preserve the existing attemptId and generation guards while reviewing all commands that mutate a connection. Late replies from an older attempt must not replace or stop the newer attempt.

The implementation and future contract should state, for each operation:

- who creates and owns its identifier;
- whether it is safe to retry;
- what a timeout means and what it does not prove;
- how cancellation is delivered and acknowledged;
- who owns remote session cleanup identifiers;
- what happens if the renderer, Electron main process, sidecar, or network disappears.

Never label remote cleanup as successful solely because local state was cleared. Surface an unknown outcome when the request may have reached the service but its response was lost.

### 3.2 Authentication and data

The current release status documents in-memory authentication and fresh interactive sign-in after restart. Preserve that behavior unless a separate design establishes a safer credential lifecycle and migration plan. Do not add persistent token storage as an incidental consequence of reorganizing Rust modules.

Keep tokens, cookies, device codes, authorization headers, account caches, console identifiers, and unredacted auth logs out of the renderer unless the UI strictly needs a short-lived value. Diagnostic output must use allowlisted fields and synthetic test fixtures. A local sign-out or credential-store cleanup attempt must not be described as server-side token revocation.

## 4. Control contract

The existing Electron bridge uses a command allowlist and correlated JSON request/reply messages. That is the compatibility baseline. The exact command inventory, argument shapes, and response semantics must be audited before changing them.

The target contract is:

- versioned at a boundary that can be tested by both the Electron sidecar and retained Tauri runner;
- keyed by request ID and, for connection mutations, the existing attempt and generation IDs;
- explicit about command, arguments, result, and typed failure category;
- bounded by message size, pending request count, timeout policy, and cancellation capacity;
- safe under duplicate, stale, malformed, and late requests;
- independent of which Rust module or runner implements a command.

Do not introduce a required breaking protocol field in the first migration step. First document and test the current envelope. If version metadata is added later, accept the current form during a compatibility period and reject unsupported future versions clearly. Do not rename commands and change their semantics in the same change.

Illustrative future envelope only; this is not the current schema:

    {
      "protocol_version": 1,
      "id": 42,
      "cmd": "start_stream",
      "args": {
        "attemptId": "opaque-attempt",
        "generation": "opaque-generation"
      }
    }

The example is not a final schema and does not assert that protocol_version currently exists. Keep credentials and media payloads out of diagnostic representations of this message.

## 5. Progressive migration plan

### Milestone 0 — Baseline and source audit

Before behavioral changes:

- Record the source commit and worktree state.
- Map the Electron command allowlist, main-process dispatcher, Rust sidecar dispatch, shared modules, and Tauri command bridge.
- Trace one Cloud Gaming and one Remote Play flow from user action through sign-in/session setup, signaling, WebRTC start, cancellation, stop, logout, and cleanup.
- Map ownership of tokens, pending auth, session IDs, attempt/generation IDs, WebRTC peer state, and remote cleanup.
- Record which tests run in CI and which require a live account, compatible Xbox console, native Windows, or Linux hardware.
- Capture a baseline for the supported source test matrix and report unavailable hardware/service checks as blocked, not passed.
- Inspect test fixtures and subprocesses before running them; use synthetic credentials and endpoints.

**Exit:** source maps, command contract, ownership/lifecycle map, and reproducible baseline are recorded. No media or auth rewrite is part of this milestone.

### Milestone 1 — Stabilize the existing sidecar boundary

- Keep Electron main as the sidecar supervisor and retain the current stdio transport.
- Add contract documentation and targeted tests for framing, message bounds, request correlation, stale replies, timeout behavior, and shutdown.
- Make Electron and the Tauri runner use the same shared session services where they already should; close only demonstrated parity gaps.
- Preserve command names and payload compatibility.
- Report sidecar health and connection state only where the implementation can measure them.

**Exit:** both runner paths have known command semantics, and process failure or malformed IPC does not corrupt a newer connection attempt.

### Milestone 2 — Extract one Rust service boundary at a time

Choose one cohesive service boundary (for example auth lifecycle, catalog/profile, console discovery, or session orchestration) only after Milestone 0 identifies its current ownership.

For each extraction:

1. Add an adapter around the existing call path.
2. Move the smallest internal unit without changing its external command.
3. Add synthetic tests for success, error, cancellation, stale completion, and cleanup.
4. Compare old and new behavior for both applicable session kinds.
5. Keep the old implementation available behind a bounded fallback or feature flag until parity evidence is sufficient.
6. Remove the old path only in a later, separately reviewable change.

**Exit:** the extracted unit has a clear owner and its behavior is equivalent for covered cases. No broad cross-stack rewrite is required.

### Milestone 3 — Improve session reliability and observability

- Use attempt/generation IDs consistently across every connection mutation.
- Bound and classify retries; never retry a non-idempotent remote operation without understanding duplicate behavior.
- Expose a small local health model for auth, sidecar, signaling, peer connection, and cleanup.
- Separate requested profile settings from negotiated dimensions, codec, frame rate, and actual decoder information.
- Add diagnostics that are opt-in, reviewed before export, and contain no credentials or identifying account data by default.
- Document how users recover from a sidecar crash, network loss, app restart, and uncertain remote cleanup.

**Exit:** failure states are distinguishable and useful without making unsupported claims about Xbox service state or stream performance.

### Milestone 4 — Replace a subsystem only when evidence requires it

A replacement might be considered for a specific renderer media component, service adapter, or IPC transport only when an audit or measurement shows a concrete limitation.

Before replacing one:

- write the interface and ownership-transfer rules;
- validate Cloud Gaming and Remote Play separately;
- compare latency, CPU/GPU use, memory, compatibility, and failure recovery to the existing path;
- test on each platform claimed as supported (Windows requires native validation);
- retain the existing path until acceptance criteria pass;
- document rollback and user-data impact.

A new process, native decoder, new WebRTC stack, persistent auth store, or account migration is not an automatic roadmap item. Each requires its own evidence and design review.

## 6. Compatibility and rollout rules

- Changes should be narrow, additive, and independently reversible.
- Keep old command behavior as an adapter while migrating internal implementations.
- If a feature is risky, add an opt-in flag with the old behavior as default; remove the flag only after the replacement has a release history and platform evidence.
- Do not ship two simultaneous changes to sign-in semantics, stream setup, and cleanup.
- Do not silently migrate credentials, account data, app identity, or user-data directories.
- Keep Cloud and Remote Play acceptance checks separate, even when they share a Rust module.
- A renderer or backend crash must not claim that a remote session was stopped unless the service confirms it.
- Platform packaging configuration is not platform QA. In particular, a Windows cross-build is not native Windows validation.
- A rollback must restore source behavior without restoring credential stores or disabling security controls.

## 7. Verification and release evidence

For each change, record:

- tested commit and exact commands;
- CI result and any skipped or blocked checks;
- session kind and flow covered;
- OS, architecture, desktop/runtime, and app build where applicable;
- synthetic versus live service coverage;
- whether a test asserts local state only or confirms remote behavior;
- known gaps and rollback path.

Tests should isolate auth, stream lifecycle, IPC framing, cancellation, and cleanup with synthetic fixtures wherever possible. Live Xbox account or console tests require a human-operated test account and must not be replaced by claims based on mocks. Performance statements require measurements from the received stream and decoder path; requested bitrate, resolution, codec, and frame rate are configuration requests, not proof of negotiated output.

The solo maintainer approves merges and releases. CI or an observed run is evidence; an AI-generated claim without a visible run is not.

## 8. Open audit questions

1. What is the full command and message schema in the current Electron and Tauri runners?
2. Which auth and session state is shared, and which state is per-attempt, per-peer, or per-session kind?
3. Which WebRTC operations are renderer-owned versus initiated or completed by the Rust sidecar?
4. What remote cleanup guarantees exist for cloud sessions and Remote Play consoles?
5. Which test results in CI use only synthetic services, and which exercise a live stream?
6. What behavior differs between Linux and Windows in credential access, process launch, permissions, and packaging?
7. Is the retained Tauri runner a supported product path, a development path, or scheduled for retirement?
8. Which user-visible issue, measured latency, or reliability failure would justify replacing a media or signaling component?

## 9. Decision record

| Decision | Status |
|---|---|
| XJAUS remains independent from Aphelion and Syzygy | Invariant |
| Keep Cloud Gaming and Remote Play as separately validated flows | Invariant |
| Electron main remains the current sidecar supervisor | Accepted current boundary |
| Keep the renderer WebRTC media path during initial migration | Accepted current boundary |
| Do not send video/audio frame payloads through JSON stdio IPC | Invariant |
| Preserve current command semantics until compatibility tests exist | Invariant |
| Keep current attempt/generation guards for connection mutations | Invariant |
| Add a required breaking IPC version field immediately | Rejected |
| Extract services incrementally behind existing commands | Accepted direction |
| Replace media/WebRTC/auth persistence without evidence | Not accepted |
| Treat Windows cross-build as native platform validation | Rejected |

**Document rule:** Update this document when a decision changes. Record evidence, compatibility impact, and rollback behavior. Mark proposals as provisional until the source audit or prototype verifies them.
