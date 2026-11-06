//! System telemetry normalization and threshold-based HUD Peek rules (PRD FR-005).

use crate::state_machine::PeekPreview;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SystemTelemetry {
    pub cpu_usage_percent: f64,
    pub memory_used_gb: f64,
    pub memory_total_gb: f64,
    pub battery_percent: u32,
    pub is_charging: bool,
    pub volume_percent: u32,
    pub is_muted: bool,
}

impl Default for SystemTelemetry {
    fn default() -> Self {
        Self {
            cpu_usage_percent: 0.0,
            memory_used_gb: 0.0,
            memory_total_gb: 16.0,
            battery_percent: 100,
            is_charging: true,
            volume_percent: 50,
            is_muted: false,
        }
    }
}

impl SystemTelemetry {
    pub fn normalized(mut self) -> Self {
        self.cpu_usage_percent = self.cpu_usage_percent.clamp(0.0, 100.0);
        self.battery_percent = self.battery_percent.min(100);
        self.volume_percent = self.volume_percent.min(100);
        if self.memory_total_gb <= 0.0 {
            self.memory_total_gb = 1.0;
        }
        self.memory_used_gb = self.memory_used_gb.clamp(0.0, self.memory_total_gb);
        self
    }

    /// Evaluates whether a HUD `PeekPreview` should fire based on changes from `previous`.
    pub fn evaluate_hud_peek(&self, previous: Option<&Self>) -> Option<PeekPreview> {
        let Some(prev) = previous else {
            return None;
        };

        if self.is_muted != prev.is_muted || self.volume_percent != prev.volume_percent {
            let title = if self.is_muted || self.volume_percent == 0 {
                "Audio Muted".to_string()
            } else {
                format!("Volume {}%", self.volume_percent)
            };
            return Some(PeekPreview {
                source: "volume_hud".to_string(),
                title,
                subtitle: "System Audio".to_string(),
            });
        }

        if !self.is_charging && self.battery_percent <= 20 && prev.battery_percent > 20 {
            return Some(PeekPreview {
                source: "battery_hud".to_string(),
                title: format!("Low Battery ({}%)", self.battery_percent),
                subtitle: "Connect power adapter".to_string(),
            });
        }

        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn triggers_volume_and_low_battery_hud_peeks() {
        let base = SystemTelemetry::default();

        let mut vol_changed = base.clone();
        vol_changed.volume_percent = 75;
        let peek = vol_changed.evaluate_hud_peek(Some(&base)).expect("volume peek");
        assert_eq!(peek.source, "volume_hud");
        assert_eq!(peek.title, "Volume 75%");

        let mut low_batt = base.clone();
        low_batt.is_charging = false;
        low_batt.battery_percent = 19;
        let batt_peek = low_batt
            .evaluate_hud_peek(Some(&base))
            .expect("low battery peek");
        assert_eq!(batt_peek.source, "battery_hud");
    }
}
