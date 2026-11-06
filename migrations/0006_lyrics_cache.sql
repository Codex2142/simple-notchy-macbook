CREATE TABLE IF NOT EXISTS lyrics_cache (
    track_key TEXT PRIMARY KEY NOT NULL,
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    synced_lrc TEXT NOT NULL,
    updated_at INTEGER NOT NULL
);
