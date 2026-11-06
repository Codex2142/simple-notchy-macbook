//! Timer, Pomodoro, and Stopwatch formatting and validation helpers (PRD FR-004).

use island_common::{IslandError, IslandResult};

/// Formats remaining seconds into `MM:SS` or `HH:MM:SS` for the Island Live Activity pill.
pub fn format_duration_mm_ss(total_secs: u32) -> String {
    let hours = total_secs / 3600;
    let minutes = (total_secs % 3600) / 60;
    let seconds = total_secs % 60;
    if hours > 0 {
        format!("{hours:02}:{minutes:02}:{seconds:02}")
    } else {
        format!("{minutes:02}:{seconds:02}")
    }
}

pub fn validate_timer_request(kind: &str, label: &str, duration_secs: u32) -> IslandResult<()> {
    if !matches!(kind, "countdown" | "pomodoro" | "stopwatch" | "keep_awake") {
        return Err(IslandError::Validation(format!(
            "Unsupported timer kind: {kind}"
        )));
    }
    if label.trim().is_empty() {
        return Err(IslandError::Validation(
            "Timer label must not be empty".to_string(),
        ));
    }
    if kind != "stopwatch" && duration_secs == 0 {
        return Err(IslandError::Validation(
            "Timer duration must be greater than 0 seconds".to_string(),
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formats_mm_ss_and_hh_mm_ss() {
        assert_eq!(format_duration_mm_ss(1500), "25:00");
        assert_eq!(format_duration_mm_ss(65), "01:05");
        assert_eq!(format_duration_mm_ss(3661), "01:01:01");
    }

    #[test]
    fn validates_timer_inputs() {
        assert!(validate_timer_request("pomodoro", "Focus", 1500).is_ok());
        assert!(validate_timer_request("countdown", "Tea", 0).is_err());
        assert!(validate_timer_request("unknown", "Focus", 60).is_err());
    }
}
