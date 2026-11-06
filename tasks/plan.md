# Implementation Plan: Project Island

## Overview

Build **Project Island**, a native, privacy-first macOS Dynamic Island productivity application (`SwiftUI` + `AppKit` + `Rust` + `UniFFI` + `SQLite`) as specified in `PRD.md`. The application renders a non-activating floating island aligned with the MacBook hardware notch (or a top-center virtual island on non-notched displays) and delivers modular vertical slices for Media, Clipboard, Timers/Pomodoro, System HUDs, Quick Notes, and File Shelf.

## Architecture Decisions

- **Modular Monolith with Event-Driven Core:** Rust owns domain state machines, event routing, privacy filtering, retention policies, and SQLite persistence; Swift/AppKit owns window positioning, notch geometry detection, 60 FPS animations, and native macOS adapters.
- **UniFFI Language Bridge:** All communication between Swift and Rust crosses a typed UniFFI boundary (`crates/bridge`) using commands, view-state snapshots, and callback listeners. UI components never access SQLite directly.
- **Public macOS APIs Only:** Uses `NSPanel` (`.nonactivatingPanel`, `.canJoinAllSpaces`, `.fullScreenAuxiliary`), `NSScreen.safeAreaInsets` / `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`, `NSPasteboard`, `IOPMAssertion`, `CoreAudio`, `DistributedNotificationCenter`, and `Security` (Keychain).
- **Streamlined Workspace Growth:** Start with 4 focused Rust crates (`crates/common`, `crates/storage`, `crates/core`, `crates/bridge`) and grow domain modules vertically slice-by-slice.
- **macOS 13.0+ Compatibility:** Target macOS 13.0+ (`aarch64-apple-darwin`) per PRD Section 4.

## Task List

See `tasks/todo.md` for the detailed task breakdown, acceptance criteria, verification commands, and checkpoints.

### Phase 1: M0 Foundation (Workspace, Storage, Core & State Machine)
- [x] Task 0: Initialize `tasks/plan.md` and `tasks/todo.md`
- [x] Task 1: Bootstrap Cargo Workspace & `crates/common`
- [x] Task 2: SQLite Storage Engine & Initial Migration (`crates/storage`)
- [x] Task 3: Rust Application Core, EventBus & Island State Machine (`crates/core`)
- [x] Checkpoint 1: Rust Core & Storage Foundation

### Phase 2: UniFFI Bridge & M1 Dynamic Island Engine (`apps/macos`)
- [x] Task 4: UniFFI Bridge Crate & Swift Binding Generator (`crates/bridge`)
- [x] Task 5: Swift Package & Notch/Display Geometry Detector (`apps/macos`)
- [x] Task 6: Floating `IslandPanel`, Hover/Gesture Controllers & 60 FPS Shell UI
- [x] Checkpoint 2: End-to-End Dynamic Island Shell

### Phase 3: M2 Application Core (Settings, Permissions & Keychain)
- [x] Task 7: Settings UI, Menu Bar Item & Keychain/Permission Adapters

### Phase 4: M3 Core Feature Vertical Slices
- [ ] Task 8: Vertical Slice — Clipboard Manager Backend
- [ ] Task 9: Vertical Slice — macOS Pasteboard Monitor & Island Clipboard UI
- [ ] Checkpoint 3: Settings + Clipboard End-to-End
- [ ] Task 10: Vertical Slice — Timer, Pomodoro & Keep Awake
- [ ] Task 11: Vertical Slice — Media Now Playing & Playback Controls
- [ ] Task 12: Vertical Slice — System Monitoring & Battery/Volume HUDs
- [ ] Task 13: Vertical Slice — Quick Notes & Drag-to-Notch File Shelf
- [ ] Task 14: CI/CD Workflow & Core Architecture Documentation
- [ ] Checkpoint 4: M0–M3 Complete & Verified

## Risks and Mitigations

| Risk | Impact | Mitigation |
| :--- | :--- | :--- |
| UniFFI version mismatch between crate and bindgen CLI | High | Build workspace-local `uniffi-bindgen` binary inside `crates/bridge/src/bin/uniffi-bindgen.rs` |
| `NSPanel` stealing focus or failing in Fullscreen | High | Use `.nonactivatingPanel` style mask and `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]` |
| Idle CPU exceeding `<1%` target | High | Suspend active polling while Island is collapsed; use event-driven macOS notifications |
| Capturing sensitive passwords in Clipboard | High | Filter `ConcealedType`, `TransientType`, and `IsSecureEventInputEnabled()` before persistence |
