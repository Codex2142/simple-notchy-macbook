-- 0002_clipboard.sql
-- Clipboard items and pinned clipboard items with foreign-key cascade.

CREATE TABLE IF NOT EXISTS clipboard_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content_type TEXT NOT NULL,
    text_content TEXT NOT NULL,
    source_app TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_clipboard_items_updated_at
    ON clipboard_items(updated_at DESC);

CREATE TABLE IF NOT EXISTS clipboard_pins (
    item_id INTEGER PRIMARY KEY NOT NULL,
    pinned_at INTEGER NOT NULL,
    FOREIGN KEY (item_id) REFERENCES clipboard_items(id) ON DELETE CASCADE
);
