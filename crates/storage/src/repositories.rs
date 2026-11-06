//! Repository interfaces and SQLite implementations for settings, display profiles, and modules.

use crate::{map_sql_err, Storage};
use island_common::{unix_timestamp_secs, IslandError, IslandResult, RetentionPolicy};
use rusqlite::{params, OptionalExtension};
use serde::{de::DeserializeOwned, Deserialize, Serialize};

const RETENTION_SETTINGS_KEY: &str = "retention_policy";

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DisplayProfileRecord {
    pub display_uuid: String,
    pub name: String,
    pub has_hardware_notch: bool,
    pub notch_width: f64,
    pub notch_height: f64,
    pub virtual_island_enabled: bool,
    pub updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModuleSettingRecord {
    pub module_id: String,
    pub enabled: bool,
    pub config_json: String,
    pub updated_at: i64,
}

pub trait SettingsRepository {
    fn get_raw(&self, key: &str) -> IslandResult<Option<String>>;
    fn set_raw(&self, key: &str, value_json: &str) -> IslandResult<()>;
    fn get_retention_policy(&self) -> IslandResult<RetentionPolicy>;
    fn set_retention_policy(&self, policy: &RetentionPolicy) -> IslandResult<()>;
}

pub trait DisplayProfileRepository {
    fn upsert(&self, profile: &DisplayProfileRecord) -> IslandResult<()>;
    fn get(&self, display_uuid: &str) -> IslandResult<Option<DisplayProfileRecord>>;
    fn list_all(&self) -> IslandResult<Vec<DisplayProfileRecord>>;
}

pub trait ModuleSettingsRepository {
    fn upsert(&self, setting: &ModuleSettingRecord) -> IslandResult<()>;
    fn get(&self, module_id: &str) -> IslandResult<Option<ModuleSettingRecord>>;
    fn list_all(&self) -> IslandResult<Vec<ModuleSettingRecord>>;
}

pub struct SqliteSettingsRepo {
    storage: Storage,
}

pub struct SqliteDisplayProfileRepo {
    storage: Storage,
}

pub struct SqliteModuleSettingsRepo {
    storage: Storage,
}

impl Storage {
    pub fn settings_repo(&self) -> SqliteSettingsRepo {
        SqliteSettingsRepo {
            storage: self.clone(),
        }
    }

    pub fn display_profile_repo(&self) -> SqliteDisplayProfileRepo {
        SqliteDisplayProfileRepo {
            storage: self.clone(),
        }
    }

    pub fn module_settings_repo(&self) -> SqliteModuleSettingsRepo {
        SqliteModuleSettingsRepo {
            storage: self.clone(),
        }
    }

    pub fn lyrics_cache_repo(&self) -> SqliteLyricsCacheRepo {
        SqliteLyricsCacheRepo {
            storage: self.clone(),
        }
    }
}

pub struct SqliteLyricsCacheRepo {
    storage: Storage,
}

impl SqliteLyricsCacheRepo {
    pub fn track_key(title: &str, artist: &str) -> String {
        format!(
            "{}::{}",
            title.trim().to_lowercase(),
            artist.trim().to_lowercase()
        )
    }

    pub fn upsert_lrc(&self, title: &str, artist: &str, synced_lrc: &str) -> IslandResult<()> {
        let key = Self::track_key(title, artist);
        let now = unix_timestamp_secs();
        self.storage.with_conn(|conn| {
            conn.execute(
                "INSERT INTO lyrics_cache (track_key, title, artist, synced_lrc, updated_at)
                 VALUES (?1, ?2, ?3, ?4, ?5)
                 ON CONFLICT(track_key) DO UPDATE SET
                    synced_lrc = excluded.synced_lrc,
                    updated_at = excluded.updated_at",
                params![key, title.trim(), artist.trim(), synced_lrc, now],
            )
            .map_err(map_sql_err)?;
            Ok(())
        })
    }

    pub fn get_lrc(&self, title: &str, artist: &str) -> IslandResult<Option<String>> {
        let key = Self::track_key(title, artist);
        self.storage.with_conn(|conn| {
            conn.query_row(
                "SELECT synced_lrc FROM lyrics_cache WHERE track_key = ?1",
                params![key],
                |row| row.get(0),
            )
            .optional()
            .map_err(map_sql_err)
        })
    }
}

impl SqliteSettingsRepo {
    pub fn get_typed<T: DeserializeOwned>(&self, key: &str) -> IslandResult<Option<T>> {
        match self.get_raw(key)? {
            Some(raw) => {
                let parsed = serde_json::from_str::<T>(&raw)
                    .map_err(|e| IslandError::Storage(format!("JSON decode error for {key}: {e}")))?;
                Ok(Some(parsed))
            }
            None => Ok(None),
        }
    }

    pub fn set_typed<T: Serialize>(&self, key: &str, value: &T) -> IslandResult<()> {
        let json = serde_json::to_string(value)
            .map_err(|e| IslandError::Storage(format!("JSON encode error for {key}: {e}")))?;
        self.set_raw(key, &json)
    }
}

impl SettingsRepository for SqliteSettingsRepo {
    fn get_raw(&self, key: &str) -> IslandResult<Option<String>> {
        self.storage.with_conn(|conn| {
            conn.query_row(
                "SELECT value_json FROM app_settings WHERE key = ?1",
                params![key],
                |row| row.get(0),
            )
            .optional()
            .map_err(map_sql_err)
        })
    }

    fn set_raw(&self, key: &str, value_json: &str) -> IslandResult<()> {
        let now = unix_timestamp_secs();
        self.storage.with_conn(|conn| {
            conn.execute(
                "INSERT INTO app_settings (key, value_json, updated_at)
                 VALUES (?1, ?2, ?3)
                 ON CONFLICT(key) DO UPDATE SET
                    value_json = excluded.value_json,
                    updated_at = excluded.updated_at",
                params![key, value_json, now],
            )
            .map_err(map_sql_err)?;
            Ok(())
        })
    }

    fn get_retention_policy(&self) -> IslandResult<RetentionPolicy> {
        Ok(self
            .get_typed::<RetentionPolicy>(RETENTION_SETTINGS_KEY)?
            .unwrap_or_default())
    }

    fn set_retention_policy(&self, policy: &RetentionPolicy) -> IslandResult<()> {
        if policy.clipboard_days == 0
            || policy.timer_history_days == 0
            || policy.activity_events_days == 0
            || policy.logs_days == 0
        {
            return Err(IslandError::Validation(
                "Retention days must all be greater than 0".to_string(),
            ));
        }
        self.set_typed(RETENTION_SETTINGS_KEY, policy)
    }
}

impl DisplayProfileRepository for SqliteDisplayProfileRepo {
    fn upsert(&self, profile: &DisplayProfileRecord) -> IslandResult<()> {
        let now = unix_timestamp_secs();
        self.storage.with_conn(|conn| {
            conn.execute(
                "INSERT INTO display_profiles (
                    display_uuid, name, has_hardware_notch, notch_width, notch_height, virtual_island_enabled, updated_at
                 ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                 ON CONFLICT(display_uuid) DO UPDATE SET
                    name = excluded.name,
                    has_hardware_notch = excluded.has_hardware_notch,
                    notch_width = excluded.notch_width,
                    notch_height = excluded.notch_height,
                    virtual_island_enabled = excluded.virtual_island_enabled,
                    updated_at = excluded.updated_at",
                params![
                    profile.display_uuid,
                    profile.name,
                    i32::from(profile.has_hardware_notch),
                    profile.notch_width,
                    profile.notch_height,
                    i32::from(profile.virtual_island_enabled),
                    now
                ],
            )
            .map_err(map_sql_err)?;
            Ok(())
        })
    }

    fn get(&self, display_uuid: &str) -> IslandResult<Option<DisplayProfileRecord>> {
        self.storage.with_conn(|conn| {
            conn.query_row(
                "SELECT display_uuid, name, has_hardware_notch, notch_width, notch_height, virtual_island_enabled, updated_at
                 FROM display_profiles
                 WHERE display_uuid = ?1",
                params![display_uuid],
                |row| {
                    Ok(DisplayProfileRecord {
                        display_uuid: row.get(0)?,
                        name: row.get(1)?,
                        has_hardware_notch: row.get::<_, i32>(2)? != 0,
                        notch_width: row.get(3)?,
                        notch_height: row.get(4)?,
                        virtual_island_enabled: row.get::<_, i32>(5)? != 0,
                        updated_at: row.get(6)?,
                    })
                },
            )
            .optional()
            .map_err(map_sql_err)
        })
    }

    fn list_all(&self) -> IslandResult<Vec<DisplayProfileRecord>> {
        self.storage.with_conn(|conn| {
            let mut stmt = conn
                .prepare(
                    "SELECT display_uuid, name, has_hardware_notch, notch_width, notch_height, virtual_island_enabled, updated_at
                     FROM display_profiles
                     ORDER BY name ASC",
                )
                .map_err(map_sql_err)?;
            let rows = stmt
                .query_map([], |row| {
                    Ok(DisplayProfileRecord {
                        display_uuid: row.get(0)?,
                        name: row.get(1)?,
                        has_hardware_notch: row.get::<_, i32>(2)? != 0,
                        notch_width: row.get(3)?,
                        notch_height: row.get(4)?,
                        virtual_island_enabled: row.get::<_, i32>(5)? != 0,
                        updated_at: row.get(6)?,
                    })
                })
                .map_err(map_sql_err)?;
            rows.collect::<Result<Vec<_>, _>>().map_err(map_sql_err)
        })
    }
}

impl ModuleSettingsRepository for SqliteModuleSettingsRepo {
    fn upsert(&self, setting: &ModuleSettingRecord) -> IslandResult<()> {
        let now = unix_timestamp_secs();
        self.storage.with_conn(|conn| {
            conn.execute(
                "INSERT INTO module_settings (module_id, enabled, config_json, updated_at)
                 VALUES (?1, ?2, ?3, ?4)
                 ON CONFLICT(module_id) DO UPDATE SET
                    enabled = excluded.enabled,
                    config_json = excluded.config_json,
                    updated_at = excluded.updated_at",
                params![
                    setting.module_id,
                    i32::from(setting.enabled),
                    setting.config_json,
                    now
                ],
            )
            .map_err(map_sql_err)?;
            Ok(())
        })
    }

    fn get(&self, module_id: &str) -> IslandResult<Option<ModuleSettingRecord>> {
        self.storage.with_conn(|conn| {
            conn.query_row(
                "SELECT module_id, enabled, config_json, updated_at
                 FROM module_settings
                 WHERE module_id = ?1",
                params![module_id],
                |row| {
                    Ok(ModuleSettingRecord {
                        module_id: row.get(0)?,
                        enabled: row.get::<_, i32>(1)? != 0,
                        config_json: row.get(2)?,
                        updated_at: row.get(3)?,
                    })
                },
            )
            .optional()
            .map_err(map_sql_err)
        })
    }

    fn list_all(&self) -> IslandResult<Vec<ModuleSettingRecord>> {
        self.storage.with_conn(|conn| {
            let mut stmt = conn
                .prepare(
                    "SELECT module_id, enabled, config_json, updated_at
                     FROM module_settings
                     ORDER BY module_id ASC",
                )
                .map_err(map_sql_err)?;
            let rows = stmt
                .query_map([], |row| {
                    Ok(ModuleSettingRecord {
                        module_id: row.get(0)?,
                        enabled: row.get::<_, i32>(1)? != 0,
                        config_json: row.get(2)?,
                        updated_at: row.get(3)?,
                    })
                })
                .map_err(map_sql_err)?;
            rows.collect::<Result<Vec<_>, _>>().map_err(map_sql_err)
        })
    }
}
