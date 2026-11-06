import SwiftUI
import IslandBridge
import IslandIntegrations

public struct MediaPlayerView: View {
    @ObservedObject public var mediaAdapter: MediaAdapter

    public init(mediaAdapter: MediaAdapter) {
        self.mediaAdapter = mediaAdapter
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                artworkView

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(mediaAdapter.nowPlaying?.title ?? "Spotify Ready")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        if let source = mediaAdapter.nowPlaying?.sourceApp, !source.isEmpty {
                            Text(source.uppercased())
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(
                                        source == "Spotify"
                                            ? Color.green.opacity(0.25)
                                            : Color.pink.opacity(0.25)
                                    )
                                )
                                .foregroundColor(source == "Spotify" ? .green : .pink)
                        }
                    }

                    Text(mediaAdapter.nowPlaying?.artist ?? "Play any song in Spotify to control & view live lyrics")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.72))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                HStack(spacing: 12) {
                    Button {
                        mediaAdapter.previousTrack()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help("Previous Track")

                    Button {
                        mediaAdapter.togglePlayPause()
                    } label: {
                        Image(systemName: mediaAdapter.nowPlaying?.isPlaying == true ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(mediaAdapter.nowPlaying?.sourceApp == "Spotify" ? .green : .white)
                    }
                    .buttonStyle(.plain)
                    .help("Play / Pause Spotify")

                    Button {
                        mediaAdapter.nextTrack()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help("Next Track")

                    Button {
                        mediaAdapter.showLyrics.toggle()
                    } label: {
                        Image(systemName: mediaAdapter.showLyrics ? "quote.bubble.fill" : "quote.bubble")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(mediaAdapter.showLyrics ? .green : .white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Toggle Live Synced Lyrics")
                }
            }

            if let track = mediaAdapter.nowPlaying, track.durationSecs > 0 {
                progressBar(for: track)
            }

            if mediaAdapter.showLyrics {
                liveLyricsSection
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    @ViewBuilder
    private var artworkView: some View {
        if let urlStr = mediaAdapter.nowPlaying?.artworkUrl,
           !urlStr.isEmpty,
           let url = URL(string: urlStr)
        {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                default:
                    fallbackArtwork
                }
            }
        } else {
            fallbackArtwork
        }
    }

    private var fallbackArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.1))
                .frame(width: 46, height: 46)
            Image(systemName: mediaAdapter.nowPlaying?.isPlaying == true ? "waveform" : "music.note")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.green)
        }
    }

    private func progressBar(for track: FfiNowPlayingTrack) -> some View {
        let totalSecs = Double(max(1, track.durationSecs))
        let currentSecs = min(totalSecs, Double(track.elapsedMs) / 1000.0)
        let ratio = CGFloat(max(0.0, min(1.0, currentSecs / totalSecs)))

        return HStack(spacing: 8) {
            Text(Self.formatMmSs(UInt32(currentSecs.rounded(.down))))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 32, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                        .frame(height: 5)
                    Capsule()
                        .fill(Color.green)
                        .frame(width: max(4, geo.size.width * ratio), height: 5)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            let clickRatio = max(0.0, min(1.0, value.location.x / max(1.0, geo.size.width)))
                            mediaAdapter.seek(toSeconds: Double(clickRatio) * totalSecs)
                        }
                )
            }
            .frame(height: 10)

            Text(Self.formatMmSs(track.durationSecs))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 32, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var liveLyricsSection: some View {
        VStack(alignment: .center, spacing: 3) {
            if let snap = mediaAdapter.lyricsSnapshot, snap.hasSyncedLyrics {
                if !snap.previousLine.isEmpty {
                    Text(snap.previousLine)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.white.opacity(0.40))
                        .lineLimit(1)
                }
                Text(snap.currentLine.isEmpty ? "♪ • • •" : snap.currentLine)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.green)
                    .lineLimit(1)
                    .id(snap.currentIndex)
                if !snap.nextLine.isEmpty {
                    Text(snap.nextLine)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.55))
                        .lineLimit(1)
                }
            } else if mediaAdapter.isLoadingLyrics {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                    Text("Syncing live lyrics from LRCLIB...")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                }
            } else if let track = mediaAdapter.nowPlaying {
                Text("♪ \(track.title) — \(track.artist)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            } else {
                Text("Start playing a track on Spotify to see live synced lyrics here.")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.35))
        )
    }

    private static func formatMmSs(_ totalSecs: UInt32) -> String {
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
