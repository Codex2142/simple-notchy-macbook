//! SQLite storage engine, migration runner, and repository traits/implementations for Project Island.

pub mod clipboard_repo;
pub mod notes_shelf_repo;
pub mod repositories;
pub mod timer_repo;

use island_common::{unix_timestamp_secs, IslandError, IslandResult};
use rusqlite::{params, Connection};
use std::path::Path;
use std::sync::{Arc, Mutex};

const MIGRATION_0001: &str = include_str!("../../../migrations/0001_initial_schema.sql");
const MIGRATION_0002: &str = include_str!("../../../migrations/0002_clipboard.sql");
const MIGRATION_0003: &str = include_str!("../../../migrations/0003_timers.sql");
const MIGRATION_0004: &str = include_str!("../../../migrations/0004_media.sql");
const MIGRATION_0005: &str = include_str!("../../../migrations/0005_notes_shelf.sql");

struct Migration {
    version: i64,
    name: &'static str,
    sql: &'static str,
}

const MIGRATIONS: &[Migration] = &[
    Migration {
        version: 1,
        name: "0001_initial_schema",
        sql: MIGRATION_0001,
    },
    Migration {
        version: 2,
        name: "0002_clipboard",
        sql: MIGRATION_0002,
    },
    Migration {
        version: 3,
        name: "0003_timers",
        sql: MIGRATION_0003,
    },
    Migration {
        version: 4,
        name: "0004_media",
        sql: MIGRATION_0004,
    },
    Migration {
        version: 5,
        name: "0005_notes_shelf",
        sql: MIGRATION_0005,
    },
];

/// Thread-safe handle to the Project Island SQLite database.
#[derive(Clone)]
pub struct Storage {
    conn: Arc<Mutex<Connection>>,
}

impl Storage {
    /// Opens or creates a SQLite database at `path`, enables WAL and foreign keys, and runs pending migrations.
    pub fn open(path: impl AsRef<Path>) -> IslandResult<Self> {
        let conn = Connection::open(path.as_ref()).map_err(map_sql_err)?;
        Self::from_connection(conn)
    }

    /// Creates an in-memory SQLite database with all migrations applied (ideal for tests).
    pub fn open_in_memory() -> IslandResult<Self> {
        let conn = Connection::open_in_memory().map_err(map_sql_err)?;
        Self::from_connection(conn)
    }

    fn from_connection(conn: Connection) -> IslandResult<Self> {
        conn.execute_batch(
            "PRAGMA journal_mode = WAL;
             PRAGMA synchronous = NORMAL;
             PRAGMA foreign_keys = ON;",
        )
        .map_err(map_sql_err)?;

        let storage = Self {
            conn: Arc::new(Mutex::new(conn)),
        };
        storage.run_migrations()?;
        Ok(storage)
    }

    /// Runs any unapplied migrations in ascending version order.
    pub fn run_migrations(&self) -> IslandResult<()> {
        let mut conn = self.lock_conn()?;
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS schema_migrations (
                version INTEGER PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                applied_at INTEGER NOT NULL
            );",
        )
        .map_err(map_sql_err)?;

        for m in MIGRATIONS {
            let already_applied: bool = conn
                .query_row(
                    "SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version = ?1)",
                    params![m.version],
                    |row| row.get(0),
                )
                .map_err(map_sql_err)?;

            if !already_applied {
                let tx = conn.transaction().map_err(map_sql_err)?;
                tx.execute_batch(m.sql).map_err(map_sql_err)?;
                tx.execute(
                    "INSERT INTO schema_migrations (version, name, applied_at) VALUES (?1, ?2, ?3)",
                    params![m.version, m.name, unix_timestamp_secs()],
                )
                .map_err(map_sql_err)?;
                tx.commit().map_err(map_sql_err)?;
                tracing::info!(version = m.version, name = m.name, "Applied SQLite migration");
            }
        }
        Ok(())
    }

    /// Executes an arbitrary closure with a locked mutable reference to the underlying `rusqlite::Connection`.
    pub fn with_conn<F, T>(&self, f: F) -> IslandResult<T>
    where
        F: FnOnce(&mut Connection) -> IslandResult<T>,
    {
        let mut guard = self.lock_conn()?;
        f(&mut guard)
    }

    fn lock_conn(&self) -> IslandResult<std::sync::MutexGuard<'_, Connection>> {
        self.conn
            .lock()
            .map_err(|_| IslandError::Storage("Database connection mutex poisoned".to_string()))
    }
}

pub(crate) fn map_sql_err(err: rusqlite::Error) -> IslandError {
    IslandError::Storage(err.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::repositories::{
        DisplayProfileRecord, DisplayProfileRepository, ModuleSettingRecord,
        ModuleSettingsRepository, SettingsRepository,
    };
    use island_common::RetentionPolicy;

    #[test]
    fn migrations_are_idempotent() {
        let storage = Storage::open_in_memory().expect("open in-memory db");
        storage.run_migrations().expect("re-running migrations succeeds");
    }

    #[test]
    fn settings_and_retention_roundtrip() {
        let storage = Storage::open_in_memory().expect("open in-memory db");
        let repo = storage.settings_repo();

        let default_retention = repo.get_retention_policy().expect("load default retention");
        assert_eq!(default_retention, RetentionPolicy::default());

        let custom = RetentionPolicy {
            clipboard_days: 14,
            timer_history_days: 180,
            activity_events_days: 30,
            logs_days: 14,
        };
        repo.set_retention_policy(&custom)
            .expect("save custom retention");
        let loaded = repo.get_retention_policy().expect("reload custom retention");
        assert_eq!(loaded, custom);
    }

    #[test]
    fn display_and_module_settings_crud() {
        let storage = Storage::open_in_memory().expect("open in-memory db");
        let display_repo = storage.display_profile_repo();
        let module_repo = storage.module_settings_repo();

        let profile = DisplayProfileRecord {
            display_uuid: "DISP-BUILT-IN-1".to_string(),
            name: "Built-in Liquid Retina XDR Display".to_string(),
            has_hardware_notch: true,
            notch_width: 184.0,
            notch_height: 37.0,
            virtual_island_enabled: true,
            updated_at: 1_700_000_000,
        };
        display_repo.upsert(&profile).expect("upsert display");

        let loaded = display_repo
            .get("DISP-BUILT-IN-1")
            .expect("query display")
            .expect("display exists");
        assert_eq!(loaded.name, profile.name);
        assert!(loaded.has_hardware_notch);

        let mod_setting = ModuleSettingRecord {
            module_id: "clipboard".to_string(),
            enabled: true,
            config_json: r#"{"capture_images":true}"#.to_string(),
            updated_at: 1_700_000_000,
        };
        module_repo.upsert(&mod_setting).expect("upsert module");
        let all_modules = module_repo.list_all().expect("list modules");
        assert_eq!(all_modules.len(), 1);
        assert_eq!(all_modules[0].module_id, "clipboard");
    }
}
