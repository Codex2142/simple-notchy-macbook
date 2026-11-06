//! UniFFI bridge exposing `IslandCore` to Swift/AppKit.
//! UI components communicate strictly through typed commands, snapshots, and listener callbacks.

use island_common::{AppConfig, IslandError, RetentionPolicy};
use island_core::{
    clipboard::ClipboardCaptureCandidate,
    event_bus::DomainEvent,
    media::NowPlayingTrack,
    state_machine::{ActiveActivity, IslandPrimaryState, IslandStateSnapshot, PeekPreview},
    system::SystemTelemetry,
    AppCoordinator,
};
use island_storage::{
    clipboard_repo::ClipboardItemRecord,
    notes_shelf_repo::{NoteRecord, ShelfItemRecord},
    repositories::{DisplayProfileRecord, ModuleSettingRecord},
    timer_repo::TimerSessionRecord,
};
use std::path::PathBuf;
use std::sync::Arc;

uniffi::setup_scaffolding!();

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum FfiError {
    #[error("Storage error: {message}")]
    Storage { message: String },
    #[error("Validation error: {message}")]
    Validation { message: String },
    #[error("Invalid transition: {message}")]
    InvalidTransition { message: String },
    #[error("Privacy policy blocked item: {message}")]
    PrivacyFiltered { message: String },
    #[error("Internal error: {message}")]
    Internal { message: String },
}

impl From<IslandError> for FfiError {
    fn from(err: IslandError) -> Self {
        match err {
            IslandError::Storage(message) => Self::Storage { message },
            IslandError::Validation(message) => Self::Validation { message },
            IslandError::InvalidTransition { from, to, reason } => Self::InvalidTransition {
                message: format!("{from} -> {to}: {reason}"),
            },
            IslandError::PrivacyFiltered(message) => Self::PrivacyFiltered { message },
            other => Self::Internal {
                message: other.to_string(),
            },
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum FfiIslandMode {
    Hidden,
    Collapsed,
    Peek,
    Expanded,
    Activity,
    Pinned,
}

impl From<IslandPrimaryState> for FfiIslandMode {
    fn from(state: IslandPrimaryState) -> Self {
        match state {
            IslandPrimaryState::Hidden => Self::Hidden,
            IslandPrimaryState::Collapsed => Self::Collapsed,
            IslandPrimaryState::Peek => Self::Peek,
            IslandPrimaryState::Expanded => Self::Expanded,
            IslandPrimaryState::Activity => Self::Activity,
            IslandPrimaryState::Pinned => Self::Pinned,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiActivityInfo {
    pub id: String,
    pub kind: String,
    pub title: String,
    pub subtitle: String,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiPeekInfo {
    pub source: String,
    pub title: String,
    pub subtitle: String,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiIslandViewState {
    pub mode: FfiIslandMode,
    pub is_transitioning: bool,
    pub is_interacting: bool,
    pub transition_epoch: u64,
    pub active_activity: Option<FfiActivityInfo>,
    pub active_peek: Option<FfiPeekInfo>,
}

impl From<IslandStateSnapshot> for FfiIslandViewState {
    fn from(s: IslandStateSnapshot) -> Self {
        Self {
            mode: s.primary.into(),
            is_transitioning: s.is_transitioning,
            is_interacting: s.is_interacting,
            transition_epoch: s.transition_epoch,
            active_activity: s.active_activity.map(|a| FfiActivityInfo {
                id: a.id,
                kind: a.kind,
                title: a.title,
                subtitle: a.subtitle,
            }),
            active_peek: s.active_peek.map(|p| FfiPeekInfo {
                source: p.source,
                title: p.title,
                subtitle: p.subtitle,
            }),
        }
    }
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiDisplayProfile {
    pub display_uuid: String,
    pub name: String,
    pub has_hardware_notch: bool,
    pub notch_width: f64,
    pub notch_height: f64,
    pub virtual_island_enabled: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiModuleSetting {
    pub module_id: String,
    pub enabled: bool,
    pub config_json: String,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiRetentionPolicy {
    pub clipboard_days: u32,
    pub timer_history_days: u32,
    pub activity_events_days: u32,
    pub logs_days: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiClipboardItem {
    pub id: i64,
    pub content_type: String,
    pub text_content: String,
    pub source_app: String,
    pub is_pinned: bool,
    pub created_at: i64,
    pub updated_at: i64,
}

impl From<ClipboardItemRecord> for FfiClipboardItem {
    fn from(r: ClipboardItemRecord) -> Self {
        Self {
            id: r.id,
            content_type: r.content_type,
            text_content: r.text_content,
            source_app: r.source_app,
            is_pinned: r.is_pinned,
            created_at: r.created_at,
            updated_at: r.updated_at,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiClipboardCaptureInput {
    pub content_type: String,
    pub text_content: String,
    pub source_app: String,
    pub pasteboard_types: Vec<String>,
    pub is_secure_input_active: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiTimerSession {
    pub id: i64,
    pub kind: String,
    pub label: String,
    pub duration_secs: u32,
    pub started_at: i64,
    pub completed_at: Option<i64>,
    pub status: String,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiNowPlayingTrack {
    pub source_app: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration_secs: u32,
    pub elapsed_secs: u32,
    pub is_playing: bool,
}

impl From<NowPlayingTrack> for FfiNowPlayingTrack {
    fn from(t: NowPlayingTrack) -> Self {
        Self {
            source_app: t.source_app,
            title: t.title,
            artist: t.artist,
            album: t.album,
            duration_secs: t.duration_secs,
            elapsed_secs: t.elapsed_secs,
            is_playing: t.is_playing,
        }
    }
}

impl From<FfiNowPlayingTrack> for NowPlayingTrack {
    fn from(t: FfiNowPlayingTrack) -> Self {
        Self {
            source_app: t.source_app,
            title: t.title,
            artist: t.artist,
            album: t.album,
            duration_secs: t.duration_secs,
            elapsed_secs: t.elapsed_secs,
            is_playing: t.is_playing,
        }
    }
}

#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct FfiSystemTelemetry {
    pub cpu_usage_percent: f64,
    pub memory_used_gb: f64,
    pub memory_total_gb: f64,
    pub battery_percent: u32,
    pub is_charging: bool,
    pub volume_percent: u32,
    pub is_muted: bool,
}

impl From<SystemTelemetry> for FfiSystemTelemetry {
    fn from(t: SystemTelemetry) -> Self {
        Self {
            cpu_usage_percent: t.cpu_usage_percent,
            memory_used_gb: t.memory_used_gb,
            memory_total_gb: t.memory_total_gb,
            battery_percent: t.battery_percent,
            is_charging: t.is_charging,
            volume_percent: t.volume_percent,
            is_muted: t.is_muted,
        }
    }
}

impl From<FfiSystemTelemetry> for SystemTelemetry {
    fn from(t: FfiSystemTelemetry) -> Self {
        Self {
            cpu_usage_percent: t.cpu_usage_percent,
            memory_used_gb: t.memory_used_gb,
            memory_total_gb: t.memory_total_gb,
            battery_percent: t.battery_percent,
            is_charging: t.is_charging,
            volume_percent: t.volume_percent,
            is_muted: t.is_muted,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiNoteItem {
    pub id: i64,
    pub title: String,
    pub content: String,
    pub updated_at: i64,
}

impl From<NoteRecord> for FfiNoteItem {
    fn from(n: NoteRecord) -> Self {
        Self {
            id: n.id,
            title: n.title,
            content: n.content,
            updated_at: n.updated_at,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct FfiShelfItem {
    pub id: i64,
    pub file_path: String,
    pub display_name: String,
    pub added_at: i64,
}

impl From<ShelfItemRecord> for FfiShelfItem {
    fn from(s: ShelfItemRecord) -> Self {
        Self {
            id: s.id,
            file_path: s.file_path,
            display_name: s.display_name,
            added_at: s.added_at,
        }
    }
}

impl From<TimerSessionRecord> for FfiTimerSession {
    fn from(r: TimerSessionRecord) -> Self {
        Self {
            id: r.id,
            kind: r.kind,
            label: r.label,
            duration_secs: r.duration_secs,
            started_at: r.started_at,
            completed_at: r.completed_at,
            status: r.status,
        }
    }
}

impl From<RetentionPolicy> for FfiRetentionPolicy {
    fn from(p: RetentionPolicy) -> Self {
        Self {
            clipboard_days: p.clipboard_days,
            timer_history_days: p.timer_history_days,
            activity_events_days: p.activity_events_days,
            logs_days: p.logs_days,
        }
    }
}

impl From<FfiRetentionPolicy> for RetentionPolicy {
    fn from(p: FfiRetentionPolicy) -> Self {
        Self {
            clipboard_days: p.clipboard_days,
            timer_history_days: p.timer_history_days,
            activity_events_days: p.activity_events_days,
            logs_days: p.logs_days,
        }
    }
}

#[uniffi::export(callback_interface)]
pub trait IslandStateListener: Send + Sync {
    fn on_state_changed(&self, new_state: FfiIslandViewState);
}

#[derive(uniffi::Object)]
pub struct IslandCore {
    coordinator: AppCoordinator,
}

#[uniffi::export]
impl IslandCore {
    /// Initializes `IslandCore` with a SQLite database at `database_path`.
    #[uniffi::constructor]
    pub fn new(database_path: String) -> Result<Arc<Self>, FfiError> {
        let config = AppConfig {
            database_path: PathBuf::from(database_path),
            ..AppConfig::default()
        };
        let coordinator = AppCoordinator::new(&config)?;
        Ok(Arc::new(Self { coordinator }))
    }

    /// Initializes an in-memory `IslandCore` instance for previews and tests.
    #[uniffi::constructor]
    pub fn new_in_memory() -> Result<Arc<Self>, FfiError> {
        let coordinator = AppCoordinator::new_in_memory()?;
        Ok(Arc::new(Self { coordinator }))
    }

    /// Subscribes a Swift listener to receive state snapshots whenever the Island changes state.
    pub fn add_state_listener(&self, listener: Box<dyn IslandStateListener>) {
        let listener: Arc<dyn IslandStateListener> = Arc::from(listener);
        self.coordinator.event_bus().subscribe(move |event| {
            if let DomainEvent::StateChanged(snapshot) = event {
                listener.on_state_changed(snapshot.clone().into());
            }
        });
    }

    pub fn current_state(&self) -> Result<FfiIslandViewState, FfiError> {
        Ok(self.coordinator.state_snapshot()?.into())
    }

    pub fn expand(&self, now_ms: u64) -> Result<FfiIslandViewState, FfiError> {
        Ok(self.coordinator.expand(now_ms)?.into())
    }

    pub fn pin(&self, now_ms: u64) -> Result<FfiIslandViewState, FfiError> {
        Ok(self.coordinator.pin(now_ms)?.into())
    }

    pub fn unpin(&self, now_ms: u64) -> Result<FfiIslandViewState, FfiError> {
        Ok(self.coordinator.unpin(now_ms)?.into())
    }

    pub fn set_interacting(
        &self,
        interacting: bool,
        now_ms: u64,
    ) -> Result<FfiIslandViewState, FfiError> {
        Ok(self.coordinator.set_interacting(interacting, now_ms)?.into())
    }

    pub fn try_auto_collapse(
        &self,
        expected_epoch: Option<u64>,
        now_ms: u64,
    ) -> Result<FfiIslandViewState, FfiError> {
        Ok(self
            .coordinator
            .try_auto_collapse(expected_epoch, now_ms)?
            .into())
    }

    pub fn start_activity(
        &self,
        activity: FfiActivityInfo,
        now_ms: u64,
    ) -> Result<FfiIslandViewState, FfiError> {
        Ok(self
            .coordinator
            .start_activity(
                ActiveActivity {
                    id: activity.id,
                    kind: activity.kind,
                    title: activity.title,
                    subtitle: activity.subtitle,
                },
                now_ms,
            )?
            .into())
    }

    pub fn clear_activity(&self, now_ms: u64) -> Result<FfiIslandViewState, FfiError> {
        Ok(self.coordinator.clear_activity(now_ms)?.into())
    }

    pub fn request_peek(
        &self,
        preview: FfiPeekInfo,
        now_ms: u64,
    ) -> Result<FfiIslandViewState, FfiError> {
        Ok(self
            .coordinator
            .request_peek(
                PeekPreview {
                    source: preview.source,
                    title: preview.title,
                    subtitle: preview.subtitle,
                },
                now_ms,
            )?
            .into())
    }

    pub fn set_hidden(&self, hidden: bool, now_ms: u64) -> Result<FfiIslandViewState, FfiError> {
        Ok(self.coordinator.set_hidden(hidden, now_ms)?.into())
    }

    pub fn register_display_profile(&self, profile: FfiDisplayProfile) -> Result<(), FfiError> {
        self.coordinator
            .register_display_profile(&DisplayProfileRecord {
                display_uuid: profile.display_uuid,
                name: profile.name,
                has_hardware_notch: profile.has_hardware_notch,
                notch_width: profile.notch_width,
                notch_height: profile.notch_height,
                virtual_island_enabled: profile.virtual_island_enabled,
                updated_at: island_common::unix_timestamp_secs(),
            })?;
        Ok(())
    }

    pub fn list_display_profiles(&self) -> Result<Vec<FfiDisplayProfile>, FfiError> {
        let profiles = self.coordinator.list_display_profiles()?;
        Ok(profiles
            .into_iter()
            .map(|p| FfiDisplayProfile {
                display_uuid: p.display_uuid,
                name: p.name,
                has_hardware_notch: p.has_hardware_notch,
                notch_width: p.notch_width,
                notch_height: p.notch_height,
                virtual_island_enabled: p.virtual_island_enabled,
            })
            .collect())
    }

    pub fn set_module_enabled(
        &self,
        module_id: String,
        enabled: bool,
        config_json: String,
    ) -> Result<(), FfiError> {
        self.coordinator
            .set_module_enabled(&module_id, enabled, &config_json)?;
        Ok(())
    }

    pub fn list_modules(&self) -> Result<Vec<FfiModuleSetting>, FfiError> {
        let modules = self.coordinator.list_modules()?;
        Ok(modules
            .into_iter()
            .map(|m: ModuleSettingRecord| FfiModuleSetting {
                module_id: m.module_id,
                enabled: m.enabled,
                config_json: m.config_json,
            })
            .collect())
    }

    pub fn get_retention_policy(&self) -> Result<FfiRetentionPolicy, FfiError> {
        Ok(self.coordinator.get_retention_policy()?.into())
    }

    pub fn set_retention_policy(&self, policy: FfiRetentionPolicy) -> Result<(), FfiError> {
        self.coordinator.set_retention_policy(&policy.into())?;
        Ok(())
    }

    pub fn capture_clipboard_item(
        &self,
        input: FfiClipboardCaptureInput,
        now_secs: i64,
    ) -> Result<FfiClipboardItem, FfiError> {
        let item = self.coordinator.capture_clipboard_item(
            &ClipboardCaptureCandidate {
                content_type: input.content_type,
                text_content: input.text_content,
                source_app: input.source_app,
                pasteboard_types: input.pasteboard_types,
                is_secure_input_active: input.is_secure_input_active,
            },
            now_secs,
        )?;
        Ok(item.into())
    }

    pub fn list_clipboard_items(
        &self,
        query: Option<String>,
        limit: u32,
    ) -> Result<Vec<FfiClipboardItem>, FfiError> {
        let items = self
            .coordinator
            .list_clipboard_items(query.as_deref(), limit as usize)?;
        Ok(items.into_iter().map(Into::into).collect())
    }

    pub fn set_clipboard_item_pinned(&self, item_id: i64, pinned: bool) -> Result<(), FfiError> {
        self.coordinator.set_clipboard_item_pinned(item_id, pinned)?;
        Ok(())
    }

    pub fn delete_clipboard_item(&self, item_id: i64) -> Result<(), FfiError> {
        self.coordinator.delete_clipboard_item(item_id)?;
        Ok(())
    }

    pub fn start_timer_session(
        &self,
        kind: String,
        label: String,
        duration_secs: u32,
        now_secs: i64,
    ) -> Result<FfiTimerSession, FfiError> {
        Ok(self
            .coordinator
            .start_timer_session(&kind, &label, duration_secs, now_secs)?
            .into())
    }

    pub fn finish_timer_session(
        &self,
        session_id: i64,
        status: String,
        now_secs: i64,
    ) -> Result<FfiTimerSession, FfiError> {
        Ok(self
            .coordinator
            .finish_timer_session(session_id, &status, now_secs)?
            .into())
    }

    pub fn list_timer_sessions(&self, limit: u32) -> Result<Vec<FfiTimerSession>, FfiError> {
        let items = self.coordinator.list_timer_sessions(limit as usize)?;
        Ok(items.into_iter().map(Into::into).collect())
    }

    pub fn update_now_playing(
        &self,
        track: FfiNowPlayingTrack,
        now_ms: u64,
    ) -> Result<FfiIslandViewState, FfiError> {
        Ok(self
            .coordinator
            .update_now_playing(track.into(), now_ms)?
            .into())
    }

    pub fn current_now_playing(&self) -> Result<Option<FfiNowPlayingTrack>, FfiError> {
        Ok(self.coordinator.current_now_playing()?.map(Into::into))
    }

    pub fn update_system_telemetry(
        &self,
        metrics: FfiSystemTelemetry,
        now_ms: u64,
    ) -> Result<FfiIslandViewState, FfiError> {
        Ok(self
            .coordinator
            .update_system_telemetry(metrics.into(), now_ms)?
            .into())
    }

    pub fn current_system_telemetry(&self) -> Result<FfiSystemTelemetry, FfiError> {
        Ok(self.coordinator.current_system_telemetry()?.into())
    }

    pub fn save_note(
        &self,
        note_id: Option<i64>,
        title: String,
        content: String,
        now_secs: i64,
    ) -> Result<FfiNoteItem, FfiError> {
        Ok(self
            .coordinator
            .save_note(note_id, &title, &content, now_secs)?
            .into())
    }

    pub fn list_notes(&self, limit: u32) -> Result<Vec<FfiNoteItem>, FfiError> {
        let notes = self.coordinator.list_notes(limit as usize)?;
        Ok(notes.into_iter().map(Into::into).collect())
    }

    pub fn delete_note(&self, note_id: i64) -> Result<(), FfiError> {
        self.coordinator.delete_note(note_id)?;
        Ok(())
    }

    pub fn add_shelf_item(
        &self,
        file_path: String,
        display_name: String,
        now_secs: i64,
    ) -> Result<FfiShelfItem, FfiError> {
        Ok(self
            .coordinator
            .add_shelf_item(&file_path, &display_name, now_secs)?
            .into())
    }

    pub fn list_shelf_items(&self) -> Result<Vec<FfiShelfItem>, FfiError> {
        let items = self.coordinator.list_shelf_items()?;
        Ok(items.into_iter().map(Into::into).collect())
    }

    pub fn remove_shelf_item(&self, item_id: i64) -> Result<(), FfiError> {
        self.coordinator.remove_shelf_item(item_id)?;
        Ok(())
    }

    pub fn clear_shelf(&self) -> Result<(), FfiError> {
        self.coordinator.clear_shelf()?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    struct TestListener {
        calls: Arc<AtomicUsize>,
    }

    impl IslandStateListener for TestListener {
        fn on_state_changed(&self, _new_state: FfiIslandViewState) {
            self.calls.fetch_add(1, Ordering::SeqCst);
        }
    }

    #[test]
    fn ffi_contract_roundtrip_and_listener() {
        let core = IslandCore::new_in_memory().expect("create in-memory core");
        let calls = Arc::new(AtomicUsize::new(0));
        core.add_state_listener(Box::new(TestListener {
            calls: calls.clone(),
        }));

        let initial = core.current_state().expect("get state");
        assert_eq!(initial.mode, FfiIslandMode::Collapsed);

        let expanded = core.expand(1_000).expect("expand");
        assert_eq!(expanded.mode, FfiIslandMode::Expanded);
        assert_eq!(calls.load(Ordering::SeqCst), 1);

        let pinned = core.pin(1_100).expect("pin");
        assert_eq!(pinned.mode, FfiIslandMode::Pinned);
        assert_eq!(calls.load(Ordering::SeqCst), 2);
    }
}
