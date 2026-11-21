# Implementation Plan: Universal File & Media Drag-and-Drop for Shelf

## Overview

Fix File Shelf drag-and-drop failures from VS Code (Electron/Chromium) and expand Shelf drop support to handle all **File & Media** sources on macOS — local files & folders (Finder, VS Code, IDEs, Terminal), `NSFilePromiseReceiver` (Photos, Mail, macOS Screenshot preview), and images dragged from browsers/apps — while rejecting non-media web links and arbitrary text snippets. Add drag-to-notch auto-expand & auto-switch to the Shelf tab with drop target highlight, internal staging with auto-cleanup for non-path media, and native file icons / image thumbnails.

## Architecture Decisions

- **AppKit `NSDraggingDestination` on `IslandHostingView`:** Replaces SwiftUI `.onDrop(of: [UTType.fileURL])` so the entire Notch/Island can accept drops even when collapsed or on another tab, inspect multi-representation `NSPasteboard` payloads (including Electron raw `Data` `public.file-url` and `NSFilenamesPboardType`), and receive `NSFilePromiseReceiver`.
- **No Rust/SQLite Schema Changes:** `shelf_items` already persists `(id, file_path, display_name, added_at)`. Non-local media (File Promises and browser/raw images) are materialized into `~/Library/Application Support/ProjectIsland/ShelfStaging/` and stored via the existing `addShelfItem` FFI API.
- **Safe Staging Cleanup:** `ShelfStagingManager` deletes files on `removeShelfItem` / `clearShelf` strictly when their standardized path lies inside `ShelfStaging/`, never touching user-owned local files.
- **Self-Drag Prevention:** `IslandHostingView` rejects drags originating from the Island itself (`sender.draggingSource != nil`) so dragging an item out of the Shelf never re-triggers drop ingestion.

## Task List

See `tasks/shelf-drag-drop-todo.md` for full task details, acceptance criteria, and verification steps.

### Phase 1: Staging & Pasteboard Drop Engine
- [x] Task 1: `ShelfStagingManager` — internal staging directory & safe auto-cleanup
- [x] Task 2: `ShelfDropResolver` — VS Code / Finder / IDE, File Promise, raw image, and browser image URL resolver
- [x] Task 3: Integrate `ShelfStagingManager` & `ShelfDropResolver` into `NotesShelfStore`

### Checkpoint 1: Core Drop & Staging Engine
- [x] Project compiles cleanly via `./scripts/test-macos.sh`

### Phase 2: Window Drag Destination & Shelf UI
- [x] Task 4: AppKit `NSDraggingDestination` on `IslandHostingView` & auto-expand/auto-switch in `IslandWindowController`
- [x] Task 5: Upgrade `FileShelfView` with drop target highlight, native macOS file icons, and async image thumbnails, plus root wiring

### Checkpoint 2: End-to-End Verification
- [x] Automated tests in `IslandSelfTest` pass (`./scripts/test-macos.sh`)
- [x] Code simplification pass complete

## Risks and Mitigations

| Risk | Impact | Mitigation |
| :--- | :--- | :--- |
| Duplicate items when source app puts both `fileURL` and `png`/`string` on pasteboard | Medium | Strict priority order in `ShelfDropResolver` (Local File > File Promise > Raw Image > Remote Image URL) + standardized path deduplication |
| Accidental deletion of user's original file on remove/clear | High | `ShelfStagingManager.isStagedFile` enforces strict standardized prefix check against `ShelfStaging/` before any `removeItem` call |
| Dragging an item out of Shelf re-triggers drop on Island | Medium | Reject drags where `sender.draggingSource != nil` in `IslandHostingView` |
| High memory usage from large dropped images in Shelf strip | Low | Downsample image thumbnails via `CGImageSourceCreateThumbnailAtIndex` (~44px) |
