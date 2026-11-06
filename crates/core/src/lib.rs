//! Application Core coordinating the Island state machine, EventBus, and SQLite repositories.

pub mod clipboard;
pub mod event_bus;
pub mod state_machine;
pub mod timer;

use clipboard::{validate_clipboard_candidate, ClipboardCaptureCandidate};
use event_bus::{DomainEvent, EventBus};
use island_common::{AppConfig, IslandError, IslandResult, RetentionPolicy};
use island_storage::{
    clipboard_repo::{ClipboardItemRecord, ClipboardRepository},
    repositories::{
        DisplayProfileRecord, DisplayProfileRepository, ModuleSettingRecord,
        ModuleSettingsRepository, SettingsRepository,
    },
    timer_repo::{TimerRepository, TimerSessionRecord},
    Storage,
};
use state_machine::{ActiveActivity, IslandStateMachine, IslandStateSnapshot, PeekPreview};
use std::sync::{Arc, Mutex};
use timer::{format_duration_mm_ss, validate_timer_request};

#[derive(Clone)]
pub struct AppCoordinator {
    storage: Storage,
    event_bus: EventBus,
    state_machine: Arc<Mutex<IslandStateMachine>>,
}

impl AppCoordinator {
    /// Creates a new `AppCoordinator` backed by the configured SQLite database.
    pub fn new(config: &AppConfig) -> IslandResult<Self> {
        config.validate()?;
        island_common::init_logging(&config.log_level);
        let storage = Storage::open(&config.database_path)?;
        Ok(Self::with_storage(storage))
    }

    /// Creates an in-memory `AppCoordinator` for unit/integration testing.
    pub fn new_in_memory() -> IslandResult<Self> {
        let storage = Storage::open_in_memory()?;
        Ok(Self::with_storage(storage))
    }

    pub fn with_storage(storage: Storage) -> Self {
        Self {
            storage,
            event_bus: EventBus::new(),
            state_machine: Arc::new(Mutex::new(IslandStateMachine::default())),
        }
    }

    pub fn event_bus(&self) -> &EventBus {
        &self.event_bus
    }

    pub fn storage(&self) -> &Storage {
        &self.storage
    }

    pub fn state_snapshot(&self) -> IslandResult<IslandStateSnapshot> {
        let sm = self.lock_sm()?;
        Ok(sm.snapshot())
    }

    pub fn expand(&self, now_ms: u64) -> IslandResult<IslandStateSnapshot> {
        let snap = {
            let mut sm = self.lock_sm()?;
            sm.expand(now_ms)?
        };
        self.event_bus.publish(&DomainEvent::StateChanged(snap.clone()));
        Ok(snap)
    }

    pub fn pin(&self, now_ms: u64) -> IslandResult<IslandStateSnapshot> {
        let snap = {
            let mut sm = self.lock_sm()?;
            sm.pin(now_ms)?
        };
        self.event_bus.publish(&DomainEvent::StateChanged(snap.clone()));
        Ok(snap)
    }

    pub fn unpin(&self, now_ms: u64) -> IslandResult<IslandStateSnapshot> {
        let snap = {
            let mut sm = self.lock_sm()?;
            sm.unpin(now_ms)
        };
        self.event_bus.publish(&DomainEvent::StateChanged(snap.clone()));
        Ok(snap)
    }

    pub fn set_interacting(&self, interacting: bool, now_ms: u64) -> IslandResult<IslandStateSnapshot> {
        let snap = {
            let mut sm = self.lock_sm()?;
            sm.set_interacting(interacting, now_ms)
        };
        self.event_bus.publish(&DomainEvent::StateChanged(snap.clone()));
        Ok(snap)
    }

    pub fn try_auto_collapse(
        &self,
        expected_epoch: Option<u64>,
        now_ms: u64,
    ) -> IslandResult<IslandStateSnapshot> {
        let snap = {
            let mut sm = self.lock_sm()?;
            sm.try_auto_collapse(expected_epoch, now_ms)?
        };
        self.event_bus.publish(&DomainEvent::StateChanged(snap.clone()));
        Ok(snap)
    }

    pub fn start_activity(
        &self,
        activity: ActiveActivity,
        now_ms: u64,
    ) -> IslandResult<IslandStateSnapshot> {
        let snap = {
            let mut sm = self.lock_sm()?;
            sm.start_activity(activity, now_ms)
        };
        self.event_bus.publish(&DomainEvent::StateChanged(snap.clone()));
        Ok(snap)
    }

    pub fn clear_activity(&self, now_ms: u64) -> IslandResult<IslandStateSnapshot> {
        let snap = {
            let mut sm = self.lock_sm()?;
            sm.clear_activity(now_ms)
        };
        self.event_bus.publish(&DomainEvent::StateChanged(snap.clone()));
        Ok(snap)
    }

    pub fn request_peek(&self, preview: PeekPreview, now_ms: u64) -> IslandResult<IslandStateSnapshot> {
        let snap = {
            let mut sm = self.lock_sm()?;
            sm.request_peek(preview, now_ms)
        };
        self.event_bus.publish(&DomainEvent::StateChanged(snap.clone()));
        Ok(snap)
    }

    pub fn set_hidden(&self, hidden: bool, now_ms: u64) -> IslandResult<IslandStateSnapshot> {
        let snap = {
            let mut sm = self.lock_sm()?;
            sm.set_hidden(hidden, now_ms)
        };
        self.event_bus.publish(&DomainEvent::StateChanged(snap.clone()));
        Ok(snap)
    }

    pub fn register_display_profile(&self, profile: &DisplayProfileRecord) -> IslandResult<()> {
        self.storage.display_profile_repo().upsert(profile)
    }

    pub fn list_display_profiles(&self) -> IslandResult<Vec<DisplayProfileRecord>> {
        self.storage.display_profile_repo().list_all()
    }

    pub fn set_module_enabled(
        &self,
        module_id: &str,
        enabled: bool,
        config_json: &str,
    ) -> IslandResult<()> {
        let record = ModuleSettingRecord {
            module_id: module_id.to_string(),
            enabled,
            config_json: config_json.to_string(),
            updated_at: island_common::unix_timestamp_secs(),
        };
        self.storage.module_settings_repo().upsert(&record)?;
        self.event_bus.publish(&DomainEvent::ModuleToggled {
            module_id: module_id.to_string(),
            enabled,
        });
        Ok(())
    }

    pub fn list_modules(&self) -> IslandResult<Vec<ModuleSettingRecord>> {
        self.storage.module_settings_repo().list_all()
    }

    pub fn get_retention_policy(&self) -> IslandResult<RetentionPolicy> {
        self.storage.settings_repo().get_retention_policy()
    }

    pub fn set_retention_policy(&self, policy: &RetentionPolicy) -> IslandResult<()> {
        self.storage.settings_repo().set_retention_policy(policy)?;
        self.event_bus
            .publish(&DomainEvent::RetentionPolicyUpdated(policy.clone()));
        Ok(())
    }

    pub fn capture_clipboard_item(
        &self,
        candidate: &ClipboardCaptureCandidate,
        now_secs: i64,
    ) -> IslandResult<ClipboardItemRecord> {
        validate_clipboard_candidate(candidate)?;
        let item = self.storage.clipboard_repo().insert_or_bump(
            &candidate.content_type,
            &candidate.text_content,
            &candidate.source_app,
            now_secs,
        )?;
        let retention = self.get_retention_policy()?;
        let _ = self
            .storage
            .clipboard_repo()
            .prune_expired(retention.clipboard_days, now_secs);
        Ok(item)
    }

    pub fn list_clipboard_items(
        &self,
        query: Option<&str>,
        limit: usize,
    ) -> IslandResult<Vec<ClipboardItemRecord>> {
        self.storage.clipboard_repo().list_or_search(query, limit)
    }

    pub fn set_clipboard_item_pinned(&self, item_id: i64, pinned: bool) -> IslandResult<()> {
        self.storage.clipboard_repo().set_pinned(item_id, pinned)
    }

    pub fn delete_clipboard_item(&self, item_id: i64) -> IslandResult<()> {
        self.storage.clipboard_repo().delete(item_id)
    }

    pub fn prune_expired_clipboard(&self, now_secs: i64) -> IslandResult<usize> {
        let retention = self.get_retention_policy()?;
        self.storage
            .clipboard_repo()
            .prune_expired(retention.clipboard_days, now_secs)
    }

    pub fn start_timer_session(
        &self,
        kind: &str,
        label: &str,
        duration_secs: u32,
        now_secs: i64,
    ) -> IslandResult<TimerSessionRecord> {
        validate_timer_request(kind, label, duration_secs)?;
        let record = self
            .storage
            .timer_repo()
            .create_session(kind, label, duration_secs, now_secs)?;
        let _ = self.start_activity(
            ActiveActivity {
                id: format!("timer-{}", record.id),
                kind: kind.to_string(),
                title: format_duration_mm_ss(duration_secs),
                subtitle: label.to_string(),
            },
            (now_secs as u64).saturating_mul(1000),
        )?;
        Ok(record)
    }

    pub fn finish_timer_session(
        &self,
        session_id: i64,
        status: &str,
        now_secs: i64,
    ) -> IslandResult<TimerSessionRecord> {
        let updated = self
            .storage
            .timer_repo()
            .finish_session(session_id, status, now_secs)?;
        let _ = self.clear_activity((now_secs as u64).saturating_mul(1000))?;
        Ok(updated)
    }

    pub fn list_timer_sessions(&self, limit: usize) -> IslandResult<Vec<TimerSessionRecord>> {
        self.storage.timer_repo().list_recent(limit)
    }

    fn lock_sm(&self) -> IslandResult<std::sync::MutexGuard<'_, IslandStateMachine>> {
        self.state_machine
            .lock()
            .map_err(|_| IslandError::Internal("State machine mutex poisoned".to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::state_machine::IslandPrimaryState;

    #[test]
    fn coordinator_emits_events_and_persists_settings() {
        let coord = AppCoordinator::new_in_memory().expect("create coordinator");
        let expanded = coord.expand(1_000).expect("expand");
        assert_eq!(expanded.primary, IslandPrimaryState::Expanded);

        coord
            .set_module_enabled("clipboard", true, "{}")
            .expect("enable clipboard");
        let modules = coord.list_modules().expect("list modules");
        assert_eq!(modules.len(), 1);
        assert!(modules[0].enabled);

        let item1 = coord
            .capture_clipboard_item(
                &ClipboardCaptureCandidate {
                    content_type: "public.utf8-plain-text".to_string(),
                    text_content: "first snippet".to_string(),
                    source_app: "Notes".to_string(),
                    pasteboard_types: vec!["public.utf8-plain-text".to_string()],
                    is_secure_input_active: false,
                },
                1_000,
            )
            .expect("capture first item");
        coord
            .set_clipboard_item_pinned(item1.id, true)
            .expect("pin item1");

        let _item2 = coord
            .capture_clipboard_item(
                &ClipboardCaptureCandidate {
                    content_type: "public.utf8-plain-text".to_string(),
                    text_content: "ephemeral text".to_string(),
                    source_app: "Safari".to_string(),
                    pasteboard_types: vec!["public.utf8-plain-text".to_string()],
                    is_secure_input_active: false,
                },
                1_100,
            )
            .expect("capture second item");

        // Advance time by 8 days -> item2 pruned, item1 kept because pinned
        let eight_days_later = 1_100 + 8 * 86_400;
        let pruned = coord
            .prune_expired_clipboard(eight_days_later)
            .expect("prune expired");
        assert_eq!(pruned, 1);

        let remaining = coord
            .list_clipboard_items(None, 20)
            .expect("list remaining");
        assert_eq!(remaining.len(), 1);
        assert_eq!(remaining[0].text_content, "first snippet");
        assert!(remaining[0].is_pinned);
    }
}
