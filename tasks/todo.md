# Project Island — Task List (`tasks/todo.md`)

## Task 0: Initialize Planning Artifacts (`tasks/plan.md` & `tasks/todo.md`)

**Description:** Persist the approved implementation plan to `tasks/plan.md` and the ordered task checklist to `tasks/todo.md`.

**Acceptance criteria:**
- [x] `tasks/plan.md` exists and contains architecture decisions, task index, and risk matrix.
- [x] `tasks/todo.md` exists and contains all tasks and checkpoints in checklist format.

**Verification:**
- [x] Manual check: `ls -la tasks/plan.md tasks/todo.md`

**Dependencies:** None

**Files likely touched:**
- `tasks/plan.md`
- `tasks/todo.md`

**Estimated scope:** Small (2 files)

---

## Task 1: Bootstrap Cargo Workspace & `crates/common`

**Description:** Ensure the Rust toolchain is available, initialize `.gitignore`, and create the root `Cargo.toml` and `crates/common` with typed `IslandError`, `AppConfig`, and structured `tracing` setup.

**Acceptance criteria:**
- [x] `cargo check` and `cargo test -p island-common` pass with zero warnings.
- [x] `IslandError` covers storage, validation, permission, and FFI error variants.
- [x] `tracing` subscriber supports configurable log level and initialization.

**Verification:**
- [x] Tests pass: `cargo test -p island-common`
- [x] Build succeeds: `cargo check --workspace`

**Dependencies:** Task 0

**Files likely touched:**
- `.gitignore`
- `Cargo.toml`
- `crates/common/Cargo.toml`
- `crates/common/src/lib.rs`

**Estimated scope:** Medium (4 files)

---

## Task 2: SQLite Storage Engine & Initial Migration (`crates/storage`)

**Description:** Implement `crates/storage` using `rusqlite` (bundled SQLite), a versioned SQL migration runner loading `migrations/0001_initial_schema.sql`, and repositories for `app_settings`, `display_profiles`, and `module_settings` plus configurable retention pruning.

**Acceptance criteria:**
- [x] In-memory and file-backed SQLite databases apply `0001_initial_schema.sql` idempotently.
- [x] Settings and display profile CRUD operations pass integration tests.
- [x] Retention policy configuration is stored and retrievable.

**Verification:**
- [x] Tests pass: `cargo test -p island-storage`
- [x] Build succeeds: `cargo build -p island-storage`

**Dependencies:** Task 1

**Files likely touched:**
- `migrations/0001_initial_schema.sql`
- `crates/storage/Cargo.toml`
- `crates/storage/src/lib.rs`
- `crates/storage/src/repositories.rs`

**Estimated scope:** Medium (4 files)

---

## Task 3: Rust Application Core, EventBus & Island State Machine (`crates/core`)

**Description:** Implement `crates/core` with a typed `EventBus`, `IslandStateController` enforcing PRD Section 6 state rules (single active state, `Activity` vs `Peek` priority, interaction lock preventing auto-collapse), and `AppCoordinator`.

**Acceptance criteria:**
- [x] State machine transitions (`Hidden`, `Collapsed`, `Peek`, `Expanded`, `Activity`, `Pinned`) enforce PRD Section 6 rules.
- [x] Repeated hover/peek requests are debounced and obsolete transitions are canceled safely.
- [x] Unit tests verify all state rules and `AppCoordinator` settings integration.

**Verification:**
- [x] Tests pass: `cargo test -p island-core`
- [x] Build succeeds: `cargo build -p island-core`

**Dependencies:** Task 2

**Files likely touched:**
- `crates/core/Cargo.toml`
- `crates/core/src/lib.rs`
- `crates/core/src/state_machine.rs`
- `crates/core/src/event_bus.rs`

**Estimated scope:** Medium (4 files)

---

## Checkpoint 1: After Tasks 0–3
- [x] All tests pass (`cargo test --workspace`)
- [x] Application workspace builds without warnings (`cargo clippy --workspace -- -D warnings`)
- [x] Core SQLite migrations and state machine transitions work end-to-end

---

## Task 4: UniFFI Bridge Crate & Swift Binding Generator (`crates/bridge`)

**Description:** Create `crates/bridge` exposing `IslandCore` FFI object, typed commands, view state snapshots, and callback listener interface. Add `scripts/build-rust-macos.sh` to generate Swift bindings into `apps/macos/Sources/Bridge/Generated`.

**Acceptance criteria:**
- [x] `crates/bridge` compiles as `staticlib` and `cdylib`.
- [x] `scripts/build-rust-macos.sh` generates Swift bindings and C header/modulemap cleanly.
- [x] Rust FFI contract tests verify round-trip command dispatch and event listener callbacks.

**Verification:**
- [x] Tests pass: `cargo test -p island-bridge`
- [x] Build succeeds: `./scripts/build-rust-macos.sh`

**Dependencies:** Task 3

**Files likely touched:**
- `crates/bridge/Cargo.toml`
- `crates/bridge/src/lib.rs`
- `crates/bridge/src/bin/uniffi-bindgen.rs`
- `scripts/build-rust-macos.sh`

**Estimated scope:** Medium (4 files)

---

## Task 5: Swift Package & Notch/Display Geometry Detector (`apps/macos`)

**Description:** Create `apps/macos/Package.swift` linking the Rust static library, and implement `NotchDetector` and `DisplayDetector` using `NSScreen` safe area and auxiliary top areas to compute hardware notch and virtual island geometry across multi-display setups.

**Acceptance criteria:**
- [x] `NotchDetector` accurately computes notch rect on notched Macs and virtual island rect on non-notched displays.
- [x] `DisplayDetector` observes screen parameter changes and maps display UUIDs.
- [x] Swift unit tests verify geometry math for notched and non-notched screen metrics plus Rust FFI bridge connectivity.

**Verification:**
- [x] Tests pass: `./scripts/test-macos.sh`
- [x] Build succeeds: `swift build --package-path apps/macos`

**Dependencies:** Task 4

**Files likely touched:**
- `apps/macos/Package.swift`
- `apps/macos/Sources/Window/NotchDetector.swift`
- `apps/macos/Sources/Window/DisplayDetector.swift`
- `apps/macos/Tests/WindowTests/NotchDetectorTests.swift`

**Estimated scope:** Medium (4 files)

---

## Task 6: Floating `IslandPanel`, Hover/Gesture Controllers & 60 FPS Shell UI

**Description:** Implement `IslandPanel` (`NSPanel` subclass with non-activating, status-bar-level, all-spaces behavior), `IslandWindowController`, `HoverController`, and the SwiftUI `IslandRootView` connected to `IslandCore` via UniFFI.

**Acceptance criteria:**
- [ ] `IslandPanel` configures `.borderless`, `.nonactivatingPanel`, `.canJoinAllSpaces`, and `.fullScreenAuxiliary`.
- [ ] Hovering over the notch expands the panel smoothly; moving the cursor away collapses it after debounce.
- [ ] Clicking the Pin button keeps the Island expanded until unpinned.

**Verification:**
- [ ] Tests pass: `swift test --package-path apps/macos`
- [ ] Build succeeds: `swift build --package-path apps/macos`

**Dependencies:** Task 5

**Files likely touched:**
- `apps/macos/Sources/Window/IslandPanel.swift`
- `apps/macos/Sources/Window/IslandWindowController.swift`
- `apps/macos/Sources/Window/HoverController.swift`
- `apps/macos/Sources/App/IslandRootView.swift`
- `apps/macos/Sources/App/ProjectIslandApp.swift`

**Estimated scope:** Medium (5 files)

---

## Checkpoint 2: After Tasks 4–6
- [ ] `cargo test --workspace` and `swift test --package-path apps/macos` pass
- [ ] Floating Island window renders at notch position, expands on hover/click, and communicates with Rust `IslandCore` over UniFFI

---

## Task 7: Settings UI, Menu Bar Item & Keychain/Permission Adapters

**Description:** Implement FR-007 (Settings & Permissions): `KeychainAdapter` (macOS Security framework), `PermissionManager`, menu bar controls, and `SettingsView` persisting module toggles and retention rules to SQLite via Rust.

**Acceptance criteria:**
- [ ] Toggling modules or changing retention days in Settings persists in `project_island.db`.
- [ ] `KeychainAdapter` stores, retrieves, and deletes secrets in macOS Keychain.
- [ ] Menu bar extra allows opening Settings, toggling Virtual Island, or quitting.

**Verification:**
- [ ] Tests pass: `cargo test --workspace && swift test --package-path apps/macos`

**Dependencies:** Task 6

**Files likely touched:**
- `apps/macos/Sources/Integrations/KeychainAdapter.swift`
- `apps/macos/Sources/Integrations/PermissionManager.swift`
- `apps/macos/Sources/Features/Settings/SettingsView.swift`
- `crates/core/src/settings.rs`
- `crates/bridge/src/lib.rs`

**Estimated scope:** Medium (5 files)

---

## Task 8: Vertical Slice — Clipboard Manager Backend

**Description:** Add `migrations/0002_clipboard.sql` (`clipboard_items`, `clipboard_pins`) and implement clipboard capture validation, privacy filtering (concealed/transient markers, secure input flag), search, pinning, and retention pruning in Rust.

**Acceptance criteria:**
- [ ] Concealed/transient items or items captured during Secure Input are rejected before persistence.
- [ ] Duplicate consecutive copies update timestamp rather than duplicating rows.
- [ ] Search, pin, delete, and 7-day retention pruning pass unit and SQLite integration tests.

**Verification:**
- [ ] Tests pass: `cargo test --workspace`
- [ ] Build succeeds: `./scripts/build-rust-macos.sh`

**Dependencies:** Task 7

**Files likely touched:**
- `migrations/0002_clipboard.sql`
- `crates/core/src/clipboard.rs`
- `crates/storage/src/clipboard_repo.rs`
- `crates/bridge/src/lib.rs`

**Estimated scope:** Medium (4 files)

---

## Task 9: Vertical Slice — macOS Pasteboard Monitor & Island Clipboard UI

**Description:** Implement `PasteboardMonitor` (`NSPasteboard.general.changeCount` + `IsSecureEventInputEnabled()` check) and `ClipboardTabView` inside the expanded Island for searching, pinning, copying back, and deleting clipboard items.

**Acceptance criteria:**
- [ ] Copying text in any app updates the Island Clipboard tab when enabled.
- [ ] Password manager copies (`ConcealedType`) are ignored.
- [ ] Clicking an item copies it back to `NSPasteboard`; pinning protects it from retention cleanup.

**Verification:**
- [ ] Tests pass: `swift test --package-path apps/macos`

**Dependencies:** Task 8

**Files likely touched:**
- `apps/macos/Sources/Integrations/PasteboardMonitor.swift`
- `apps/macos/Sources/Features/Clipboard/ClipboardTabView.swift`
- `apps/macos/Sources/App/IslandStore.swift`
- `apps/macos/Sources/App/IslandRootView.swift`

**Estimated scope:** Medium (4 files)

---

## Checkpoint 3: After Tasks 7–9
- [ ] All Rust and Swift tests pass
- [ ] Settings persist in `project_island.db`
- [ ] Clipboard history captures, filters sensitive data, searches, and pins end-to-end

---

## Task 10: Vertical Slice — Timer, Pomodoro & Keep Awake

**Description:** Add `migrations/0003_timers.sql` (`timer_sessions`, `focus_sessions`), implement timer/Pomodoro/stopwatch state & session persistence in Rust, `KeepAwakeAdapter` (`IOPMAssertionCreateWithName`) in Swift, and the Live Activity timer pill in Collapsed/Activity Island states.

**Acceptance criteria:**
- [ ] Starting a Countdown or Pomodoro transitions the Island to `Activity` state showing a live countdown pill.
- [ ] Enabling Keep Awake creates a valid macOS `IOPMAssertion` and releases it cleanly on stop.
- [ ] Completed sessions are recorded in `timer_sessions`.

**Verification:**
- [ ] Tests pass: `cargo test --workspace && swift test --package-path apps/macos`

**Dependencies:** Task 9

**Files likely touched:**
- `migrations/0003_timers.sql`
- `crates/core/src/timer.rs`
- `apps/macos/Sources/Integrations/KeepAwakeAdapter.swift`
- `apps/macos/Sources/Features/Timer/TimerTabView.swift`
- `apps/macos/Sources/Features/Timer/ActivityPillView.swift`

**Estimated scope:** Medium (5 files)

---

## Task 11: Vertical Slice — Media Now Playing & Playback Controls

**Description:** Add `migrations/0004_media.sql`, implement media state normalization in Rust, `MediaAdapter` in Swift using `DistributedNotificationCenter` (`com.apple.Music.playerInfo`, `com.spotify.client.PlaybackStateChanged`) and AppleScript playback commands, and render the Now Playing Peek/Expanded view.

**Acceptance criteria:**
- [ ] Track changes in Apple Music or Spotify update Now Playing metadata and trigger a `Peek` transition.
- [ ] Play/Pause, Next, and Previous controls dispatch to the active media player.
- [ ] Unavailable players are handled gracefully.

**Verification:**
- [ ] Tests pass: `cargo test --workspace && swift test --package-path apps/macos`

**Dependencies:** Task 10

**Files likely touched:**
- `migrations/0004_media.sql`
- `crates/core/src/media.rs`
- `apps/macos/Sources/Integrations/MediaAdapter.swift`
- `apps/macos/Sources/Features/Media/MediaPlayerView.swift`

**Estimated scope:** Medium (4 files)

---

## Task 12: Vertical Slice — System Monitoring & Battery/Volume HUDs

**Description:** Implement efficient system telemetry in `SystemMetricsAdapter` (`host_statistics64` CPU/RAM, `IOPSCopyPowerSourcesInfo` battery, `CoreAudio` output volume listener) feeding Rust threshold filters and rendering System HUD Peeks and telemetry gauges in the Island.

**Acceptance criteria:**
- [ ] CPU, RAM, and Battery levels render accurately in the System tab with `<1%` average idle CPU overhead.
- [ ] Volume changes trigger a smooth Island `Peek` HUD.

**Verification:**
- [ ] Tests pass: `cargo test --workspace && swift test --package-path apps/macos`

**Dependencies:** Task 11

**Files likely touched:**
- `crates/core/src/system.rs`
- `apps/macos/Sources/Integrations/SystemMetricsAdapter.swift`
- `apps/macos/Sources/Features/System/SystemHudView.swift`
- `apps/macos/Sources/Features/System/SystemMetricsView.swift`

**Estimated scope:** Medium (4 files)

---

## Task 13: Vertical Slice — Quick Notes & Drag-to-Notch File Shelf

**Description:** Add `migrations/0005_notes_shelf.sql` (`notes`, `snippets`, `activity_events`), implement CRUD in Rust, and build `QuickNotesView` and drag-to-notch `FileShelfView`.

**Acceptance criteria:**
- [ ] Dragging files to the Island stores them in the File Shelf for quick drag-out or clearing.
- [ ] Quick Notes and Snippets persist immediately to SQLite and survive app restarts.

**Verification:**
- [ ] Tests pass: `cargo test --workspace && swift test --package-path apps/macos`

**Dependencies:** Task 12

**Files likely touched:**
- `migrations/0005_notes_shelf.sql`
- `crates/core/src/notes_shelf.rs`
- `apps/macos/Sources/Features/Notes/QuickNotesView.swift`
- `apps/macos/Sources/Features/Shelf/FileShelfView.swift`

**Estimated scope:** Medium (4 files)

---

## Task 14: CI/CD Workflow & Core Architecture Documentation

**Description:** Create `.github/workflows/ci.yml` to run `cargo test`, `cargo clippy`, and `swift test` on macOS runners, and generate `docs/ARCHITECTURE.md`, `docs/DATABASE.md`, and `docs/SECURITY.md`.

**Acceptance criteria:**
- [ ] GitHub Actions workflow validates both Rust and Swift build/test suites.
- [ ] Architecture, Database, and Security docs match implemented schemas and FFI contracts.

**Verification:**
- [ ] Tests pass: `cargo test --workspace && swift test --package-path apps/macos`

**Dependencies:** Task 13

**Files likely touched:**
- `.github/workflows/ci.yml`
- `docs/ARCHITECTURE.md`
- `docs/DATABASE.md`
- `docs/SECURITY.md`

**Estimated scope:** Medium (4 files)

---

## Checkpoint 4: After Tasks 10–14
- [ ] All Rust and Swift tests pass
- [ ] All M0–M3 vertical slices verified end-to-end
- [ ] Documentation and CI pipeline complete
