-- 0004_media.sql
-- Media preferences and favorite tracks (PRD Section 7).

CREATE TABLE IF NOT EXISTS media_preferences (
    key TEXT PRIMARY KEY NOT NULL,
    value_json TEXT NOT NULL,
    updated_at INTEGER NOT NULL
);
