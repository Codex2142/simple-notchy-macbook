# Project Island — Database Architecture

## Overview

- **Engine:** Bundled SQLite (`rusqlite` with `WAL` journal mode and `PRAGMA foreign_keys = ON`)
- **Default Location:** `~/Library/Application Support/ProjectIsland/project_island.db`
- **Migrations Directory:** `migrations/`

## Schema Migrations

1. **`migrations/0001_initial_schema.sql`**
   - `schema_migrations`: Tracks applied migration versions and timestamps.
   - `app_settings`: Key-value JSON store for application preferences and `retention_policy`.
   - `display_profiles`: Per-display UUID hardware notch and virtual island settings.
   - `module_settings`: Feature module activation flags (`media`, `clipboard`, `timer`, `system`, `notes`, `shelf`).
2. **`migrations/0002_clipboard.sql`**
   - `clipboard_items`: Captured clipboard history with `content_type`, `text_content`, `source_app`, `created_at`, `updated_at`.
   - `clipboard_pins`: Pinned clipboard item IDs (`ON DELETE CASCADE`) exempt from retention pruning.
3. **`migrations/0003_timers.sql`**
   - `timer_sessions`: Countdown, Pomodoro, Stopwatch, and Keep Awake session history.
   - `focus_sessions`: Multi-cycle Pomodoro session tracking.
4. **`migrations/0004_media.sql`**
   - `media_preferences`: Media source preferences and favorite tracks.
5. **`migrations/0005_notes_shelf.sql`**
   - `notes`: Persistent Quick Notes.
   - `snippets`: Text expansion snippets.
   - `shelf_items`: Drag-to-notch File Shelf references.
   - `activity_events`: Audit/activity log events.

## Configurable Retention Policies

Default retention values (stored in `app_settings` under `retention_policy` and configurable via `SettingsStore`):
- **Clipboard History:** 7 days (Pinned items retained until deleted)
- **Timer & Focus History:** 90 days
- **Activity Events:** 7 days
- **Logs:** 7 days
- **Quick Notes:** Retained until deleted
