//! Dynamic Island state machine implementing PRD Section 6 rules:
//! 1. Only one primary state can be active.
//! 2. Debounce repeated interactions.
//! 3. Cancel obsolete transitions safely (via monotonic transition_epoch).
//! 4. Do not auto-collapse during active interaction.
//! 5. Prioritize important activities over previews.

use island_common::{IslandError, IslandResult};
use serde::{Deserialize, Serialize};

/// Primary states supported by the Dynamic Island Engine (PRD Section 6).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum IslandPrimaryState {
    Hidden,
    Collapsed,
    Peek,
    Expanded,
    Activity,
    Pinned,
}

/// Active live activity summary displayed in `Activity` state.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ActiveActivity {
    pub id: String,
    pub kind: String,
    pub title: String,
    pub subtitle: String,
}

/// Transient preview summary displayed in `Peek` state.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PeekPreview {
    pub source: String,
    pub title: String,
    pub subtitle: String,
}

/// Complete immutable snapshot of the Island state.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct IslandStateSnapshot {
    pub primary: IslandPrimaryState,
    pub is_transitioning: bool,
    pub is_interacting: bool,
    pub transition_epoch: u64,
    pub last_interaction_ms: u64,
    pub active_activity: Option<ActiveActivity>,
    pub active_peek: Option<PeekPreview>,
}

impl Default for IslandStateSnapshot {
    fn default() -> Self {
        Self {
            primary: IslandPrimaryState::Collapsed,
            is_transitioning: false,
            is_interacting: false,
            transition_epoch: 1,
            last_interaction_ms: 0,
            active_activity: None,
            active_peek: None,
        }
    }
}

pub struct IslandStateMachine {
    state: IslandStateSnapshot,
    debounce_window_ms: u64,
}

impl Default for IslandStateMachine {
    fn default() -> Self {
        Self::new(120)
    }
}

impl IslandStateMachine {
    pub fn new(debounce_window_ms: u64) -> Self {
        Self {
            state: IslandStateSnapshot::default(),
            debounce_window_ms,
        }
    }

    pub fn snapshot(&self) -> IslandStateSnapshot {
        self.state.clone()
    }

    /// Sets whether the user is actively interacting (hovering inside expanded panel, typing, dragging).
    /// Rule 4: Do not auto-collapse during active interaction.
    pub fn set_interacting(&mut self, interacting: bool, now_ms: u64) -> IslandStateSnapshot {
        self.state.is_interacting = interacting;
        if interacting {
            self.state.last_interaction_ms = now_ms;
        }
        self.state.clone()
    }

    /// Expands the Island via hover or click, subject to debounce (Rule 2).
    pub fn expand(&mut self, now_ms: u64) -> IslandResult<IslandStateSnapshot> {
        if self.state.primary == IslandPrimaryState::Hidden {
            return Err(IslandError::InvalidTransition {
                from: "Hidden".to_string(),
                to: "Expanded".to_string(),
                reason: "Unhide the island before expanding".to_string(),
            });
        }
        if self.state.primary == IslandPrimaryState::Pinned {
            return Ok(self.state.clone());
        }
        if self.is_debounced(now_ms) && self.state.primary == IslandPrimaryState::Expanded {
            return Ok(self.state.clone());
        }

        self.advance_epoch(now_ms);
        self.state.primary = IslandPrimaryState::Expanded;
        self.state.is_interacting = true;
        Ok(self.state.clone())
    }

    /// Pins the Island open so auto-collapse is disabled until unpinned.
    pub fn pin(&mut self, now_ms: u64) -> IslandResult<IslandStateSnapshot> {
        if self.state.primary == IslandPrimaryState::Hidden {
            return Err(IslandError::InvalidTransition {
                from: "Hidden".to_string(),
                to: "Pinned".to_string(),
                reason: "Cannot pin while hidden".to_string(),
            });
        }
        self.advance_epoch(now_ms);
        self.state.primary = IslandPrimaryState::Pinned;
        Ok(self.state.clone())
    }

    /// Unpins the Island, returning to `Expanded` if interacting or collapsing to resting state.
    pub fn unpin(&mut self, now_ms: u64) -> IslandStateSnapshot {
        if self.state.primary == IslandPrimaryState::Pinned {
            self.advance_epoch(now_ms);
            self.state.primary = if self.state.is_interacting {
                IslandPrimaryState::Expanded
            } else {
                self.resting_state()
            };
        }
        self.state.clone()
    }

    /// Attempts to auto-collapse the Island (e.g. after mouse exit or Peek timeout).
    /// Enforces Rule 3 (epoch check) and Rule 4 (never auto-collapse during active interaction or when Pinned).
    pub fn try_auto_collapse(
        &mut self,
        expected_epoch: Option<u64>,
        now_ms: u64,
    ) -> IslandResult<IslandStateSnapshot> {
        if let Some(epoch) = expected_epoch {
            if epoch != self.state.transition_epoch {
                // Rule 3: Cancel obsolete transitions safely.
                return Ok(self.state.clone());
            }
        }

        if self.state.is_interacting || self.state.primary == IslandPrimaryState::Pinned {
            // Rule 4: Do not auto-collapse during active interaction or while pinned.
            return Ok(self.state.clone());
        }

        if self.state.primary != IslandPrimaryState::Hidden {
            self.advance_epoch(now_ms);
            self.state.active_peek = None;
            self.state.primary = self.resting_state();
        }
        Ok(self.state.clone())
    }

    /// Starts or updates an important Live Activity (Timer, Pomodoro, Keep Awake).
    /// Rule 5: Prioritize important activities over previews.
    pub fn start_activity(
        &mut self,
        activity: ActiveActivity,
        now_ms: u64,
    ) -> IslandStateSnapshot {
        self.state.active_activity = Some(activity);
        self.state.active_peek = None;

        if matches!(
            self.state.primary,
            IslandPrimaryState::Collapsed | IslandPrimaryState::Peek
        ) {
            self.advance_epoch(now_ms);
            self.state.primary = IslandPrimaryState::Activity;
        }
        self.state.clone()
    }

    /// Stops the active Live Activity and returns to `Collapsed` if currently in `Activity` state.
    pub fn clear_activity(&mut self, now_ms: u64) -> IslandStateSnapshot {
        self.state.active_activity = None;
        if self.state.primary == IslandPrimaryState::Activity {
            self.advance_epoch(now_ms);
            self.state.primary = IslandPrimaryState::Collapsed;
        }
        self.state.clone()
    }

    /// Requests a transient `Peek` preview (e.g., track change or HUD).
    /// Rule 5: Prioritize important activities over previews (if an `Activity` is active, do not overwrite it).
    pub fn request_peek(&mut self, preview: PeekPreview, now_ms: u64) -> IslandStateSnapshot {
        if self.state.active_activity.is_some() {
            // Rule 5: Activity has higher priority than transient Peek preview.
            return self.state.clone();
        }
        if matches!(
            self.state.primary,
            IslandPrimaryState::Expanded | IslandPrimaryState::Pinned | IslandPrimaryState::Hidden
        ) {
            return self.state.clone();
        }

        self.advance_epoch(now_ms);
        self.state.active_peek = Some(preview);
        self.state.primary = IslandPrimaryState::Peek;
        self.state.clone()
    }

    /// Hides or unhides the Island (e.g., user toggle or fullscreen policy).
    pub fn set_hidden(&mut self, hidden: bool, now_ms: u64) -> IslandStateSnapshot {
        self.advance_epoch(now_ms);
        if hidden {
            self.state.is_interacting = false;
            self.state.primary = IslandPrimaryState::Hidden;
        } else if self.state.primary == IslandPrimaryState::Hidden {
            self.state.primary = self.resting_state();
        }
        self.state.clone()
    }

    /// Marks the current animation transition as completed for the given epoch.
    pub fn complete_transition(&mut self, epoch: u64) -> IslandStateSnapshot {
        if self.state.transition_epoch == epoch {
            self.state.is_transitioning = false;
        }
        self.state.clone()
    }

    fn resting_state(&self) -> IslandPrimaryState {
        if self.state.active_activity.is_some() {
            IslandPrimaryState::Activity
        } else {
            IslandPrimaryState::Collapsed
        }
    }

    fn is_debounced(&self, now_ms: u64) -> bool {
        now_ms.saturating_sub(self.state.last_interaction_ms) < self.debounce_window_ms
    }

    fn advance_epoch(&mut self, now_ms: u64) {
        self.state.transition_epoch += 1;
        self.state.is_transitioning = true;
        self.state.last_interaction_ms = now_ms;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rule_1_and_4_expand_and_block_auto_collapse_while_interacting() {
        let mut sm = IslandStateMachine::new(100);
        assert_eq!(sm.snapshot().primary, IslandPrimaryState::Collapsed);

        let snap = sm.expand(1_000).expect("expand succeeds");
        assert_eq!(snap.primary, IslandPrimaryState::Expanded);
        assert!(snap.is_interacting);

        // Rule 4: auto-collapse must be ignored while interacting is true
        let snap_after = sm.try_auto_collapse(None, 1_500).expect("try collapse");
        assert_eq!(snap_after.primary, IslandPrimaryState::Expanded);

        // Once interaction ends, auto-collapse succeeds
        sm.set_interacting(false, 1_600);
        let collapsed = sm.try_auto_collapse(None, 1_850).expect("collapse");
        assert_eq!(collapsed.primary, IslandPrimaryState::Collapsed);
    }

    #[test]
    fn rule_3_obsolete_transition_epoch_is_ignored() {
        let mut sm = IslandStateMachine::new(100);
        let peek_snap = sm.request_peek(
            PeekPreview {
                source: "media".to_string(),
                title: "Song A".to_string(),
                subtitle: "Artist".to_string(),
            },
            1_000,
        );
        assert_eq!(peek_snap.primary, IslandPrimaryState::Peek);
        let old_epoch = peek_snap.transition_epoch;

        // User expands Island before Peek timeout fires
        sm.expand(1_200).expect("expand");
        sm.set_interacting(false, 1_300);

        // Obsolete timer from Peek tries to collapse with old_epoch -> ignored
        let after_obsolete = sm
            .try_auto_collapse(Some(old_epoch), 2_000)
            .expect("obsolete collapse");
        assert_eq!(after_obsolete.primary, IslandPrimaryState::Expanded);
    }

    #[test]
    fn rule_5_activity_prioritized_over_peek() {
        let mut sm = IslandStateMachine::new(100);
        let act_snap = sm.start_activity(
            ActiveActivity {
                id: "pomodoro-1".to_string(),
                kind: "timer".to_string(),
                title: "24:59".to_string(),
                subtitle: "Focus".to_string(),
            },
            1_000,
        );
        assert_eq!(act_snap.primary, IslandPrimaryState::Activity);

        // Requesting a Peek while Activity is running keeps Activity primary
        let after_peek = sm.request_peek(
            PeekPreview {
                source: "volume".to_string(),
                title: "Volume 75%".to_string(),
                subtitle: "".to_string(),
            },
            1_200,
        );
        assert_eq!(after_peek.primary, IslandPrimaryState::Activity);
        assert!(after_peek.active_peek.is_none());

        // Expanding and then collapsing while Activity is active returns to Activity, not Collapsed
        sm.expand(1_500).expect("expand");
        sm.set_interacting(false, 1_700);
        let collapsed_to_activity = sm.try_auto_collapse(None, 2_000).expect("collapse");
        assert_eq!(collapsed_to_activity.primary, IslandPrimaryState::Activity);
    }
}
