# Project Island — Technical Architecture

## 1. Architectural Pattern

Project Island is a **modular monolith** with a native **SwiftUI + AppKit** presentation and macOS integration layer communicating over a typed **UniFFI** boundary with a **Rust** application core and **SQLite** storage layer.

```
apps/macos (SwiftUI + AppKit)
  ├── Window Engine (NotchDetector, DisplayDetector, IslandPanel, HoverController, IslandWindowController)
  ├── Native Integrations (KeychainAdapter, PermissionManager, PasteboardMonitor, KeepAwakeAdapter, MediaAdapter, SystemMetricsAdapter)
  └── Feature Views (IslandRootView, ClipboardTabView, TimerTabView, MediaPlayerView, SystemMetricsView, QuickNotesView, FileShelfView, SettingsView)
         │
         ▼  UniFFI Typed Boundary (crates/bridge)
crates/core (AppCoordinator, EventBus, IslandStateMachine, Clipboard, Timer, Media, System)
         │
         ▼  Repository Traits
crates/storage (SQLite WAL pool, versioned migrations 0001..0005, retention pruning)
```

## 2. Responsibility Separation

- **Swift (`apps/macos`)**:
  - Hardware notch detection (`NSScreen.safeAreaInsets`, `auxiliaryTopLeftArea`, `auxiliaryTopRightArea`) and virtual island fallback geometry.
  - Non-activating floating window (`IslandPanel: NSPanel`) with `.canJoinAllSpaces` and `.fullScreenAuxiliary`.
  - 60 FPS animations (`NSAnimationContext` + SwiftUI spring transitions).
  - Public macOS system adapters (`NSPasteboard`, `IOPMAssertion`, `DistributedNotificationCenter`, `host_statistics64`, `IOPSCopyPowerSourcesInfo`, `Security` Keychain).
- **Rust (`crates/*`)**:
  - `IslandStateMachine` enforcing all 5 Dynamic Island rules (single active state, interaction debounce, epoch-based cancellation of obsolete transitions, active-interaction lock against auto-collapse, and `Activity` priority over transient `Peek`).
  - Domain validation, privacy filtering (`ConcealedType` / `TransientType` / Secure Event Input), deduplication, and retention pruning.
  - Versioned SQLite migrations and repository implementations.
