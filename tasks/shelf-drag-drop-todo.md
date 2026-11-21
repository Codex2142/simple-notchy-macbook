# File Shelf Drag-and-Drop — Task List (`tasks/shelf-drag-drop-todo.md`)

## Task 1: Implement `ShelfStagingManager`

**Description:** Create `ShelfStagingManager` in `IslandIntegrations` to manage `~/Library/Application Support/ProjectIsland/ShelfStaging/` for materialized File Promises and browser/raw images, with TIFF-to-PNG conversion and strict ownership-checked auto-cleanup.

**Acceptance criteria:**
- [x] Generates collision-free destination URLs with sanitized filenames inside `ShelfStaging/`.
- [x] Stages raw image bytes (converting TIFF to PNG when possible) atomically.
- [x] `cleanupStagedFileIfOwned(path:)` deletes only files inside `ShelfStaging/` and never touches external user files.

**Verification:**
- [x] Build & tests pass: `./scripts/test-macos.sh`

**Dependencies:** None

**Files likely touched:**
- `apps/macos/Sources/Integrations/ShelfStagingManager.swift`

**Estimated scope:** Small (1 file)

---

## Task 2: Implement `ShelfDropResolver`

**Description:** Create `ShelfDropResolver` in `IslandIntegrations` to inspect and extract File & Media payloads from `NSPasteboard` across Finder, VS Code (Electron raw `Data` `public.file-url`, `NSFilenamesPboardType`, existing local path strings), `NSFilePromiseReceiver` (Photos, Mail, Screenshots), raw image data, and browser `<img>` URLs, while rejecting non-file text and non-image web URLs.

**Acceptance criteria:**
- [x] Accepts VS Code raw `Data` `public.file-url`, `NSFilenamesPboardType`, standard `NSURL`, and existing local file path strings.
- [x] Accepts `NSFilePromiseReceiver`, raw image data, and browser image URLs; rejects arbitrary plain text and non-image web URLs.
- [x] Deduplicates multi-representation drops using strict priority ordering.

**Verification:**
- [x] Build & tests pass: `./scripts/test-macos.sh`

**Dependencies:** Task 1

**Files likely touched:**
- `apps/macos/Sources/Integrations/ShelfDropResolver.swift`

**Estimated scope:** Small (1 file)

---

## Task 3: Integrate Staging Cleanup & Drop Handling into `NotesShelfStore`

**Description:** Wire `ShelfStagingManager` and `ShelfDropResolver` into `NotesShelfStore` so removing a shelf item or clearing the shelf cleans up owned staged files, and dropped pasteboards are resolved and persisted cleanly.

**Acceptance criteria:**
- [x] `removeShelfItem(_:)` cleans up staged files inside `ShelfStaging/` without deleting user local files.
- [x] `clearShelf()` cleans up all staged files inside `ShelfStaging/`.
- [x] `handleDroppedPasteboard(_:)` resolves and adds items via `addFileToShelf(url:)`.

**Verification:**
- [x] Build & tests pass: `./scripts/test-macos.sh`

**Dependencies:** Task 1, Task 2

**Files likely touched:**
- `apps/macos/Sources/Features/Notes/QuickNotesView.swift`

**Estimated scope:** Small (1 file)

---

## Checkpoint 1: After Tasks 1–3
- [x] `./scripts/test-macos.sh` builds and passes

---

## Task 4: AppKit `NSDraggingDestination` on `IslandHostingView` & Auto-Expand in `IslandWindowController`

**Description:** Add `NSDraggingDestination` support with self-drag guard to `IslandHostingView`, and coordinate drag-to-notch auto-expand, auto-switch to `.shelf` tab, and `isDragTargeted` state in `IslandWindowController`.

**Acceptance criteria:**
- [x] Dragging a valid File/Media payload onto the collapsed Notch or while on another tab auto-expands the Island and switches to `.shelf`.
- [x] Dragging an invalid payload (plain text / non-image link) or self-dragging from Shelf is ignored.
- [x] After drop completes, the Island remains on the `.shelf` tab so the user sees the added item.

**Verification:**
- [x] Build & tests pass: `./scripts/test-macos.sh`

**Dependencies:** Task 3

**Files likely touched:**
- `apps/macos/Sources/Window/IslandPanel.swift`
- `apps/macos/Sources/Window/IslandWindowController.swift`

**Estimated scope:** Small (2 files)

---

## Task 5: Upgrade `FileShelfView` UI & Wire Root App Callbacks

**Description:** Update `FileShelfView` to remove legacy SwiftUI `.onDrop`, display a highlighted drop target state when `isDragTargeted` is true, and render native macOS file icons (`NSWorkspace.shared.icon(forFile:)`) and downsampled image thumbnail previews. Wire drag callbacks in `ProjectIslandApp` and `IslandRootView`.

**Acceptance criteria:**
- [x] `FileShelfView` highlights clearly during an active drag-over (`isDragTargeted == true`).
- [x] Image items show rounded downsampled thumbnails; non-image files and folders show their native macOS icon.
- [x] `ProjectIslandApp` respects `settingsStore.isModuleEnabled("shelf")` for drag acceptance.

**Verification:**
- [x] Build & tests pass: `./scripts/test-macos.sh`

**Dependencies:** Task 4

**Files likely touched:**
- `apps/macos/Sources/Features/Shelf/FileShelfView.swift`
- `apps/macos/Sources/App/IslandRootView.swift`
- `apps/macos/Sources/App/ProjectIslandApp.swift`

**Estimated scope:** Medium (3 files)

---

## Task 6: Add Automated Self-Tests & Final Verification

**Description:** Add automated tests in `IslandSelfTest` covering VS Code raw `Data` `public.file-url`, `NSFilenamesPboardType`, plain-text/non-image rejection, raw image staging + safe cleanup, and drag-to-notch auto-expand/tab switch. Run full verification and code simplification review.

**Acceptance criteria:**
- [x] All new `IslandSelfTest` assertions pass in `./scripts/test-macos.sh`.
- [x] `ProjectIslandApp` builds cleanly with zero errors.

**Verification:**
- [x] Tests pass: `./scripts/test-macos.sh`

**Dependencies:** Task 5

**Files likely touched:**
- `apps/macos/Sources/SelfTest/main.swift`

**Estimated scope:** Small (1 file)

---

## Task 7: Multi-Item Drag-IN (Mixed Batches & Multi-Line URI Lists) & Multi-Item Drag-OUT

**Description:** Upgrade `ShelfDropResolver` for multi-line `public.uri-list` / multi-representation VS Code drops and mixed batches (local files + raw images/file promises), add batched `addFilesToShelf(urls:)` + selection state in `NotesShelfStore`, and add click-to-select chips plus an AppKit `NSDraggingSession` (`Drag All (N)` / `Drag Selected (K)`) handle in `FileShelfView`.

**Acceptance criteria:**
- [x] Multi-line `public.uri-list`, multi-file `NSFilenamesPboardType`, and mixed local + raw image batches all resolve without duplicates.
- [x] Clicking Shelf items toggles multi-selection; `Drag All (N)` / `Drag Selected (K)` drags multiple files simultaneously via native AppKit `NSDraggingSession`.

**Verification:**
- [x] Tests pass: `./scripts/test-macos.sh`

**Dependencies:** Task 6

**Files likely touched:**
- `apps/macos/Sources/Integrations/ShelfDropResolver.swift`
- `apps/macos/Sources/Features/Notes/QuickNotesView.swift`
- `apps/macos/Sources/Features/Shelf/FileShelfView.swift`
- `apps/macos/Sources/SelfTest/main.swift`

**Estimated scope:** Medium (4 files)

---

## Checkpoint 2: Complete
- [x] All acceptance criteria met
- [x] `./scripts/test-macos.sh` passes 100%
- [x] Walkthrough artifact created
