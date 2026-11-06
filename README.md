# Project Island

Native macOS Dynamic Island productivity application built with **SwiftUI + AppKit**, **Rust**, **UniFFI**, and **SQLite**.

## Repository Structure

```text
.
├── apps/macos/              # SwiftUI + AppKit macOS application & self-test runner
│   ├── Package.swift
│   └── Sources/
│       ├── App/             # ProjectIslandApp & IslandRootView
│       ├── Window/          # NotchDetector, DisplayDetector, IslandPanel, HoverController, IslandWindowController
│       ├── Integrations/    # KeychainAdapter, PermissionManager, PasteboardMonitor, KeepAwakeAdapter, MediaAdapter, SystemMetricsAdapter
│       ├── Features/        # Clipboard, Timer, Media, System, Notes, Shelf, Settings SwiftUI views
│       └── Bridge/          # Generated UniFFI Swift bindings
├── crates/
│   ├── common/              # IslandError, AppConfig, RetentionPolicy, tracing
│   ├── storage/             # SQLite WAL pool, migrations, repositories
│   ├── core/                # AppCoordinator, EventBus, IslandStateMachine, domain logic
│   └── bridge/              # UniFFI exports & uniffi-bindgen binary
├── migrations/              # Versioned SQLite schema migrations (0001..0005)
├── scripts/
│   ├── build-rust-macos.sh  # Builds Rust staticlib/cdylib & generates Swift UniFFI bindings
│   └── test-macos.sh        # Builds ProjectIslandApp & executes IslandSelfTest
└── docs/                    # Architecture, Database, and Security documentation
```

## Build & Verify

```bash
# 1. Run Rust unit, repository, and FFI contract tests
cargo test --workspace

# 2. Build Rust bridge and generate Swift UniFFI bindings
./scripts/build-rust-macos.sh

# 3. Build ProjectIslandApp and run macOS Swift + UniFFI integration tests
./scripts/test-macos.sh
```
