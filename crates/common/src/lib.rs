//! Common types, error definitions, configuration, and logging initialization for Project Island.

use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::Once;
use std::time::{SystemTime, UNIX_EPOCH};
use thiserror::Error;

/// Unified error type across Project Island Rust crates.
#[derive(Debug, Error, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum IslandError {
    #[error("Storage error: {0}")]
    Storage(String),

    #[error("Validation error: {0}")]
    Validation(String),

    #[error("Not found: {0}")]
    NotFound(String),

    #[error("Permission denied: {0}")]
    PermissionDenied(String),

    #[error("Invalid state transition from {from} to {to}: {reason}")]
    InvalidTransition {
        from: String,
        to: String,
        reason: String,
    },

    #[error("Privacy policy blocked item: {0}")]
    PrivacyFiltered(String),

    #[error("Internal error: {0}")]
    Internal(String),
}

pub type IslandResult<T> = Result<T, IslandError>;

/// Application-wide configuration for core paths and default retention policies.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppConfig {
    pub database_path: PathBuf,
    pub log_level: String,
    pub retention: RetentionPolicy,
}

/// Configurable data retention policies in days (PRD Section 7).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RetentionPolicy {
    pub clipboard_days: u32,
    pub timer_history_days: u32,
    pub activity_events_days: u32,
    pub logs_days: u32,
}

impl Default for RetentionPolicy {
    fn default() -> Self {
        Self {
            clipboard_days: 7,
            timer_history_days: 90,
            activity_events_days: 7,
            logs_days: 7,
        }
    }
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            database_path: PathBuf::from("project_island.db"),
            log_level: "info".to_string(),
            retention: RetentionPolicy::default(),
        }
    }
}

impl AppConfig {
    /// Validates configuration values before startup.
    pub fn validate(&self) -> IslandResult<()> {
        if self.database_path.as_os_str().is_empty() {
            return Err(IslandError::Validation(
                "database_path must not be empty".to_string(),
            ));
        }
        if self.retention.clipboard_days == 0
            || self.retention.timer_history_days == 0
            || self.retention.activity_events_days == 0
            || self.retention.logs_days == 0
        {
            return Err(IslandError::Validation(
                "retention days must be greater than zero".to_string(),
            ));
        }
        Ok(())
    }
}

static TRACING_INIT: Once = Once::new();

/// Initializes structured tracing once per process.
pub fn init_logging(default_level: &str) {
    TRACING_INIT.call_once(|| {
        let filter = tracing_subscriber::EnvFilter::try_from_default_env()
            .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new(default_level));
        let _ = tracing_subscriber::fmt()
            .with_env_filter(filter)
            .with_target(true)
            .try_init();
    });
}

/// Returns current Unix timestamp in seconds.
pub fn unix_timestamp_secs() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_config_is_valid() {
        let cfg = AppConfig::default();
        assert!(cfg.validate().is_ok());
        assert_eq!(cfg.retention.clipboard_days, 7);
        assert_eq!(cfg.retention.timer_history_days, 90);
        assert_eq!(cfg.retention.activity_events_days, 7);
        assert_eq!(cfg.retention.logs_days, 7);
    }

    #[test]
    fn rejects_empty_db_path_or_zero_retention() {
        let mut cfg = AppConfig::default();
        cfg.database_path = PathBuf::new();
        assert!(matches!(cfg.validate(), Err(IslandError::Validation(_))));

        let mut cfg2 = AppConfig::default();
        cfg2.retention.clipboard_days = 0;
        assert!(matches!(cfg2.validate(), Err(IslandError::Validation(_))));
    }

    #[test]
    fn logging_init_is_idempotent() {
        init_logging("debug");
        init_logging("info");
        assert!(unix_timestamp_secs() > 1_700_000_000);
    }
}
