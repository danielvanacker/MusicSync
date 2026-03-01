import SwiftUI

struct AlbumRowView: View {
    let album: Album

    var body: some View {
        HStack(spacing: 12) {
            if let url = album.artworkURL {
                ArtworkImage(url: url, size: 50)
            } else {
                artworkPlaceholder
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(album.name)
                    .font(.body)
                    .lineLimit(1)

                Text(album.artistName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let date = album.releaseDate {
                    Text(formatYear(date))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            sourceIcon(for: album.source)
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

    private func formatYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter.string(from: date)
    }

    private var artworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.gray.opacity(0.3))
            .frame(width: 50, height: 50)
            .overlay {
                Image(systemName: "square.stack")
                    .foregroundStyle(.secondary)
            }
    }
}
