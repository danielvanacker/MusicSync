import Combine
import Foundation
import MusicKit
import SwiftData

private enum SyncError: LocalizedError {
    case timeout
    var errorDescription: String? {
        switch self {
        case .timeout:
            return "Loading is taking longer than expected. Check your connection and try again."
        }
    }
}

@MainActor
class AppleMusicService: ObservableObject {
    @Published var authorizationStatus: MusicAuthorization.Status = .notDetermined
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var syncedCount = 0
    @Published var totalCount: Int?

    private var modelContext: ModelContext?
    private var modelContainer: ModelContainer?

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }

    func requestAuthorization() async {
        DebugLog.log("Apple Music: requesting authorization...")
        let status = await MusicAuthorization.request()
        authorizationStatus = status
        DebugLog.log("Apple Music: authorization status = \(String(describing: status))")
        if status == .authorized {
            await syncLibrary()
        }
    }

    func checkAuthorizationStatus() {
        authorizationStatus = MusicAuthorization.currentStatus
        DebugLog.log("Apple Music: checked status = \(String(describing: authorizationStatus))")
    }

    private let syncTimeout: Duration = .seconds(60)

    func syncLibrary() async {
        DebugLog.log("Apple Music: sync starting...")
        guard let container = modelContainer else {
            errorMessage = "Storage not available"
            DebugLog.error("Apple Music: no model container")
            return
        }

        isLoading = true
        errorMessage = nil
        syncedCount = 0
        totalCount = nil

        let result: Result<(Int, Int), Error> = await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            do {
                var existingBySourceId = AppleMusicService.fetchExistingSourceTracks(context: context)
                var tracksByMetadata = AppleMusicService.fetchExistingTracksByMetadata(context: context)

                let request = MusicLibraryRequest<Song>()
                let response = try await withThrowingTaskGroup(of: MusicLibraryResponse<Song>.self) { group in
                    group.addTask { try await request.response() }
                    group.addTask {
                        try await Task.sleep(for: .seconds(60))
                        throw SyncError.timeout
                    }
                    let result = try await group.next()!
                    group.cancelAll()
                    return result
                }
                var collection = response.items
                let firstBatch = Array(collection)

                var syncedSoFar = 0
                try await AppleMusicService.upsertBatch(firstBatch, context: context, existingBySourceId: &existingBySourceId, tracksByMetadata: &tracksByMetadata, syncedSoFar: syncedSoFar)
                syncedSoFar = firstBatch.count

                while collection.hasNextBatch {
                    guard let nextBatch = try await collection.nextBatch() else { break }
                    let nextItems = Array(nextBatch)
                    try await AppleMusicService.upsertBatch(nextItems, context: context, existingBySourceId: &existingBySourceId, tracksByMetadata: &tracksByMetadata, syncedSoFar: syncedSoFar)
                    syncedSoFar += nextItems.count
                    collection = nextBatch
                }

                try context.save()
                return .success((syncedSoFar, syncedSoFar))
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success((let count, let total)):
            syncedCount = count
            totalCount = total
            errorMessage = nil
        case .failure(let error):
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            DebugLog.error("Apple Music: sync failed - \(error.localizedDescription)")
        }
        isLoading = false
    }

    nonisolated private static func fetchExistingSourceTracks(context: ModelContext) -> [String: SourceTrack] {
        let appleMusicRaw = Source.appleMusic.rawValue
        let predicate = #Predicate<SourceTrack> { $0.sourceRawValue == appleMusicRaw }
        let descriptor = FetchDescriptor<SourceTrack>(predicate: predicate)
        let existing = (try? context.fetch(descriptor)) ?? []
        return Dictionary(uniqueKeysWithValues: existing.map { ($0.sourceId, $0) })
    }

    private static let progressUpdateInterval = 100

    nonisolated private static func upsertBatch(_ songs: [Song], context: ModelContext, existingBySourceId: inout [String: SourceTrack], tracksByMetadata: inout [String: Track], syncedSoFar: Int) async throws {
        let now = Date.now

        for (index, song) in songs.enumerated() {
            let songId = song.id.rawValue
            let existingSourceTrack = existingBySourceId[songId]

            if let sourceTrack = existingSourceTrack {
                Self.updateSourceTrack(sourceTrack, from: song, now: now)
                if let track = sourceTrack.track {
                    Self.updateTrack(track, from: song, now: now)
                }
            } else {
                let title = song.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let artist = song.artistName.trimmingCharacters(in: .whitespacesAndNewlines)
                let album = (song.albumTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let safeTitle = title.isEmpty ? "Unknown Track" : title
                let safeArtist = artist.isEmpty ? "Unknown Artist" : artist
                let safeAlbum = album.isEmpty ? "Unknown Album" : album
                let metaKey = trackMetadataKey(title: safeTitle, artistName: safeArtist, albumName: safeAlbum)

                let track: Track
                if let existingTrack = tracksByMetadata[metaKey] {
                    track = existingTrack
                    Self.updateTrack(track, from: song, now: now)
                } else {
                    track = Self.makeTrack(from: song, now: now)
                    context.insert(track)
                    tracksByMetadata[metaKey] = track
                }

                let sourceTrack = Self.makeSourceTrack(from: song, now: now)
                sourceTrack.track = track
                context.insert(sourceTrack)
                existingBySourceId[songId] = sourceTrack
            }

            if (index + 1) % progressUpdateInterval == 0 {
                await Task.yield()
            }
        }
    }

    // MARK: - Mapping helpers

    nonisolated private static func makeTrack(from song: Song, now: Date) -> Track {
        let title = song.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artistName = song.artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        let albumName = (song.albumTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        return Track(
            title: title.isEmpty ? "Unknown Track" : title,
            artistName: artistName.isEmpty ? "Unknown Artist" : artistName,
            albumName: albumName.isEmpty ? "Unknown Album" : albumName,
            artworkURL: song.artwork?.url(width: 150, height: 150),
            durationMs: max(0, Int((song.duration ?? 0) * 1000)),
            genreNames: song.genreNames ?? [],
            releaseDate: song.releaseDate,
            isExplicit: song.contentRating == .explicit,
            isrc: song.isrc,
            discNumber: song.discNumber,
            trackNumber: song.trackNumber,
            composerName: song.composerName,
            addedAt: song.libraryAddedDate,
            lastSyncedAt: now
        )
    }

    nonisolated private static func makeSourceTrack(from song: Song, now: Date) -> SourceTrack {
        SourceTrack(
            source: .appleMusic,
            sourceId: song.id.rawValue,
            addedAt: song.libraryAddedDate,
            playCount: song.playCount,
            lastPlayedDate: song.lastPlayedDate,
            rating: nil,
            artworkURL: song.artwork?.url(width: 150, height: 150),
            lastSyncedAt: now
        )
    }

    nonisolated private static func updateTrack(_ track: Track, from song: Song, now: Date) {
        let title = song.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artistName = song.artistName.trimmingCharacters(in: .whitespacesAndNewlines)
        let albumName = (song.albumTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        track.title = title.isEmpty ? "Unknown Track" : title
        track.artistName = artistName.isEmpty ? "Unknown Artist" : artistName
        track.albumName = albumName.isEmpty ? "Unknown Album" : albumName
        track.artworkURL = song.artwork?.url(width: 150, height: 150)
        track.durationMs = max(0, Int((song.duration ?? 0) * 1000))
        track.genreNames = song.genreNames ?? []
        track.releaseDate = song.releaseDate
        track.isExplicit = song.contentRating == .explicit
        track.isrc = song.isrc
        track.discNumber = song.discNumber
        track.trackNumber = song.trackNumber
        track.composerName = song.composerName
        track.addedAt = song.libraryAddedDate
        track.lastSyncedAt = now
    }

    nonisolated private static func updateSourceTrack(_ sourceTrack: SourceTrack, from song: Song, now: Date) {
        sourceTrack.addedAt = song.libraryAddedDate
        sourceTrack.playCount = song.playCount
        sourceTrack.lastPlayedDate = song.lastPlayedDate
        sourceTrack.rating = nil
        sourceTrack.artworkURL = song.artwork?.url(width: 150, height: 150)
        sourceTrack.lastSyncedAt = now
    }

    // MARK: - Playlist Sync

    func syncPlaylists() async {
        DebugLog.log("Apple Music: playlist sync starting...")
        guard let container = modelContainer else {
            DebugLog.error("Apple Music: no model container for playlists")
            return
        }
        guard authorizationStatus == .authorized else { return }

        let result: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            do {
                var existingSourceTracks = AppleMusicService.fetchExistingSourceTracks(context: context)
                var existingPlaylists = AppleMusicService.fetchExistingPlaylists(context: context)
                var tracksByMetadata = AppleMusicService.fetchExistingTracksByMetadata(context: context)

                let request = MusicLibraryRequest<MusicKit.Playlist>()
                let response = try await request.response()
                var collection = response.items
                var currentBatch = Array(collection)

                while true {
                    for playlist in currentBatch {
                        try await Self.upsertPlaylist(playlist, context: context, existingSourceTracks: &existingSourceTracks, existingPlaylists: &existingPlaylists, tracksByMetadata: &tracksByMetadata)
                    }
                    guard collection.hasNextBatch, let nextBatch = try await collection.nextBatch() else { break }
                    currentBatch = Array(nextBatch)
                    collection = nextBatch
                    await Task.yield()
                }

                try context.save()
                DebugLog.log("Apple Music: playlist sync complete")
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value

        if case .failure(let error) = result {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            DebugLog.error("Apple Music: playlist sync failed - \(error.localizedDescription)")
        }
    }

    nonisolated private static func trackMetadataKey(title: String, artistName: String, albumName: String) -> String {
        "\(title.lowercased())|\(artistName.lowercased())|\(albumName.lowercased())"
    }

    nonisolated private static func fetchExistingTracksByMetadata(context: ModelContext) -> [String: Track] {
        let descriptor = FetchDescriptor<Track>()
        let tracks = (try? context.fetch(descriptor)) ?? []
        var dict: [String: Track] = Dictionary(minimumCapacity: tracks.count)
        for track in tracks {
            let key = trackMetadataKey(title: track.title, artistName: track.artistName, albumName: track.albumName)
            dict[key] = track
        }
        return dict
    }

    nonisolated private static func fetchExistingPlaylists(context: ModelContext) -> [String: Playlist] {
        let appleMusicRaw = Source.appleMusic.rawValue
        let predicate = #Predicate<Playlist> { $0.sourceRawValue == appleMusicRaw }
        let descriptor = FetchDescriptor<Playlist>(predicate: predicate)
        let existing = (try? context.fetch(descriptor)) ?? []
        return Dictionary(uniqueKeysWithValues: existing.map { ($0.sourceId, $0) })
    }

    nonisolated private static func upsertPlaylist(_ mkPlaylist: MusicKit.Playlist, context: ModelContext, existingSourceTracks: inout [String: SourceTrack], existingPlaylists: inout [String: Playlist], tracksByMetadata: inout [String: Track]) async throws {
        let playlistId = mkPlaylist.id.rawValue
        let now = Date.now

        let playlist: Playlist
        if let existing = existingPlaylists[playlistId] {
            playlist = existing
            playlist.name = mkPlaylist.name
            playlist.descriptionText = mkPlaylist.description
            playlist.artworkURL = mkPlaylist.artwork?.url(width: 150, height: 150)
            playlist.ownerName = mkPlaylist.curatorName
            playlist.lastSyncedAt = now
        } else {
            playlist = Playlist(
                source: .appleMusic,
                sourceId: playlistId,
                name: mkPlaylist.name,
                descriptionText: mkPlaylist.description,
                artworkURL: mkPlaylist.artwork?.url(width: 150, height: 150),
                trackCount: 0,
                ownerName: mkPlaylist.curatorName,
                isPublic: nil,
                lastSyncedAt: now
            )
            context.insert(playlist)
            existingPlaylists[playlistId] = playlist
        }

        for existingPT in Array(playlist.playlistTracks) {
            context.delete(existingPT)
        }

        guard let tracksCollection = try await mkPlaylist.with([.tracks]).tracks else {
            playlist.trackCount = 0
            return
        }

        var tracksArray: [MusicKit.Track] = []
        for item in tracksCollection {
            tracksArray.append(item)
        }

        playlist.trackCount = tracksArray.count

        for (index, mkTrack) in tracksArray.enumerated() {
            let position = index
            guard case .song(let song) = mkTrack else { continue }

            let songId = song.id.rawValue
            let addedAt = song.libraryAddedDate

            let track: Track
            if let sourceTrack = existingSourceTracks[songId] {
                if let t = sourceTrack.track {
                    track = t
                } else { continue }
            } else {
                let title = song.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let artist = song.artistName.trimmingCharacters(in: .whitespacesAndNewlines)
                let album = (song.albumTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let safeTitle = title.isEmpty ? "Unknown Track" : title
                let safeArtist = artist.isEmpty ? "Unknown Artist" : artist
                let safeAlbum = album.isEmpty ? "Unknown Album" : album
                let metaKey = trackMetadataKey(title: safeTitle, artistName: safeArtist, albumName: safeAlbum)

                if let existingTrack = tracksByMetadata[metaKey] {
                    track = existingTrack
                    updateTrack(existingTrack, from: song, now: now)
                } else {
                    track = makeTrack(from: song, now: now)
                    context.insert(track)
                    tracksByMetadata[metaKey] = track
                }
                let sourceTrack = makeSourceTrack(from: song, now: now)
                sourceTrack.track = track
                context.insert(sourceTrack)
                existingSourceTracks[songId] = sourceTrack
            }

            let playlistTrack = PlaylistTrack(position: position, addedAt: addedAt, playlist: playlist, track: track)
            context.insert(playlistTrack)
        }
    }

    // MARK: - Album Sync

    func syncAlbums() async {
        DebugLog.log("Apple Music: album sync starting...")
        guard let container = modelContainer else {
            DebugLog.error("Apple Music: no model container for albums")
            return
        }
        guard authorizationStatus == .authorized else { return }

        let result: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            do {
                var existingAlbums = AppleMusicService.fetchExistingAlbums(context: context)

                let request = MusicLibraryRequest<MusicKit.Album>()
                let response = try await request.response()
                var collection = response.items
                var currentBatch = Array(collection)

                while true {
                    for mkAlbum in currentBatch {
                        Self.upsertAlbum(mkAlbum, context: context, existingAlbums: &existingAlbums)
                    }
                    guard collection.hasNextBatch, let nextBatch = try await collection.nextBatch() else { break }
                    currentBatch = Array(nextBatch)
                    collection = nextBatch
                    await Task.yield()
                }

                try context.save()
                DebugLog.log("Apple Music: album sync complete")
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value

        if case .failure(let error) = result {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            DebugLog.error("Apple Music: album sync failed - \(error.localizedDescription)")
        }
    }

    nonisolated private static func fetchExistingAlbums(context: ModelContext) -> [String: Album] {
        let appleMusicRaw = Source.appleMusic.rawValue
        let predicate = #Predicate<Album> { $0.sourceRawValue == appleMusicRaw }
        let descriptor = FetchDescriptor<Album>(predicate: predicate)
        let existing = (try? context.fetch(descriptor)) ?? []
        return Dictionary(uniqueKeysWithValues: existing.map { ($0.sourceId, $0) })
    }

    nonisolated private static func upsertAlbum(_ mkAlbum: MusicKit.Album, context: ModelContext, existingAlbums: inout [String: Album]) {
        let albumId = mkAlbum.id.rawValue
        let now = Date.now

        if let existing = existingAlbums[albumId] {
            existing.name = mkAlbum.title
            existing.artistName = mkAlbum.artistName
            existing.artworkURL = mkAlbum.artwork?.url(width: 150, height: 150)
            existing.releaseDate = mkAlbum.releaseDate
            existing.trackCount = mkAlbum.trackCount
            existing.genreNames = mkAlbum.genreNames
            existing.lastSyncedAt = now
        } else {
            let album = Album(
                source: .appleMusic,
                sourceId: albumId,
                name: mkAlbum.title,
                artistName: mkAlbum.artistName,
                artworkURL: mkAlbum.artwork?.url(width: 150, height: 150),
                releaseDate: mkAlbum.releaseDate,
                trackCount: mkAlbum.trackCount,
                genreNames: mkAlbum.genreNames,
                lastSyncedAt: now
            )
            context.insert(album)
            existingAlbums[albumId] = album
        }
    }
}
