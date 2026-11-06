-- 0001_initial_schema.sql
-- Initial Project Island schema for application settings, display profiles, and module settings.

CREATE TABLE IF NOT EXISTS schema_migrations (
    version INTEGER PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    applied_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS app_settings (
    key TEXT PRIMARY KEY NOT NULL,
    value_json TEXT NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS display_profiles (
    display_uuid TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    has_hardware_notch INTEGER NOT NULL DEFAULT 0,
    notch_width REAL NOT NULL DEFAULT 0.0,
    notch_height REAL NOT NULL DEFAULT 0.0,
    virtual_island_enabled INTEGER NOT NULL DEFAULT 1,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS module_settings (
    module_id TEXT PRIMARY KEY NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    config_json TEXT NOT NULL DEFAULT '{}',
    updated_at INTEGER NOT NULL
);
