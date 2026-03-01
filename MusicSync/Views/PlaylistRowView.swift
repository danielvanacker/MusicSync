import SwiftUI

struct PlaylistRowView: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: 12) {
            if let url = playlist.artworkURL {
                ArtworkImage(url: url, size: 50)
            } else {
                artworkPlaceholder
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("\(playlist.trackCount) songs")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let owner = playlist.ownerName, !owner.isEmpty {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(owner)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            sourceIcon(for: playlist.source)
        }
        .padding(.vertical, 4)
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
                Image(systemName: "music.note.list")
                    .foregroundStyle(.secondary)
            }
    }
}
