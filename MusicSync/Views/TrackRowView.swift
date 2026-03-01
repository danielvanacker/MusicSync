import SwiftUI

struct TrackRowView: View {
    let track: Track

    var body: some View {
        HStack(spacing: 12) {
            if let url = track.artworkURL {
                ArtworkImage(url: url, size: 50)
            } else {
                artworkPlaceholder
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                    .lineLimit(1)

                Text(track.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            sourceBadges
        }
        .padding(.vertical, 4)
    }

    private var sourceBadges: some View {
        HStack(spacing: 4) {
            ForEach(track.sourceTracks, id: \.id) { sourceTrack in
                sourceIcon(for: sourceTrack.source)
            }
        }
    }

    @ViewBuilder
    private func sourceIcon(for source: Source) -> some View {
        switch source {
        case .appleMusic:
            Image(systemName: "apple.logo")
                .font(.caption2)
                .foregroundStyle(.pink)
        case .spotify:
            Image(systemName: "waveform")
                .font(.caption2)
                .foregroundStyle(.green)
        }
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.gray.opacity(0.3))
            .frame(width: 50, height: 50)
            .overlay {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
    }
}
