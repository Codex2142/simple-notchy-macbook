//! SQLite repository for `timer_sessions` and `focus_sessions` with 90-day retention pruning.

use crate::{map_sql_err, Storage};
use island_common::IslandResult;
use rusqlite::params;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TimerSessionRecord {
    pub id: i64,
    pub kind: String,
    pub label: String,
    pub duration_secs: u32,
    pub started_at: i64,
    pub completed_at: Option<i64>,
    pub status: String,
}

pub trait TimerRepository {
    fn create_session(
        &self,
        kind: &str,
        label: &str,
        duration_secs: u32,
        started_at: i64,
    ) -> IslandResult<TimerSessionRecord>;
    fn finish_session(
        &self,
        session_id: i64,
        status: &str,
        completed_at: i64,
    ) -> IslandResult<TimerSessionRecord>;
    fn list_recent(&self, limit: usize) -> IslandResult<Vec<TimerSessionRecord>>;
    fn prune_expired(&self, retention_days: u32, now_secs: i64) -> IslandResult<usize>;
}

pub struct SqliteTimerRepo {
    storage: Storage,
}

impl Storage {
    pub fn timer_repo(&self) -> SqliteTimerRepo {
        SqliteTimerRepo {
            storage: self.clone(),
        }
    }
}

impl TimerRepository for SqliteTimerRepo {
    fn create_session(
        &self,
        kind: &str,
        label: &str,
        duration_secs: u32,
        started_at: i64,
    ) -> IslandResult<TimerSessionRecord> {
        self.storage.with_conn(|conn| {
            conn.execute(
                "INSERT INTO timer_sessions (kind, label, duration_secs, started_at, status)
                 VALUES (?1, ?2, ?3, ?4, 'running')",
                params![kind, label, duration_secs, started_at],
            )
            .map_err(map_sql_err)?;
            let id = conn.last_insert_rowid();
            Ok(TimerSessionRecord {
                id,
                kind: kind.to_string(),
                label: label.to_string(),
                duration_secs,
                started_at,
                completed_at: None,
                status: "running".to_string(),
            })
        })
    }

    fn finish_session(
        &self,
        session_id: i64,
        status: &str,
        completed_at: i64,
    ) -> IslandResult<TimerSessionRecord> {
        self.storage.with_conn(|conn| {
            conn.execute(
                "UPDATE timer_sessions SET status = ?1, completed_at = ?2 WHERE id = ?3",
                params![status, completed_at, session_id],
            )
            .map_err(map_sql_err)?;

            conn.query_row(
                "SELECT id, kind, label, duration_secs, started_at, completed_at, status
                 FROM timer_sessions WHERE id = ?1",
                params![session_id],
                |row| {
                    Ok(TimerSessionRecord {
                        id: row.get(0)?,
                        kind: row.get(1)?,
                        label: row.get(2)?,
                        duration_secs: row.get(3)?,
                        started_at: row.get(4)?,
                        completed_at: row.get(5)?,
                        status: row.get(6)?,
                    })
                },
            )
            .map_err(map_sql_err)
        })
    }

    fn list_recent(&self, limit: usize) -> IslandResult<Vec<TimerSessionRecord>> {
        self.storage.with_conn(|conn| {
            let mut stmt = conn
                .prepare(
                    "SELECT id, kind, label, duration_secs, started_at, completed_at, status
                     FROM timer_sessions
                     ORDER BY started_at DESC, id DESC
                     LIMIT ?1",
                )
                .map_err(map_sql_err)?;
            let rows = stmt
                .query_map(params![limit as i64], |row| {
                    Ok(TimerSessionRecord {
                        id: row.get(0)?,
                        kind: row.get(1)?,
                        label: row.get(2)?,
                        duration_secs: row.get(3)?,
                        started_at: row.get(4)?,
                        completed_at: row.get(5)?,
                        status: row.get(6)?,
                    })
                })
                .map_err(map_sql_err)?;
            rows.collect::<Result<Vec<_>, _>>().map_err(map_sql_err)
        })
    }

    fn prune_expired(&self, retention_days: u32, now_secs: i64) -> IslandResult<usize> {
        let cutoff = now_secs - i64::from(retention_days) * 86_400;
        self.storage.with_conn(|conn| {
            conn.execute(
                "DELETE FROM timer_sessions WHERE started_at < ?1",
                params![cutoff],
            )
            .map_err(map_sql_err)
        })
    }
}
