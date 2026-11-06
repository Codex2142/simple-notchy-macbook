//! SQLite repositories for Quick Notes and File Shelf items (PRD Section 7).

use crate::{map_sql_err, Storage};
use island_common::{IslandError, IslandResult};
use rusqlite::params;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct NoteRecord {
    pub id: i64,
    pub title: String,
    pub content: String,
    pub updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShelfItemRecord {
    pub id: i64,
    pub file_path: String,
    pub display_name: String,
    pub added_at: i64,
}

pub struct SqliteNotesShelfRepo {
    storage: Storage,
}

impl Storage {
    pub fn notes_shelf_repo(&self) -> SqliteNotesShelfRepo {
        SqliteNotesShelfRepo {
            storage: self.clone(),
        }
    }
}

impl SqliteNotesShelfRepo {
    pub fn save_note(
        &self,
        note_id: Option<i64>,
        title: &str,
        content: &str,
        now_secs: i64,
    ) -> IslandResult<NoteRecord> {
        if title.trim().is_empty() && content.trim().is_empty() {
            return Err(IslandError::Validation(
                "Note title and content cannot both be empty".to_string(),
            ));
        }

        self.storage.with_conn(|conn| {
            let resolved_id = if let Some(id) = note_id {
                conn.execute(
                    "UPDATE notes SET title = ?1, content = ?2, updated_at = ?3 WHERE id = ?4",
                    params![title, content, now_secs, id],
                )
                .map_err(map_sql_err)?;
                id
            } else {
                conn.execute(
                    "INSERT INTO notes (title, content, updated_at) VALUES (?1, ?2, ?3)",
                    params![title, content, now_secs],
                )
                .map_err(map_sql_err)?;
                conn.last_insert_rowid()
            };

            Ok(NoteRecord {
                id: resolved_id,
                title: title.to_string(),
                content: content.to_string(),
                updated_at: now_secs,
            })
        })
    }

    pub fn list_notes(&self, limit: usize) -> IslandResult<Vec<NoteRecord>> {
        self.storage.with_conn(|conn| {
            let mut stmt = conn
                .prepare(
                    "SELECT id, title, content, updated_at
                     FROM notes
                     ORDER BY updated_at DESC, id DESC
                     LIMIT ?1",
                )
                .map_err(map_sql_err)?;
            let rows = stmt
                .query_map(params![limit as i64], |row| {
                    Ok(NoteRecord {
                        id: row.get(0)?,
                        title: row.get(1)?,
                        content: row.get(2)?,
                        updated_at: row.get(3)?,
                    })
                })
                .map_err(map_sql_err)?;
            rows.collect::<Result<Vec<_>, _>>().map_err(map_sql_err)
        })
    }

    pub fn delete_note(&self, note_id: i64) -> IslandResult<()> {
        self.storage.with_conn(|conn| {
            conn.execute("DELETE FROM notes WHERE id = ?1", params![note_id])
                .map_err(map_sql_err)?;
            Ok(())
        })
    }

    pub fn add_shelf_item(
        &self,
        file_path: &str,
        display_name: &str,
        now_secs: i64,
    ) -> IslandResult<ShelfItemRecord> {
        if file_path.trim().is_empty() {
            return Err(IslandError::Validation(
                "Shelf file_path must not be empty".to_string(),
            ));
        }

        self.storage.with_conn(|conn| {
            conn.execute(
                "INSERT INTO shelf_items (file_path, display_name, added_at)
                 VALUES (?1, ?2, ?3)
                 ON CONFLICT(file_path) DO UPDATE SET
                    display_name = excluded.display_name,
                    added_at = excluded.added_at",
                params![file_path, display_name, now_secs],
            )
            .map_err(map_sql_err)?;

            conn.query_row(
                "SELECT id, file_path, display_name, added_at FROM shelf_items WHERE file_path = ?1",
                params![file_path],
                |row| {
                    Ok(ShelfItemRecord {
                        id: row.get(0)?,
                        file_path: row.get(1)?,
                        display_name: row.get(2)?,
                        added_at: row.get(3)?,
                    })
                },
            )
            .map_err(map_sql_err)
        })
    }

    pub fn list_shelf_items(&self) -> IslandResult<Vec<ShelfItemRecord>> {
        self.storage.with_conn(|conn| {
            let mut stmt = conn
                .prepare(
                    "SELECT id, file_path, display_name, added_at
                     FROM shelf_items
                     ORDER BY added_at DESC, id DESC",
                )
                .map_err(map_sql_err)?;
            let rows = stmt
                .query_map([], |row| {
                    Ok(ShelfItemRecord {
                        id: row.get(0)?,
                        file_path: row.get(1)?,
                        display_name: row.get(2)?,
                        added_at: row.get(3)?,
                    })
                })
                .map_err(map_sql_err)?;
            rows.collect::<Result<Vec<_>, _>>().map_err(map_sql_err)
        })
    }

    pub fn remove_shelf_item(&self, item_id: i64) -> IslandResult<()> {
        self.storage.with_conn(|conn| {
            conn.execute("DELETE FROM shelf_items WHERE id = ?1", params![item_id])
                .map_err(map_sql_err)?;
            Ok(())
        })
    }

    pub fn clear_shelf(&self) -> IslandResult<()> {
        self.storage.with_conn(|conn| {
            conn.execute("DELETE FROM shelf_items", [])
                .map_err(map_sql_err)?;
            Ok(())
        })
    }
}
