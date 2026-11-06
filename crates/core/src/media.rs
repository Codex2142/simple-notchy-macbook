//! Media Now Playing state normalization and track-change detection (PRD FR-002).

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct NowPlayingTrack {
    pub source_app: String,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub duration_secs: u32,
    pub elapsed_secs: u32,
    pub is_playing: bool,
}

impl NowPlayingTrack {
    /// Returns true if the track title, artist, or source changed compared to `previous` and the new track is non-empty.
    pub fn is_new_track_compared_to(&self, previous: Option<&Self>) -> bool {
        if self.title.trim().is_empty() {
            return false;
        }
        match previous {
            None => true,
            Some(prev) => {
                prev.title != self.title
                    || prev.artist != self.artist
                    || prev.source_app != self.source_app
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_track_change() {
        let t1 = NowPlayingTrack {
            source_app: "Music".to_string(),
            title: "Midnight City".to_string(),
            artist: "M83".to_string(),
            album: "Hurry Up, We're Dreaming".to_string(),
            duration_secs: 243,
            elapsed_secs: 10,
            is_playing: true,
        };
        assert!(t1.is_new_track_compared_to(None));
        assert!(!t1.is_new_track_compared_to(Some(&t1)));

        let mut same_song_paused = t1.clone();
        same_song_paused.is_playing = false;
        same_song_paused.elapsed_secs = 42;
        assert!(!same_song_paused.is_new_track_compared_to(Some(&t1)));

        let t2 = NowPlayingTrack {
            title: "Outro".to_string(),
            ..t1.clone()
        };
        assert!(t2.is_new_track_compared_to(Some(&t1)));
    }
}
