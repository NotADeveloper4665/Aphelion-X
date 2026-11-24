# Aphelion-Inspired Architecture Plan for XJAUS

**Status:** Incremental plan; first health-contract slice implemented, validation pending
**Scope:** XJAUS Xbox streaming client, with the KDE shell and Electron shell sharing the Rust service
**Guiding rule:** Adapt Aphelion's ownership, contract, evidence, and rollout principles to a client. Do not transplant host-side capture or encoder architecture.

## Current architecture and constraints

XJAUS already has a Rust backend process that owns Xbox credentials, auth generations, API operations, stream-session handles, cancellation, and cleanup. Electron and the KDE shell are clients of that service. The shared web player owns browser/WebRTC playback and input. The service exposes bounded request handling and a versioned IPC envelope; requests without a version remain accepted for compatibility.

Before this plan's first slice, the Rust `backend_status` command reported static service metadata and a list of implemented command families, but not current authentication, stream lifecycle, or uncertain cleanup. The KDE shell uses this command to display service health. The first slice adds operational state without changing the existing response fields or moving media ownership.

Aphelion's founding architecture is a plan for a Linux streaming **host**. Its capture, encoder, worker, and media-plane boundaries do not map directly onto an Xbox streaming **client**. XJAUS should adopt only the parts that solve client problems.

## Decisions

1. **Keep Rust as the sole owner of credentials and Xbox session handles.** UI shells may display state but must not create a competing session owner.
2. **Keep WebRTC playback in the shared player runtime.** The Rust process controls and negotiates the remote session; the player handles browser media, rendering, and input.
3. **Keep one backend process per app instance.** Do not add a supervisor/worker tree or a separate media process without measured reliability, privilege, or performance evidence.
4. **Keep one versioned, bounded control contract across shells.** Add fields compatibly; do not make a version mandatory until every supported caller sends it.
5. **Health values must come from live state.** Distinguish service readiness, authentication, stream lifecycle, and cleanup. Do not infer decoder/network health from backend readiness or report unavailable measurements as zero.
6. **Roll out by small slices.** Preserve the Electron fallback and existing stream path while the KDE shell and each contract change are validated.

## Work plan

### Slice 1 — Report truthful backend health (implemented; validation pending)

Add an additive `health` object to `backend_status` with:

- service readiness;
- signed-in versus signed-out state;
- current backend-owned session lifecycle state, or `idle` when there is no session;
- cleanup state (`clear`, `pending`, or `uncertain`) and the count of pending detached cleanup operations.

Keep existing fields (`ready`, `version`, `platform`, `apiVersion`, and `capabilities`) unchanged. Do not expose credentials, Xbox session identifiers, or account tokens. Update the architecture contract so shells know exactly what the values mean.

**Acceptance:** Existing consumers can continue reading all current fields. Health distinguishes backend readiness from sign-in and stream state. Cleanup uncertainty blocks unsafe new sessions as it does today.

### Slice 2 — Make the shared contract explicit

Document request/response envelopes, compatibility behavior for missing and unknown API versions, error shape, request identifiers, payload limits, and which layer owns each state. Add typed client-side status definitions and narrow command wrappers where that reduces shell drift. Preserve the current envelope and command names.

**Acceptance:** Electron and KDE can use the same documented contract; older callers continue to work during rollout; no secret-bearing data is added to shell-facing status.

### Slice 3 — Align lifecycle and cancellation reporting

Trace begin, start, provisioning, negotiation, connected, cancel, stop, logout, and late-response cleanup through both shells. Keep backend-issued generations authoritative. Fix only demonstrated differences or stale-state gaps, and ensure a shell closing cannot silently leave an owned request untracked.

**Acceptance:** A cancelled or superseded attempt cannot adopt a late response; logout invalidates owned work; both shells show lifecycle states from the same backend source where available.

### Slice 4 — Add honest player diagnostics

Expose player-side WebRTC facts separately from backend health: connection state, selected candidate type when available, decoded/rendered frame counters and measured timing only when the Web API provides them. Mark unsupported metrics unavailable. No telemetry upload by default.

**Acceptance:** A local diagnostics view can distinguish backend, signaling, transport, and playback failures without inventing host-side measurements.

### Slice 5 — Improve process recovery only where justified

Observe Electron and KDE sidecar crash behavior, pending request failure, shutdown, and restart on supported systems. If evidence supports it, add bounded restart/backoff at the shell's existing process boundary, with duplicate-start protection and clear user-visible recovery state. Do not restart during shutdown or revive a stream silently.

**Acceptance:** Crash recovery is bounded, observable, and tested for both shells; explicit exit remains final; no duplicate backend or session is created.

## Explicitly out of scope

- Aphelion's capture broker, Thick Worker, encoder workers, Moonlight host protocol stack, or host-side frame queues.
- Moving WebRTC, rendering, or controller input from the browser player into Rust.
- Splitting video/audio payloads across IPC or introducing shared memory, DMA-BUF, or zero-copy paths.
- Rewriting the Xbox protocol/session implementation or changing authentication behavior as part of the shell migration.
- Removing Electron/Windows support as a prerequisite for Linux improvements.

## Rollout and rollback

Each slice should be a small reviewable change with the old path retained until the new path is observed working. Contract additions are additive first. KDE remains the Linux target while Electron packaging stays available as an explicit rollback. Windows continues using Electron and the shared Rust backend. If a slice breaks startup, sign-in, stream launch, cancellation, or shutdown, revert that slice without reverting unrelated UI work.

## Progress

- [x] Confirm current Rust service ownership, bounded IPC, and attempt generations from source.
- [x] Add live service/auth/session/cleanup health to `backend_status` without removing existing fields.
- [x] Document the health field semantics in the architecture overview.
- [x] Show the additive health fields in the KDE backend status line; older responses degrade to `unknown` values.
- [ ] Define validation and rollout evidence for the health contract.
- [ ] Trace cross-shell stream lifecycle and identify concrete gaps before changing it.
- [ ] Design player diagnostics from metrics actually exposed by the WebRTC runtime.
- [ ] Assess bounded sidecar recovery after observing process failure behavior.
