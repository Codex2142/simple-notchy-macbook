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
- [x] `IslandPanel` configures `.borderless`, `.nonactivatingPanel`, `.canJoinAllSpaces`, and `.fullScreenAuxiliary`.
- [x] Hovering over the notch expands the panel smoothly; moving the cursor away collapses it after debounce.
- [x] Clicking the Pin button keeps the Island expanded until unpinned.

**Verification:**
- [x] Tests pass: `./scripts/test-macos.sh`
- [x] Build succeeds: `swift build --package-path apps/macos`

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
- [x] `cargo test --workspace` and `./scripts/test-macos.sh` pass
- [x] Floating Island window renders at notch position, expands on hover/click, and communicates with Rust `IslandCore` over UniFFI

---

## Task 7: Settings UI, Menu Bar Item & Keychain/Permission Adapters

**Description:** Implement FR-007 (Settings & Permissions): `KeychainAdapter` (macOS Security framework), `PermissionManager`, menu bar controls, and `SettingsView` persisting module toggles and retention rules to SQLite via Rust.

**Acceptance criteria:**
- [x] Toggling modules or changing retention days in Settings persists in `project_island.db`.
- [x] `KeychainAdapter` stores, retrieves, and deletes secrets in macOS Keychain.
- [x] Menu bar extra allows opening Settings, toggling Virtual Island, or quitting.

**Verification:**
- [x] Tests pass: `cargo test --workspace && ./scripts/test-macos.sh`

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
- [x] Concealed/transient items or items captured during Secure Input are rejected before persistence.
- [x] Duplicate consecutive copies update timestamp rather than duplicating rows.
- [x] Search, pin, delete, and 7-day retention pruning pass unit and SQLite integration tests.

**Verification:**
- [x] Tests pass: `cargo test --workspace`
- [x] Build succeeds: `./scripts/build-rust-macos.sh`

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
- [x] Copying text in any app updates the Island Clipboard tab when enabled.
- [x] Password manager copies (`ConcealedType`) are ignored.
- [x] Clicking an item copies it back to `NSPasteboard`; pinning protects it from retention cleanup.

**Verification:**
- [x] Tests pass: `./scripts/test-macos.sh`

**Dependencies:** Task 8

**Files likely touched:**
- `apps/macos/Sources/Integrations/PasteboardMonitor.swift`
- `apps/macos/Sources/Features/Clipboard/ClipboardTabView.swift`
- `apps/macos/Sources/App/IslandStore.swift`
- `apps/macos/Sources/App/IslandRootView.swift`

**Estimated scope:** Medium (4 files)

---

## Checkpoint 3: After Tasks 7–9
- [x] All Rust and Swift tests pass
- [x] Settings persist in `project_island.db`
- [x] Clipboard history captures, filters sensitive data, searches, and pins end-to-end

---

## Task 10: Vertical Slice — Timer, Pomodoro & Keep Awake

**Description:** Add `migrations/0003_timers.sql` (`timer_sessions`, `focus_sessions`), implement timer/Pomodoro/stopwatch state & session persistence in Rust, `KeepAwakeAdapter` (`IOPMAssertionCreateWithName`) in Swift, and the Live Activity timer pill in Collapsed/Activity Island states.

**Acceptance criteria:**
- [x] Starting a Countdown or Pomodoro transitions the Island to `Activity` state showing a live countdown pill.
- [x] Enabling Keep Awake creates a valid macOS `IOPMAssertion` and releases it cleanly on stop.
- [x] Completed sessions are recorded in `timer_sessions`.

**Verification:**
- [x] Tests pass: `cargo test --workspace && ./scripts/test-macos.sh`

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
- [x] Track changes in Apple Music or Spotify update Now Playing metadata and trigger a `Peek` transition.
- [x] Play/Pause, Next, and Previous controls dispatch to the active media player.
- [x] Unavailable players are handled gracefully.

**Verification:**
- [x] Tests pass: `cargo test --workspace && ./scripts/test-macos.sh`

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
- [x] CPU, RAM, and Battery levels render accurately in the System tab with `<1%` average idle CPU overhead.
- [x] Volume changes trigger a smooth Island `Peek` HUD.

**Verification:**
- [x] Tests pass: `cargo test --workspace && ./scripts/test-macos.sh`

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
- [x] Dragging files to the Island stores them in the File Shelf for quick drag-out or clearing.
- [x] Quick Notes and Snippets persist immediately to SQLite and survive app restarts.

**Verification:**
- [x] Tests pass: `cargo test --workspace && ./scripts/test-macos.sh`

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
- [x] GitHub Actions workflow validates both Rust and Swift build/test suites.
- [x] Architecture, Database, and Security docs match implemented schemas and FFI contracts.

**Verification:**
- [x] Tests pass: `cargo test --workspace && ./scripts/test-macos.sh`

**Dependencies:** Task 13

**Files likely touched:**
- `.github/workflows/ci.yml`
- `docs/ARCHITECTURE.md`
- `docs/DATABASE.md`
- `docs/SECURITY.md`

**Estimated scope:** Medium (4 files)

---

## Checkpoint 4: After Tasks 10–14
- [x] All Rust and Swift tests pass
- [x] All M0–M3 vertical slices verified end-to-end
- [x] Documentation and CI pipeline complete

---

## Task 15: Fix Notch Hover Oscillation & Click-Through Window (`apps/macos/Sources/Window`)

**Description:** Stop `NSPanel` frame resize thrashing during hover transitions by keeping `IslandPanel` at a stable top-centered canvas (`expandedFrame`), overriding `IslandHostingView.hitTest(_:)` so clicks outside the active pill rect pass through, and adding `NSEvent.mouseLocation` hysteresis validation in `HoverController` and `IslandWindowController`.

**Acceptance criteria:**
- [x] Hovering over the notch expands once and remains stably expanded while the cursor stays anywhere inside the expanded pill area (`expandedFrame` + 12pt hysteresis).
- [x] Spurious SwiftUI `.onHover(false)` events emitted during view layout changes are ignored when `NSEvent.mouseLocation` is still inside the active hysteresis rect.
- [x] Clicks outside the active pill rect pass through `IslandHostingView` to underlying windows/menu bar.

**Verification:**
- [x] Tests pass: `./scripts/test-macos.sh`

**Dependencies:** Task 14

**Files likely touched:**
- `apps/macos/Sources/Window/NotchDetector.swift`
- `apps/macos/Sources/Window/IslandPanel.swift`
- `apps/macos/Sources/Window/HoverController.swift`
- `apps/macos/Sources/Window/IslandWindowController.swift`
- `apps/macos/Sources/App/IslandRootView.swift`

**Estimated scope:** Medium (5 files)

---

## Task 16: Rust LRC Synced Lyrics Engine & SQLite Cache (`crates/storage`, `crates/core`, `crates/bridge`)

**Description:** Add `migrations/0006_lyrics_cache.sql`, implement `crates/core/src/lyrics.rs` to parse `.lrc` timestamped lyrics (`[mm:ss.xx]`) and compute `LyricSyncSnapshot` for any `elapsed_ms`, extend `NowPlayingTrack` with `artwork_url` and `elapsed_ms`, and expose lyrics caching/lookup over UniFFI.

**Acceptance criteria:**
- [x] `0006_lyrics_cache.sql` migrates cleanly and stores/retrieves cached LRC lyrics per `(title, artist)`.
- [x] `parse_lrc` and `sync_lyrics(lines, elapsed_ms)` accurately compute `previous_line`, `current_line`, `next_line`, and `current_index`.
- [x] `./scripts/build-rust-macos.sh` regenerates Swift bindings cleanly.

**Verification:**
- [x] Tests pass: `cargo test --workspace --offline && ./scripts/build-rust-macos.sh`

**Dependencies:** Task 15

**Files likely touched:**
- `migrations/0006_lyrics_cache.sql`
- `crates/storage/src/lib.rs`
- `crates/storage/src/repositories.rs`
- `crates/core/src/lyrics.rs`
- `crates/core/src/media.rs`
- `crates/core/src/lib.rs`
- `crates/bridge/src/lib.rs`

**Estimated scope:** Medium (7 files)

---

## Task 17: Full Spotify Integration & Live Synced Lyrics UI (`apps/macos/Sources/Integrations/MediaAdapter.swift`, `MediaPlayerView.swift`)

**Description:** Upgrade `MediaAdapter` with active AppleScript Spotify synchronization (`1.0s` poll + `250ms` smooth elapsed-time tick when playing), artwork URL, interactive seek (`set player position to ...`), auto-launch Spotify on Play, and automatic synced lyrics lookup from `lrclib.net` cached in SQLite. Update `MediaPlayerView` and `IslandRootView` to show album artwork, seek bar, full playback controls, and real-time synced lyrics in both the expanded Media view and collapsed/activity notch bar.

**Acceptance criteria:**
- [x] When Spotify is playing, `MediaAdapter` syncs track title, artist, album, artwork URL, duration, and live `elapsedMs` even if Spotify started before Project Island launched.
- [x] Play/Pause, Next, Previous, and scrubbing/clicking the progress bar control Spotify playback directly.
- [x] Live synced lyrics highlight the current line in real time based on `elapsedMs` and show a compact live lyric preview on the notch pill.

**Verification:**
- [x] Tests pass: `./scripts/test-macos.sh`

**Dependencies:** Task 16

**Files likely touched:**
- `apps/macos/Sources/Integrations/MediaAdapter.swift`
- `apps/macos/Sources/Features/Media/MediaPlayerView.swift`
- `apps/macos/Sources/App/IslandRootView.swift`

**Estimated scope:** Medium (3 files)

---

## Task 18: `.app` Bundle Packaging Script & End-to-End Verification (`scripts/package-app.sh`, `SelfTest`)

**Description:** Create `scripts/package-app.sh` to build `build/Project Island.app` with `NSAppleEventsUsageDescription` in `Info.plist`, add unit/integration tests for hover hysteresis and LRC synced lyrics in `apps/macos/Sources/SelfTest/main.swift`, and update `README.md` and `walkthrough.md`.

**Acceptance criteria:**
- [x] `./scripts/package-app.sh` produces a runnable `build/Project Island.app` bundle with `NSAppleEventsUsageDescription`.
- [x] `cargo test --workspace --offline`, `cargo clippy --workspace --all-targets --offline -- -D warnings`, and `./scripts/test-macos.sh` pass 100%.

**Verification:**
- [x] Tests pass: `cargo test --workspace --offline && ./scripts/test-macos.sh && ./scripts/package-app.sh`

**Dependencies:** Task 17

**Files likely touched:**
- `scripts/package-app.sh`
- `apps/macos/Sources/SelfTest/main.swift`
- `README.md`
- `/Users/akbarsadat/.gemini/antigravity/brain/0abeea8a-6d04-4d43-8680-a0dc159290d1/walkthrough.md`

**Estimated scope:** Medium (4 files)

---

## Task 19: Reliable Spotify Playback Integration (`IslandPanel.swift`, `MediaAdapter.swift`, `scripts/package-app.sh`)

**Description:** Fix Spotify playback buttons (`Play/Pause`, `Previous`, `Next`, `Seek`) by enabling `acceptsFirstMouse(for:)` on `IslandHostingView`, executing Spotify commands via `NSAppleScript` + `/usr/bin/osascript` + `MediaRemote.framework` (`MRMediaRemoteSendCommand`) fallback, resolving Spotify track artwork from both AppleScript and Spotify oEmbed (`Track ID`), and signing the `.app` bundle with `com.apple.security.automation.apple-events`.

**Acceptance criteria:**
- [ ] Clicking Play/Pause, Previous, or Next inside the non-activating Island panel registers immediately on first click and controls Spotify.
- [ ] UI state (`isPlaying`, `title`, `artist`, `artworkUrl`, `elapsedMs`) updates immediately after any command and stays in sync with Spotify.

**Verification:**
- [ ] Tests pass: `./scripts/test-macos.sh`

**Dependencies:** Task 18

---

## Task 20: MacBook Air M2 Notch-Aware Layout & Text Clipping Fix (`NotchDetector.swift`, `IslandRootView.swift`, `Features/*`)

**Description:** Dynamically compute `notchSafeTopInset` from `ScreenMetrics` so the physical MacBook Air M2 camera notch is never overlapped by interactive tabs (`Overview`, `Clipboard`, `Timer`, `Notes`, `Shelf`, `System`) or text in Collapsed, Activity, Peek, or Expanded modes. Fix vertical text clipping across all modes.

**Acceptance criteria:**
- [ ] In Expanded/Pinned mode, all tabs (`Overview` through `System`) sit below `notchSafeTopInset` (with a flanking header beside the physical notch) so nothing is hidden behind the MacBook Air M2 notch.
- [ ] In Collapsed and Activity modes, left and right wings flank `notchRect.width` cleanly without placing text behind the center camera cutout.
- [ ] No text is vertically clipped by 30% in Peek, Collapsed, or Expanded modes.

**Verification:**
- [ ] Tests pass: `./scripts/test-macos.sh`

**Dependencies:** Task 19

---

## Task 21: High-Precision Lyric Timestamp Sync & Smooth Slide/Fade Animation (`MediaAdapter.swift`, `MediaPlayerView.swift`)

**Description:** Replace coarse 250ms wall-clock stepping with a high-precision monotonic playback anchor (`lastAnchorElapsedMs` + `lastAnchorWallMs` + `120ms` IPC latency compensation) evaluated at `50ms` (20 Hz), and add smooth vertical slide + fade transitions between lyric lines in `MediaPlayerView.swift`.

**Acceptance criteria:**
- [ ] Lyrics transition at the exact LRC timestamp synchronized with Spotify playback position without noticeable delay.
- [ ] Line transitions animate smoothly (vertical slide + opacity fade) without flickering or blocking subsequent lyric updates.

**Verification:**
- [ ] Tests pass: `./scripts/test-macos.sh`

**Dependencies:** Task 20

---

## Task 22: Automatic 2-Second System Telemetry Refresh (`SystemMetricsAdapter.swift`, `SystemMetricsView.swift`, `ProjectIslandApp.swift`)

**Description:** Add automatic 2-second telemetry refresh in `SystemMetricsAdapter` sampling CPU usage (`HOST_CPU_LOAD_INFO` delta ticks), RAM (`HOST_VM_INFO64`), Battery (`IOPSCopyPowerSourcesInfo`), and Disk usage (`attributesOfFileSystem`), and update `SystemMetricsView` to display live auto-refreshed metrics without manual refresh buttons.

**Acceptance criteria:**
- [ ] Telemetry automatically updates every 2 seconds without manual button clicks.
- [ ] CPU, RAM, Battery, and Disk metrics are displayed cleanly and pause when the app is hidden.

**Verification:**
- [ ] Tests pass: `./scripts/test-macos.sh`

**Dependencies:** Task 21

---

## Task 23: Collapsed Island Circular Spotify Artwork & Progressive Circular Playback Border (`IslandRootView.swift`, `MediaAdapter.swift`)

**Description:** Render Spotify album artwork as a circular thumbnail on the left wing of the collapsed Island with a progressive circular border (`Circle().trim(from: 0, to: playbackProgress)`) that advances smoothly in proportion to `elapsedMs / durationMs`, pauses when playback is paused, and resets on track change.

**Acceptance criteria:**
- [ ] Circular Spotify artwork is visible on the left side of the collapsed Island.
- [ ] Circular progress ring accurately reflects `elapsedMs / durationMs`, stops when paused, and resets on new tracks.

**Verification:**
- [ ] Tests pass: `./scripts/test-macos.sh`

**Dependencies:** Task 22

---

## Task 24: End-to-End Verification & `.app` Bundle Packaging (`SelfTest/main.swift`, `scripts/package-app.sh`)

**Description:** Add automated verification for MacBook Air M2 notch safe-area layout, telemetry auto-refresh, playback progress calculation, and lyric sync in `SelfTest/main.swift`, then build and package `build/Project Island.app`.

**Acceptance criteria:**
- [ ] `cargo test --workspace --offline`, `cargo clippy --workspace --all-targets --offline -- -D warnings`, `./scripts/test-macos.sh`, and `./scripts/package-app.sh` pass 100%.
