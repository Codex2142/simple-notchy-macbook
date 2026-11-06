//! LRC synced lyrics parser and real-time playback timestamp synchronizer.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LyricLine {
    pub timestamp_ms: u64,
    pub text: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct LyricSyncSnapshot {
    pub lines: Vec<LyricLine>,
    pub current_index: i32,
    pub previous_line: String,
    pub current_line: String,
    pub next_line: String,
    pub has_synced_lyrics: bool,
}

/// Parses an `.lrc` string (e.g. `[00:12.34] Hello world`) into sorted `LyricLine` items.
/// If the input contains no valid `[mm:ss]` timestamps, non-empty plain lines are spaced by 4000ms.
pub fn parse_lrc(lrc_content: &str) -> Vec<LyricLine> {
    let mut parsed = Vec::new();
    let mut plain_lines = Vec::new();

    for raw_line in lrc_content.lines() {
        let trimmed = raw_line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if let Some((timestamps, lyric_text)) = extract_lrc_timestamps_and_text(trimmed) {
            let clean_text = lyric_text.trim();
            // Skip metadata tags like [ar:Artist], [ti:Title], [al:Album]
            if timestamps.is_empty() {
                if !trimmed.starts_with('[') {
                    plain_lines.push(trimmed.to_string());
                }
                continue;
            }
            for ts_ms in timestamps {
                if !clean_text.is_empty() {
                    parsed.push(LyricLine {
                        timestamp_ms: ts_ms,
                        text: clean_text.to_string(),
                    });
                }
            }
        } else if !trimmed.starts_with('[') {
            plain_lines.push(trimmed.to_string());
        }
    }

    if !parsed.is_empty() {
        parsed.sort_by_key(|l| l.timestamp_ms);
        return parsed;
    }

    // Fallback for plain unsynced lyrics
    plain_lines
        .into_iter()
        .enumerate()
        .map(|(idx, text)| LyricLine {
            timestamp_ms: (idx as u64) * 4_000,
            text,
        })
        .collect()
}

/// Synchronizes a list of `LyricLine`s against `elapsed_ms`, returning the active line index and surrounding lines.
pub fn sync_lyrics(lines: &[LyricLine], elapsed_ms: u64) -> LyricSyncSnapshot {
    if lines.is_empty() {
        return LyricSyncSnapshot {
            lines: Vec::new(),
            current_index: -1,
            previous_line: String::new(),
            current_line: String::new(),
            next_line: String::new(),
            has_synced_lyrics: false,
        };
    }

    let mut active_idx: Option<usize> = None;
    for (idx, line) in lines.iter().enumerate() {
        if line.timestamp_ms <= elapsed_ms {
            active_idx = Some(idx);
        } else {
            break;
        }
    }

    match active_idx {
        Some(idx) => {
            let previous_line = if idx > 0 {
                lines[idx - 1].text.clone()
            } else {
                String::new()
            };
            let current_line = lines[idx].text.clone();
            let next_line = if idx + 1 < lines.len() {
                lines[idx + 1].text.clone()
            } else {
                String::new()
            };
            LyricSyncSnapshot {
                lines: lines.to_vec(),
                current_index: idx as i32,
                previous_line,
                current_line,
                next_line,
                has_synced_lyrics: true,
            }
        }
        None => {
            // Before the first vocal timestamp: show musical intro indicator and upcoming first line
            let next_line = lines.first().map(|l| l.text.clone()).unwrap_or_default();
            LyricSyncSnapshot {
                lines: lines.to_vec(),
                current_index: 0,
                previous_line: String::new(),
                current_line: "♪ • • •".to_string(),
                next_line,
                has_synced_lyrics: true,
            }
        }
    }
}

fn extract_lrc_timestamps_and_text(mut line: &str) -> Option<(Vec<u64>, &str)> {
    if !line.starts_with('[') {
        return None;
    }
    let mut timestamps = Vec::new();
    while let Some(rest) = line.strip_prefix('[') {
        let close_idx = rest.find(']')?;
        let tag = &rest[..close_idx];
        if let Some(ms) = parse_time_tag_ms(tag) {
            timestamps.push(ms);
            line = &rest[close_idx + 1..];
        } else {
            // Non-time tag like [ar:Muse]
            return Some((Vec::new(), ""));
        }
    }
    Some((timestamps, line))
}

fn parse_time_tag_ms(tag: &str) -> Option<u64> {
    let (mins_str, secs_part) = tag.split_once(':')?;
    let mins: u64 = mins_str.trim().parse().ok()?;

    let (secs, millis) = if let Some((s_str, frac_str)) = secs_part.split_once(['.', ':']) {
        let s: u64 = s_str.trim().parse().ok()?;
        let frac_trimmed = frac_str.trim();
        let raw_frac: u64 = frac_trimmed.parse().ok()?;
        let ms = match frac_trimmed.len() {
            1 => raw_frac * 100,
            2 => raw_frac * 10,
            3 => raw_frac,
            _ => return None,
        };
        (s, ms)
    } else {
        let s: u64 = secs_part.trim().parse().ok()?;
        (s, 0)
    };

    Some(mins * 60_000 + secs * 1_000 + millis)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_lrc_and_syncs_current_line() {
        let sample = "\
[ti:Starlight]
[ar:Muse]
[00:05.20] Far away
[00:09.50] This ship is taking me far away
[00:14.00] Far away from the memories
";
        let lines = parse_lrc(sample);
        assert_eq!(lines.len(), 3);
        assert_eq!(lines[0].timestamp_ms, 5_200);
        assert_eq!(lines[0].text, "Far away");
        assert_eq!(lines[1].timestamp_ms, 9_500);
        assert_eq!(lines[2].timestamp_ms, 14_000);

        let before = sync_lyrics(&lines, 2_000);
        assert_eq!(before.current_line, "♪ • • •");
        assert_eq!(before.next_line, "Far away");

        let mid = sync_lyrics(&lines, 10_200);
        assert_eq!(mid.current_index, 1);
        assert_eq!(mid.previous_line, "Far away");
        assert_eq!(mid.current_line, "This ship is taking me far away");
        assert_eq!(mid.next_line, "Far away from the memories");
    }
}
