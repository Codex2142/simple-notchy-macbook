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

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(mediaAdapter.nowPlaying?.title ?? "Spotify Ready")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)

                        if let source = mediaAdapter.nowPlaying?.sourceApp, !source.isEmpty {
                            Text(source.uppercased())
                                .font(.system(size: 8.5, weight: .bold))
                                .padding(.horizontal, 6)
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
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    Button {
                        mediaAdapter.previousTrack()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Previous Track")

                    Button {
                        mediaAdapter.togglePlayPause()
                    } label: {
                        Image(systemName: mediaAdapter.nowPlaying?.isPlaying == true ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(mediaAdapter.nowPlaying?.sourceApp == "Spotify" ? .green : .white)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Play / Pause Spotify")

                    Button {
                        mediaAdapter.nextTrack()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Next Track")

                    Button {
                        mediaAdapter.showLyrics.toggle()
                    } label: {
                        Image(systemName: mediaAdapter.showLyrics ? "quote.bubble.fill" : "quote.bubble")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(mediaAdapter.showLyrics ? .green : .white.opacity(0.6))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
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
        let ratio = CGFloat(max(0.0, min(1.0, mediaAdapter.playbackProgress)))

        return HStack(spacing: 8) {
            Text(Self.formatMmSs(mediaAdapter.liveElapsedSecs))
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.65))
                .frame(width: 34, alignment: .leading)

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
            .frame(height: 12)

            Text(Self.formatMmSs(track.durationSecs))
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.65))
                .frame(width: 34, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var liveLyricsSection: some View {
        ZStack {
            if let snap = mediaAdapter.lyricsSnapshot, snap.hasSyncedLyrics {
                VStack(alignment: .center, spacing: 4) {
                    if !snap.previousLine.isEmpty {
                        Text(snap.previousLine)
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundColor(.white.opacity(0.42))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    Text(snap.currentLine.isEmpty ? "♪ • • •" : snap.currentLine)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.green)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                    if !snap.nextLine.isEmpty {
                        Text(snap.nextLine)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.58))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                }
                .id(snap.currentIndex)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    )
                )
            } else if mediaAdapter.isLoadingLyrics {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                    Text("Syncing live lyrics from LRCLIB...")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                }
            } else if let track = mediaAdapter.nowPlaying {
                Text("♪ \(track.title) — \(track.artist)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            } else {
                Text("Start playing a track on Spotify to see live synced lyrics here.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.84), value: mediaAdapter.lyricsSnapshot?.currentIndex ?? -1)
        .frame(maxWidth: .infinity, minHeight: 58)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.38))
        )
        .clipped()
    }

    private static func formatMmSs(_ totalSecs: UInt32) -> String {
        let mins = totalSecs / 60
        let secs = totalSecs % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
