//! Application Core coordinating the Island state machine, EventBus, and SQLite repositories.

pub mod event_bus;
pub mod state_machine;

use event_bus::{DomainEvent, EventBus};
use island_common::{AppConfig, IslandError, IslandResult, RetentionPolicy};
use island_storage::{
    repositories::{
        DisplayProfileRecord, DisplayProfileRepository, ModuleSettingRecord,
        ModuleSettingsRepository, SettingsRepository,
    },
    Storage,
};
use state_machine::{ActiveActivity, IslandStateMachine, IslandStateSnapshot, PeekPreview};
use std::sync::{Arc, Mutex};

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
    }
}
