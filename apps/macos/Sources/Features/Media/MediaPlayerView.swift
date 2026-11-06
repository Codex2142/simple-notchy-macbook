import SwiftUI
import IslandBridge
import IslandIntegrations

public struct MediaPlayerView: View {
    @ObservedObject public var mediaAdapter: MediaAdapter

    public init(mediaAdapter: MediaAdapter) {
        self.mediaAdapter = mediaAdapter
    }

    public var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: mediaAdapter.nowPlaying?.isPlaying == true ? "waveform" : "music.note")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.pink)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(mediaAdapter.nowPlaying?.title ?? "Nothing Playing")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(mediaAdapter.nowPlaying?.artist ?? "Play music in Apple Music or Spotify")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 12) {
                Button {
                    mediaAdapter.previousTrack()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)

                Button {
                    mediaAdapter.togglePlayPause()
                } label: {
                    Image(systemName: mediaAdapter.nowPlaying?.isPlaying == true ? "pause.fill" : "play.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Button {
                    mediaAdapter.nextTrack()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}
