//! SQLite repository for `clipboard_items` and `clipboard_pins` with deduplication and retention pruning.

use crate::{map_sql_err, Storage};
use island_common::{unix_timestamp_secs, IslandResult};
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ClipboardItemRecord {
    pub id: i64,
    pub content_type: String,
    pub text_content: String,
    pub source_app: String,
    pub is_pinned: bool,
    pub created_at: i64,
    pub updated_at: i64,
}

pub trait ClipboardRepository {
    fn insert_or_bump(
        &self,
        content_type: &str,
        text_content: &str,
        source_app: &str,
        now_secs: i64,
    ) -> IslandResult<ClipboardItemRecord>;
    fn list_or_search(&self, query: Option<&str>, limit: usize) -> IslandResult<Vec<ClipboardItemRecord>>;
    fn set_pinned(&self, item_id: i64, pinned: bool) -> IslandResult<()>;
    fn delete(&self, item_id: i64) -> IslandResult<()>;
    fn prune_expired(&self, retention_days: u32, now_secs: i64) -> IslandResult<usize>;
    fn clear_all(&self) -> IslandResult<usize>;
}

pub struct SqliteClipboardRepo {
    storage: Storage,
}

impl Storage {
    pub fn clipboard_repo(&self) -> SqliteClipboardRepo {
        SqliteClipboardRepo {
            storage: self.clone(),
        }
    }
}

impl ClipboardRepository for SqliteClipboardRepo {
    fn insert_or_bump(
        &self,
        content_type: &str,
        text_content: &str,
        source_app: &str,
        now_secs: i64,
    ) -> IslandResult<ClipboardItemRecord> {
        self.storage.with_conn(|conn| {
            let existing_id: Option<i64> = conn
                .query_row(
                    "SELECT id FROM clipboard_items WHERE content_type = ?1 AND text_content = ?2 LIMIT 1",
                    params![content_type, text_content],
                    |row| row.get(0),
                )
                .optional()
                .map_err(map_sql_err)?;

            let item_id = if let Some(id) = existing_id {
                conn.execute(
                    "UPDATE clipboard_items SET source_app = ?1, updated_at = ?2 WHERE id = ?3",
                    params![source_app, now_secs, id],
                )
                .map_err(map_sql_err)?;
                id
            } else {
                conn.execute(
                    "INSERT INTO clipboard_items (content_type, text_content, source_app, created_at, updated_at)
                     VALUES (?1, ?2, ?3, ?4, ?5)",
                    params![content_type, text_content, source_app, now_secs, now_secs],
                )
                .map_err(map_sql_err)?;
                conn.last_insert_rowid()
            };

            conn.query_row(
                "SELECT c.id, c.content_type, c.text_content, c.source_app,
                        (p.item_id IS NOT NULL) AS is_pinned,
                        c.created_at, c.updated_at
                 FROM clipboard_items c
                 LEFT JOIN clipboard_pins p ON p.item_id = c.id
                 WHERE c.id = ?1",
                params![item_id],
                |row| {
                    Ok(ClipboardItemRecord {
                        id: row.get(0)?,
                        content_type: row.get(1)?,
                        text_content: row.get(2)?,
                        source_app: row.get(3)?,
                        is_pinned: row.get::<_, i32>(4)? != 0,
                        created_at: row.get(5)?,
                        updated_at: row.get(6)?,
                    })
                },
            )
            .map_err(map_sql_err)
        })
    }

    fn list_or_search(&self, query: Option<&str>, limit: usize) -> IslandResult<Vec<ClipboardItemRecord>> {
        let trimmed = query.map(str::trim).filter(|s| !s.is_empty());
        self.storage.with_conn(|conn| {
            let mut results = Vec::new();
            if let Some(q) = trimmed {
                let pattern = format!("%{q}%");
                let mut stmt = conn
                    .prepare(
                        "SELECT c.id, c.content_type, c.text_content, c.source_app,
                                (p.item_id IS NOT NULL) AS is_pinned,
                                c.created_at, c.updated_at
                         FROM clipboard_items c
                         LEFT JOIN clipboard_pins p ON p.item_id = c.id
                         WHERE c.text_content LIKE ?1 COLLATE NOCASE
                            OR c.source_app LIKE ?1 COLLATE NOCASE
                         ORDER BY is_pinned DESC, c.updated_at DESC, c.id DESC
                         LIMIT ?2",
                    )
                    .map_err(map_sql_err)?;
                let rows = stmt
                    .query_map(params![pattern, limit as i64], map_clipboard_row)
                    .map_err(map_sql_err)?;
                for r in rows {
                    results.push(r.map_err(map_sql_err)?);
                }
            } else {
                let mut stmt = conn
                    .prepare(
                        "SELECT c.id, c.content_type, c.text_content, c.source_app,
                                (p.item_id IS NOT NULL) AS is_pinned,
                                c.created_at, c.updated_at
                         FROM clipboard_items c
                         LEFT JOIN clipboard_pins p ON p.item_id = c.id
                         ORDER BY is_pinned DESC, c.updated_at DESC, c.id DESC
                         LIMIT ?1",
                    )
                    .map_err(map_sql_err)?;
                let rows = stmt
                    .query_map(params![limit as i64], map_clipboard_row)
                    .map_err(map_sql_err)?;
                for r in rows {
                    results.push(r.map_err(map_sql_err)?);
                }
            }
            Ok(results)
        })
    }

    fn set_pinned(&self, item_id: i64, pinned: bool) -> IslandResult<()> {
        let now = unix_timestamp_secs();
        self.storage.with_conn(|conn| {
            if pinned {
                conn.execute(
                    "INSERT INTO clipboard_pins (item_id, pinned_at) VALUES (?1, ?2)
                     ON CONFLICT(item_id) DO NOTHING",
                    params![item_id, now],
                )
                .map_err(map_sql_err)?;
            } else {
                conn.execute(
                    "DELETE FROM clipboard_pins WHERE item_id = ?1",
                    params![item_id],
                )
                .map_err(map_sql_err)?;
            }
            Ok(())
        })
    }

    fn delete(&self, item_id: i64) -> IslandResult<()> {
        self.storage.with_conn(|conn| {
            conn.execute("DELETE FROM clipboard_items WHERE id = ?1", params![item_id])
                .map_err(map_sql_err)?;
            Ok(())
        })
    }

    fn prune_expired(&self, retention_days: u32, now_secs: i64) -> IslandResult<usize> {
        let cutoff = now_secs - i64::from(retention_days) * 86_400;
        self.storage.with_conn(|conn| {
            let deleted = conn
                .execute(
                    "DELETE FROM clipboard_items
                     WHERE updated_at < ?1
                       AND id NOT IN (SELECT item_id FROM clipboard_pins)",
                    params![cutoff],
                )
                .map_err(map_sql_err)?;
            Ok(deleted)
        })
    }

    fn clear_all(&self) -> IslandResult<usize> {
        self.storage.with_conn(|conn| {
            conn.execute("DELETE FROM clipboard_pins", [])
                .map_err(map_sql_err)?;
            let deleted = conn
                .execute("DELETE FROM clipboard_items", [])
                .map_err(map_sql_err)?;
            Ok(deleted)
        })
    }
}

fn map_clipboard_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<ClipboardItemRecord> {
    Ok(ClipboardItemRecord {
        id: row.get(0)?,
        content_type: row.get(1)?,
        text_content: row.get(2)?,
        source_app: row.get(3)?,
        is_pinned: row.get::<_, i32>(4)? != 0,
        created_at: row.get(5)?,
        updated_at: row.get(6)?,
    })
}
