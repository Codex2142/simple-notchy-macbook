-- 0003_timers.sql
-- Timer and Pomodoro focus session history tables (PRD Section 7).

CREATE TABLE IF NOT EXISTS timer_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kind TEXT NOT NULL,
    label TEXT NOT NULL,
    duration_secs INTEGER NOT NULL,
    started_at INTEGER NOT NULL,
    completed_at INTEGER,
    status TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_timer_sessions_started_at
    ON timer_sessions(started_at DESC);

CREATE TABLE IF NOT EXISTS focus_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    label TEXT NOT NULL,
    work_secs INTEGER NOT NULL,
    break_secs INTEGER NOT NULL,
    started_at INTEGER NOT NULL,
    ended_at INTEGER,
    completed_cycles INTEGER NOT NULL DEFAULT 0
);
