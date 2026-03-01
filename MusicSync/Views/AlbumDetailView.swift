import SwiftData
import SwiftUI

struct AlbumDetailView: View {
    let album: Album
    @Query(sort: \Track.title, order: .forward) private var allTracks: [Track]

    private var matchingTracks: [Track] {
        allTracks.filter {
            $0.albumName == album.name && $0.artistName == album.artistName
        }
        .sorted { t1, t2 in
            let d1 = t1.discNumber ?? 1
            let d2 = t2.discNumber ?? 1
            if d1 != d2 { return d1 < d2 }
            return (t1.trackNumber ?? 0) < (t2.trackNumber ?? 0)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                sourceBadge
                if !album.genreNames.isEmpty {
                    metadataSection(title: "Genres", value: album.genreNames.joined(separator: ", "))
                }
                if !matchingTracks.isEmpty {
                    tracksSection
                }
            }
            .padding()
        }
        .navigationTitle(album.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        VStack(spacing: 16) {
            if let url = album.artworkURL {
                ArtworkImage(url: url, size: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 200, height: 200)
                    .overlay {
                        Image(systemName: "square.stack")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(spacing: 4) {
                Text(album.name)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(album.artistName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let date = album.releaseDate {
                    Text(formatDate(date))
                        .font(.body)
                        .foregroundStyle(.tertiary)
                }

                Text("\(album.trackCount) tracks")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var sourceBadge: some View {
        HStack(spacing: 4) {
            switch album.source {
            case .appleMusic:
                Image(systemName: "apple.logo")
                    .foregroundStyle(.pink)
                Text("Apple Music")
            case .spotify:
                Image(systemName: "waveform")
                    .foregroundStyle(.green)
                Text("Spotify")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .clipShape(Capsule())
    }

    private func metadataSection(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
    }

    private var tracksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tracks")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(matchingTracks) { track in
                    NavigationLink(value: track) {
                        TrackRowView(track: track)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationDestination(for: Track.self) { track in
            TrackDetailView(track: track)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
