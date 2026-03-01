import AVFoundation
import SwiftUI
import SwiftData

struct TrackDetailView: View {
    let track: Track

    private var appleMusicSourceTrack: SourceTrack? {
        track.sourceTracks.first { $0.source == .appleMusic }
    }

    private var spotifySourceTrack: SourceTrack? {
        track.sourceTracks.first { $0.source == .spotify }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                sourceBadges
                trackInfoSection
                if let st = appleMusicSourceTrack {
                    appleMusicSection(sourceTrack: st)
                }
                if let st = spotifySourceTrack {
                    spotifySection(sourceTrack: st)
                }
                syncInfoSection
            }
            .padding()
        }
        .navigationTitle(track.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerSection: some View {
        VStack(spacing: 16) {
            if let url = track.artworkURL {
                ArtworkImage(url: url, size: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                artworkPlaceholder(size: 200)
            }

            VStack(spacing: 4) {
                Text(track.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(track.artistName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if !track.albumName.isEmpty {
                    Text(track.albumName)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var sourceBadges: some View {
        HStack(spacing: 8) {
            ForEach(track.sourceTracks, id: \.id) { sourceTrack in
                sourceBadge(for: sourceTrack.source)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func sourceBadge(for source: Source) -> some View {
        HStack(spacing: 4) {
            switch source {
            case .appleMusic:
                Image(systemName: "apple.logo")
                    .foregroundStyle(.pink)
            case .spotify:
                Image(systemName: "waveform")
                    .foregroundStyle(.green)
            }
            Text(source == .appleMusic ? "Apple Music" : "Spotify")
                .font(.subheadline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var trackInfoSection: some View {
        let rows = trackInfoRows
        if !rows.isEmpty {
            metadataSection(title: "Track Info", rows: rows)
        }
    }

    private var trackInfoRows: [(String, String)] {
        var rows: [(String, String)] = []

        if track.durationMs > 0 {
            rows.append(("Duration", formatDuration(track.durationMs)))
        }
        if let disc = track.discNumber, disc > 0 {
            rows.append(("Disc", "\(disc)"))
        }
        if let num = track.trackNumber, num > 0 {
            rows.append(("Track", "\(num)"))
        }
        if !track.genreNames.isEmpty {
            rows.append(("Genre", track.genreNames.joined(separator: ", ")))
        }
        if let date = track.releaseDate {
            rows.append(("Release Date", formatDate(date)))
        }
        if track.isExplicit {
            rows.append(("Explicit", "Yes"))
        }
        if let isrc = track.isrc, !isrc.isEmpty {
            rows.append(("ISRC", isrc))
        }
        if let composer = track.composerName, !composer.isEmpty {
            rows.append(("Composer", composer))
        }

        return rows
    }

    private func appleMusicRows(sourceTrack: SourceTrack) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let count = sourceTrack.playCount {
            rows.append(("Play Count", "\(count)"))
        }
        if let date = sourceTrack.lastPlayedDate {
            rows.append(("Last Played", formatDate(date)))
        }
        if let rating = sourceTrack.rating {
            rows.append(("Rating", "\(rating)/5"))
        }
        if let date = sourceTrack.addedAt {
            rows.append(("Added", formatDate(date)))
        }
        return rows
    }

    @ViewBuilder
    private func appleMusicSection(sourceTrack: SourceTrack) -> some View {
        let rows = appleMusicRows(sourceTrack: sourceTrack)
        if !rows.isEmpty {
            metadataSection(title: "Apple Music", rows: rows)
        }
    }

    private func spotifyRows(sourceTrack: SourceTrack) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let pop = sourceTrack.popularity {
            rows.append(("Popularity", "\(pop)/100"))
        }
        if let date = sourceTrack.addedAt {
            rows.append(("Added", formatDate(date)))
        }
        return rows
    }

    @ViewBuilder
    private func spotifySection(sourceTrack: SourceTrack) -> some View {
        let rows = spotifyRows(sourceTrack: sourceTrack)
        let previewURL = sourceTrack.previewURL
        if !rows.isEmpty || previewURL != nil {
            VStack(alignment: .leading, spacing: 12) {
                if !rows.isEmpty {
                    metadataSection(title: "Spotify", rows: rows)
                }
                if let url = previewURL {
                    SpotifyPreviewPlayer(url: url)
                }
            }
        }
    }

    @ViewBuilder
    private var syncInfoSection: some View {
        metadataSection(title: "Sync Info", rows: [
            ("Last Synced", relativeTime(from: track.lastSyncedAt))
        ])
    }

    private func metadataSection(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(rows, id: \.0) { label, value in
                    HStack {
                        Text(label)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(value)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(.subheadline)
                }
            }
            .padding()
            .background(.bar.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func artworkPlaceholder(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.gray.opacity(0.3))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "music.note")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
    }

    private func formatDuration(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60)) min ago" }
        if interval < 86400 { return "\(Int(interval / 3600)) hr ago" }
        return "\(Int(interval / 86400)) days ago"
    }
}

// MARK: - Spotify Preview Player

@Observable
private final class SpotifyPreviewPlayerModel {
    var isPlaying = false
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    func togglePlayback(url: URL) {
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            if player == nil {
                let item = AVPlayerItem(url: url)
                player = AVPlayer(playerItem: item)

                endObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: item,
                    queue: .main
                ) { [weak self] _ in
                    self?.player?.pause()
                    self?.isPlaying = false
                }
            }
            player?.seek(to: .zero)
            player?.play()
            isPlaying = true
        }
    }

    func stop() {
        player?.pause()
        isPlaying = false
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
    }
}

private struct SpotifyPreviewPlayer: View {
    let url: URL

    @State private var model = SpotifyPreviewPlayerModel()

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.togglePlayback(url: url)
            } label: {
                Image(systemName: model.isPlaying ? "stop.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(.tint)
                    .foregroundStyle(.white)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("30-second preview")
                    .font(.subheadline)
                Text(model.isPlaying ? "Playing…" : "Tap to play")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(.bar.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onDisappear {
            model.stop()
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Track.self, SourceTrack.self, configurations: config)
    let track = Track(
        title: "Sample Song",
        artistName: "Sample Artist",
        albumName: "Sample Album",
        artworkURL: nil,
        durationMs: 234000,
        genreNames: ["Pop", "Electronic"],
        releaseDate: Date(),
        isExplicit: true,
        isrc: "USRC12345678",
        discNumber: 1,
        trackNumber: 5,
        composerName: "Composer Name",
        addedAt: Date(),
        lastSyncedAt: Date()
    )
    container.mainContext.insert(track)

    return NavigationStack {
        TrackDetailView(track: track)
    }
    .modelContainer(container)
}
