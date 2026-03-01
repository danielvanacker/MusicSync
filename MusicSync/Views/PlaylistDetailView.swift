import SwiftData
import SwiftUI

struct PlaylistDetailView: View {
    let playlist: Playlist

    private var sortedTracks: [PlaylistTrack] {
        playlist.playlistTracks.sorted { $0.position < $1.position }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                sourceBadge
                if !sortedTracks.isEmpty {
                    tracksSection
                }
            }
            .padding()
        }
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        VStack(spacing: 16) {
            if let url = playlist.artworkURL {
                ArtworkImage(url: url, size: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 200, height: 200)
                    .overlay {
                        Image(systemName: "music.note.list")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
            }

            VStack(spacing: 4) {
                Text(playlist.name)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                if let owner = playlist.ownerName, !owner.isEmpty {
                    Text(owner)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Text("\(playlist.trackCount) songs")
                    .font(.body)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var sourceBadge: some View {
        HStack(spacing: 4) {
            switch playlist.source {
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

    private var tracksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tracks")
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(sortedTracks, id: \.id) { playlistTrack in
                    if let track = playlistTrack.track {
                        NavigationLink(value: track) {
                            TrackRowView(track: track)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationDestination(for: Track.self) { track in
            TrackDetailView(track: track)
        }
    }
}
