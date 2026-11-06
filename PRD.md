# Project Island

## Product Requirements Document & Technical Architecture

**Version:** 1.0  
**Status:** Proposed / Development Planning  
**Platform:** macOS  
**UI:** SwiftUI + AppKit  
**Core:** Rust  
**Bridge:** UniFFI  
**Database:** SQLite

---

# 1. Product Overview

Project Island is an independently developed native macOS application that transforms the MacBook notch or a configurable screen area into an interactive productivity interface.

The application centralizes media controls, clipboard management, productivity tools, system monitoring, notifications, and developer utilities.

The product is independently designed and implemented. Existing commercial applications are used only as references for user-facing capabilities and behavior, not as sources of proprietary code or assets.

## Vision

Create a lightweight, modular, privacy-first Dynamic Island experience for macOS.

## Objectives

1. Provide quick access to frequently used macOS utilities.
2. Build a responsive floating island interface.
3. Reduce application switching.
4. Use native macOS frameworks wherever possible.
5. Keep local features functional without internet.
6. Maintain modular and replaceable software components.
7. Give the project owner control over source code, branding, and distribution.

# 2. Product Scope

The product includes 12 feature domains:

1. Dynamic Island Engine
2. Media & Audio
3. Clipboard & File Management
4. Productivity & Focus
5. System HUD & Monitoring
6. Window Management
7. Developer Tools
8. Search & Utility
9. Camera & Communication
10. Notification & Live Activities
11. Desktop & Lock Screen
12. Customization & Security

## Feature Backlog

### Dynamic Island

- Notch detection
- Collapsed and expanded states
- Hover and click interaction
- Swipe gestures
- Auto-collapse
- Multi-display support
- Virtual island
- Fullscreen behavior
- Custom sizing and themes
- Menu bar detach

### Media & Audio

- Now Playing
- Playback controls
- Album artwork
- Playback progress
- Shuffle and repeat
- Favorites
- Synced lyrics
- Audio output switching
- Device battery information
- Application volume
- Equalizer
- Browser media integration

### Clipboard & Files

- Clipboard history
- Search and pin
- Smart actions
- OCR
- Image search
- Text snippets
- File shelf
- Drag and drop
- Image conversion
- ZIP and UNZIP
- AirDrop handoff

### Productivity

- Pomodoro
- Countdown
- Stopwatch
- Focus sessions
- Keep Awake
- Quick Notes
- Calendar
- Reminders
- Focus awareness
- Activity tracking
- Teleprompter

### System

- Volume HUD
- Brightness HUD
- Battery HUD
- CPU and RAM
- Disk and network monitoring
- Device battery
- Microphone mute
- Caps Lock HUD
- Keyboard cleaning lock
- Keyboard backlight
- External display brightness
- Privacy indicators

### Window Management

- Window snapping
- Split layouts
- Custom snapping zones
- Drag-to-notch interaction

### Developer Tools

- AI usage tracking
- Claude Code integration
- Codex integration
- Cursor integration
- GitHub PR counter
- Agent approval notifications
- Shell activity
- Notch Terminal
- Command Palette
- Local Developer API

### Search & Utility

- Universal search
- Search engine shortcuts
- Quick calculations
- Translation
- Color eyedropper
- QR utilities
- Weather
- Stocks
- Download notifications
- App launcher
- Apple Shortcuts

### Communication & Extended Features

- Camera mirror
- Incoming call notifications
- Message notifications
- Notification mirror
- Desktop widgets
- Lock Screen research
- Advanced customization

Features requiring private macOS APIs, unauthorized access, or unsupported security workarounds must be excluded or redesigned using supported APIs.

# 3. Functional Requirements

**FR-001: Island Engine**

- Detect display dimensions and notch information.
- Support collapsed and expanded states.
- Support hover, click, and keyboard interaction.
- Support multiple displays.
- Handle fullscreen and Spaces configurations.
- Provide configurable appearance.

**FR-002: Media**

- Display available playback information.
- Show artwork and metadata.
- Provide supported playback controls.
- Handle media source changes.

**FR-003: Clipboard**

- Capture clipboard changes with user consent.
- Store history locally.
- Support search, pin, and deletion.
- Enforce retention policies.
- Exclude sensitive content where detectable.

**FR-004: Productivity**

- Support timers, stopwatch, and Pomodoro.
- Store session history.
- Provide notifications.
- Support timed Keep Awake.

**FR-005: System Monitoring**

- Display CPU, RAM, disk, network, and battery information.
- Use efficient monitoring intervals.
- Avoid excessive background polling.

**FR-006: Developer Integration**

- Support approved local hooks and integrations.
- Provide authenticated localhost API.
- Protect credentials.
- Handle unavailable providers gracefully.

**FR-007: Settings**

- Module configuration.
- Keyboard shortcuts.
- Display preferences.
- Permission management.
- Data retention.
- Startup configuration.
- Update preferences.

# 4. Non-functional Requirements

| Requirement          | Initial target                    |
| -------------------- | --------------------------------- |
| Platform             | macOS 13+                         |
| Primary architecture | Apple Silicon ARM64               |
| Idle CPU             | <1% average                       |
| Idle RAM             | <150 MB                           |
| Startup              | <2 seconds                        |
| UI response          | <100 ms for simple local actions  |
| Animation            | 60 FPS target                     |
| Offline operation    | All local core features           |
| Database             | SQLite                            |
| Security             | Least privilege                   |
| Testing              | Unit, integration, UI, regression |

These values are engineering targets and must be verified through benchmarking.

# 5. Technical Architecture

## Architecture Decisions

| Component           | Technology          |
| ------------------- | ------------------- |
| UI                  | SwiftUI             |
| Window management   | AppKit              |
| Native integration  | Swift               |
| Core business logic | Rust                |
| Language bridge     | UniFFI              |
| Database            | SQLite              |
| Configuration       | JSON/TOML           |
| Credentials         | macOS Keychain      |
| Logging             | Tracing             |
| Testing             | XCTest + Cargo Test |
| CI/CD               | GitHub Actions      |

## Architecture Pattern

Modular monolith with domain-based modules and event-driven communication.

### Presentation Layer

- Island UI
- Expanded panel
- Settings UI
- Menu bar UI
- Onboarding
- Widget UI

### Application Core

- Application coordinator
- Event bus
- State management
- Module registry
- Domain services

### Domain Modules

- Media
- Clipboard
- Timer
- Productivity
- System
- Developer
- Notifications
- Search

### Infrastructure

- SQLite
- Filesystem
- Keychain
- macOS adapters
- Logging
- Local API

## Responsibility Separation

Swift:

- UI rendering
- Floating windows
- Display detection
- macOS framework integration
- Native notifications
- Permission handling

Rust:

- Business logic
- Domain services
- Event processing
- Data validation
- Repository interfaces
- Persistence logic
- Local API
- Search and aggregation

## Communication

Swift and Rust communicate through UniFFI-generated bindings.

Use typed commands, responses, events, and errors.

Do not allow UI components to directly manipulate database connections or domain internals.

# 6. Dynamic Island Engine

Main components:

- IslandWindowController
- DisplayDetector
- NotchDetector
- WindowPositionManager
- WindowLevelManager
- IslandStateController
- HoverController
- GestureController
- AnimationCoordinator

Supported states:

- Hidden
- Collapsed
- Peek
- Expanded
- Activity
- Pinned
- Transitioning

Rules:

1. Only one primary state can be active.
2. Debounce repeated interactions.
3. Cancel obsolete transitions safely.
4. Do not auto-collapse during active interaction.
5. Prioritize important activities over previews.

Use public AppKit APIs such as NSWindow, NSPanel, NSScreen, and NSWindow.CollectionBehavior.

# 7. Database Architecture

Database: `project_island.db`

Initial tables:

- app_settings
- display_profiles
- module_settings
- clipboard_items
- clipboard_pins
- timer_sessions
- focus_sessions
- notes
- snippets
- notification_history
- media_preferences
- activity_events
- developer_integrations

Use repository interfaces to isolate database implementation.

Default retention:

- Clipboard: 7 days
- Pinned clipboard: until deleted
- Timer history: 90 days
- Activity events: 7 days
- Notes: until deleted
- Logs: 7 days

All retention policies must be configurable.

# 8. Security & Privacy

Principles:

- Local-first.
- Least privilege.
- No plaintext credentials.
- Keychain for tokens and API keys.
- Explicit permission onboarding.
- Clipboard privacy filtering.
- Secure input awareness.
- No telemetry by default.
- No unauthorized screen capture.
- Authenticated localhost API.
- No private API dependency.

Permissions must be requested only when a feature requires them.

# 9. Repository Structure

```text
project-island/
├── apps/
│   └── macos/
│       ├── Sources/
│       │   ├── App/
│       │   ├── Window/
│       │   ├── Features/
│       │   ├── Integrations/
│       │   └── Bridge/
│       ├── Resources/
│       └── Tests/
├── crates/
│   ├── core/
│   ├── domain/
│   ├── event-bus/
│   ├── bridge/
│   ├── storage/
│   ├── media/
│   ├── clipboard/
│   ├── timer/
│   ├── productivity/
│   ├── system/
│   ├── developer/
│   ├── notifications/
│   └── common/
├── extensions/
│   └── widgets/
├── migrations/
├── docs/
│   ├── PRD.md
│   ├── ARCHITECTURE.md
│   ├── DATABASE.md
│   ├── SECURITY.md
│   ├── FEATURES.md
│   ├── ROADMAP.md
│   └── ADR/
├── scripts/
├── .github/
│   └── workflows/
├── Cargo.toml
├── Cargo.lock
├── README.md
├── LICENSE
└── .gitignore
```

# 10. Testing Strategy

Testing layers:

1. Rust unit tests.
2. Repository integration tests.
3. FFI contract tests.
4. Swift unit tests.
5. SwiftUI UI tests.
6. AppKit integration tests.
7. End-to-end tests.
8. Performance benchmarks.

Important test scenarios:

- Display changes.
- Monitor connection/disconnection.
- Sleep and wake.
- Fullscreen transitions.
- Clipboard retention.
- Media source changes.
- Permission denial.
- Database migration.
- Application relaunch.

# 11. Development Roadmap

**M0 — Foundation**

- GitHub setup
- Xcode project
- Rust workspace
- UniFFI
- CI
- Logging
- Error handling

**M1 — Dynamic Island Engine**

- Floating window
- Notch detection
- Display positioning
- State management
- Hover and click
- Animation

**M2 — Application Core**

- Event bus
- SQLite
- Repositories
- Settings
- Permission manager

**M3 — Core Features**

- Media
- Clipboard
- Timer
- Battery
- System monitoring
- Notes
- File Shelf

**M4 — Productivity**

- Pomodoro
- Focus
- Calendar
- Reminders
- Search
- App launcher

**M5 — Advanced System**

- Window snapping
- OCR
- Audio controls
- Image conversion
- Camera
- Keyboard utilities

**M6 — Developer Ecosystem**

- AI usage
- GitHub
- Claude Code
- Codex
- Shell activity
- Local API
- Command Palette

**M7 — Extended Features**

- Widgets
- Communication
- Advanced customization
- Additional integrations

**M8 — Production**

- Optimization
- Security audit
- Regression tests
- Signing
- Notarization
- DMG
- Auto-update

# 12. Ownership and Licensing

The repository must be controlled by the project owner.

Original source code, design, documentation, and branding are developed independently.

Third-party libraries remain subject to their respective licenses.

Recommended initial arrangement:

- Private GitHub repository.
- Proprietary development during initial implementation.
- Final open-source or proprietary licensing decision before public distribution.

# 13. Definition of Done

A feature is complete when:

- Requirements are documented.
- Interfaces are defined.
- Business logic is separated from UI.
- Error handling is implemented.
- Automated tests pass.
- Security requirements are satisfied.
- No regression is introduced.
- Documentation is updated.
- Feature is verified on the target Mac.

# 14. Final Architecture Decisions

| Area          | Decision                         |
| ------------- | -------------------------------- |
| Product       | Independent macOS Dynamic Island |
| UI            | SwiftUI                          |
| Native APIs   | AppKit                           |
| Core          | Rust                             |
| Bridge        | UniFFI                           |
| Pattern       | Modular monolith                 |
| Communication | Typed event-driven               |
| Database      | SQLite                           |
| Storage       | Local filesystem                 |
| Secrets       | Keychain                         |
| Testing       | XCTest + Cargo Test              |
| CI/CD         | GitHub Actions                   |
| Distribution  | Signed DMG                       |
| Backend       | Not required                     |
| Cloud sync    | Out of initial scope             |
| Analytics     | Opt-in only                      |

**Primary engineering principle:** Build a stable native macOS foundation first, then add independent feature modules without coupling their business logic to the presentation layer.
