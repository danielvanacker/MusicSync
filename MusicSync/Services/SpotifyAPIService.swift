import Combine
import Foundation
import SwiftData

private let spotifyAPIBase = "https://api.spotify.com/v1"
private let pageLimit = 50

// MARK: - API Response Models

private struct SpotifySavedTracksResponse: Codable {
    let items: [SpotifySavedTrackItem]
    let next: String?
    let offset: Int
    let total: Int
}

private struct SpotifySavedTrackItem: Codable {
    let addedAt: String
    let track: SpotifyTrack?

    enum CodingKeys: String, CodingKey {
        case addedAt = "added_at"
        case track
    }
}

private struct SpotifyTrack: Codable {
    let id: String
    let name: String
    let artists: [SpotifyArtist]
    let album: SpotifyAlbum
    let durationMs: Int
    let explicit: Bool
    let externalIds: SpotifyExternalIds?
    let popularity: Int?
    let previewUrl: String?
    let discNumber: Int
    let trackNumber: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, artists, album, explicit, popularity
        case durationMs = "duration_ms"
        case externalIds = "external_ids"
        case previewUrl = "preview_url"
        case discNumber = "disc_number"
        case trackNumber = "track_number"
    }
}

private struct SpotifyArtist: Codable {
    let name: String
}

private struct SpotifyAlbum: Codable {
    let name: String
    let images: [SpotifyImage]
    let releaseDate: String?

    enum CodingKeys: String, CodingKey {
        case name, images
        case releaseDate = "release_date"
    }
}

private struct SpotifyImage: Codable {
    let url: URL
    let width: Int?
    let height: Int?
}

private struct SpotifyExternalIds: Codable {
    let isrc: String?
}

// MARK: - Playlist API DTOs

private struct SpotifyPlaylistsResponse: Decodable {
    let items: [SpotifyPlaylistItem]
    let next: String?
    let offset: Int
    let total: Int
}

private struct SpotifyPlaylistItem: Decodable {
    let id: String
    let name: String
    let description: String?
    let images: [SpotifyImage]
    let owner: SpotifyPlaylistOwner
    let tracks: SpotifyPlaylistTracksRef?
    let `public`: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, description, images, owner, tracks
        case `public` = "public"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        images = (try? c.decode([SpotifyImage].self, forKey: .images)) ?? []
        owner = try c.decode(SpotifyPlaylistOwner.self, forKey: .owner)
        tracks = try c.decodeIfPresent(SpotifyPlaylistTracksRef.self, forKey: .tracks)
        `public` = try c.decodeIfPresent(Bool.self, forKey: .public)
    }
}

private struct SpotifyPlaylistOwner: Codable {
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

private struct SpotifyPlaylistTracksRef: Codable {
    let total: Int
}

private struct SpotifyPlaylistTracksResponse: Decodable {
    let items: [SpotifyPlaylistTrackItem]
    let next: String?
    let offset: Int
    let total: Int
}

/// Playlist items can contain tracks OR podcast episodes. Episodes have a different structure
/// and cause decode failure. We try to decode as track; if it fails (episode, null, malformed), skip.
private struct SpotifyPlaylistTrackItem: Decodable {
    let addedAt: String?
    let track: SpotifyTrack?

    enum CodingKeys: String, CodingKey {
        case track
        case addedAt = "added_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        addedAt = try c.decodeIfPresent(String.self, forKey: .addedAt)
        track = try? c.decode(SpotifyTrack.self, forKey: .track)
    }
}

// MARK: - Saved Albums API DTOs

private struct SpotifySavedAlbumsResponse: Codable {
    let items: [SpotifySavedAlbumItem]
    let next: String?
    let offset: Int
    let total: Int
}

private struct SpotifySavedAlbumItem: Codable {
    let addedAt: String?
    let album: SpotifyAlbumFull

    enum CodingKeys: String, CodingKey {
        case album
        case addedAt = "added_at"
    }
}

private struct SpotifyAlbumFull: Codable {
    let id: String
    let name: String
    let artists: [SpotifyArtist]
    let images: [SpotifyImage]
    let releaseDate: String
    let totalTracks: Int
    let genres: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, artists, images, genres
        case releaseDate = "release_date"
        case totalTracks = "total_tracks"
    }
}

// MARK: - SpotifyAPIService

@MainActor
final class SpotifyAPIService: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var syncedCount = 0
    @Published var totalCount: Int?

    private let authService: SpotifyAuthService
    private var modelContext: ModelContext?
    private var modelContainer: ModelContainer?

    init(authService: SpotifyAuthService) {
        self.authService = authService
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }

    func syncLibrary() async {
        DebugLog.log("Spotify API: sync starting...")
        guard let container = modelContainer else {
            errorMessage = "Storage not available"
            DebugLog.error("Spotify API: no model container")
            return
        }
        guard authService.isConnected else {
            errorMessage = "Not connected to Spotify."
            DebugLog.error("Spotify API: not connected")
            return
        }

        let token: String
        do {
            token = try await authService.getAccessToken()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            DebugLog.error("Spotify API: not authenticated - \(error.localizedDescription)")
            return
        }

        isLoading = true
        errorMessage = nil
        syncedCount = 0
        totalCount = nil

        let result: Result<(Int, Int?), Error> = await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            do {
                var existingBySourceId = Self.fetchExistingSourceTracks(context: context)
                let existingCount = existingBySourceId.count
                DebugLog.log("Spotify API: fetched \(existingCount) existing SourceTracks")

                var nextURL: URL? = URL(string: "\(spotifyAPIBase)/me/tracks")!
                nextURL?.append(queryItems: [
                    URLQueryItem(name: "limit", value: "\(pageLimit)"),
                    URLQueryItem(name: "offset", value: "0"),
                ])
                var total: Int?
                var syncedSoFar = 0
                var newTracksFound = 0

                while let url = nextURL {
                    let page = try await Self.fetchPage(url: url, token: token)
                    total = page.total

                    if syncedSoFar == 0 && page.total == existingCount && existingCount > 0 {
                        DebugLog.log("Spotify API: total (\(page.total)) matches existing count, skipping full sync")
                        break
                    }

                    for item in page.items {
                        guard let track = item.track else { continue }
                        let spotifyId = track.id
                        let existingSourceTrack = existingBySourceId[spotifyId]
                        let addedAt = Self.parseISO8601(item.addedAt)

                        if let sourceTrack = existingSourceTrack {
                            Self.updateSourceTrack(sourceTrack, from: track, addedAt: addedAt)
                            if let linkedTrack = sourceTrack.track {
                                Self.updateTrackPreservingExistingMetadata(linkedTrack, from: track, spotifyAddedAt: addedAt)
                            }
                        } else {
                            newTracksFound += 1
                            let title = track.name
                            let artistName = track.artists.first?.name ?? "Unknown Artist"
                            let albumName = track.album.name
                            let existingTrack = Self.fetchExistingTrack(title: title, artistName: artistName, albumName: albumName, context: context)

                            if let existingTrack {
                                let sourceTrack = Self.makeSourceTrack(from: track, addedAt: addedAt)
                                sourceTrack.track = existingTrack
                                context.insert(sourceTrack)
                                existingBySourceId[spotifyId] = sourceTrack
                                Self.updateTrackPreservingExistingMetadata(existingTrack, from: track, spotifyAddedAt: addedAt)
                            } else {
                                let newTrack = Self.makeTrack(from: track, addedAt: addedAt)
                                context.insert(newTrack)
                                let sourceTrack = Self.makeSourceTrack(from: track, addedAt: addedAt)
                                sourceTrack.track = newTrack
                                context.insert(sourceTrack)
                                existingBySourceId[spotifyId] = sourceTrack
                            }
                        }

                        syncedSoFar += 1
                    }

                    if let nextStr = page.next, let url = URL(string: nextStr) {
                        nextURL = url
                        await Task.yield()
                    } else {
                        nextURL = nil
                    }
                }

                try context.save()
                DebugLog.log("Spotify API: sync complete, processed \(syncedSoFar) tracks (\(newTracksFound) new)")
                return .success((syncedSoFar, total))
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
            DebugLog.error("Spotify API: sync failed - \(error.localizedDescription)")
        }
        isLoading = false
    }

    // MARK: - Fetch

    nonisolated private static func fetchPage(url: URL, token: String) async throws -> (items: [SpotifySavedTrackItem], next: String?, total: Int) {
        var response: (data: Data, response: URLResponse)
        var retries = 0
        let maxRetries = 5

        repeat {
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            response = try await URLSession.shared.data(for: req)

            if let http = response.response as? HTTPURLResponse, http.statusCode == 429 {
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) } ?? 5
                DebugLog.log("Spotify API: rate limited (429), retrying after \(retryAfter)s")
                try await Task.sleep(nanoseconds: UInt64(retryAfter) * 1_000_000_000)
                retries += 1
                if retries >= maxRetries {
                    throw SpotifyAPIError.rateLimited("Too many rate limit retries")
                }
                continue
            }
            break
        } while true

        guard let http = response.response as? HTTPURLResponse else {
            throw SpotifyAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(SpotifyErrorResponse.self, from: response.data))
                .map { $0.error.message }
            throw SpotifyAPIError.httpError(http.statusCode, message: message)
        }

        let decoder = JSONDecoder()
        let body = try decoder.decode(SpotifySavedTracksResponse.self, from: response.data)
        return (body.items, body.next, body.total)
    }

    nonisolated private static func fetchJSON<T: Decodable>(url: URL, token: String) async throws -> T {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse else { throw SpotifyAPIError.invalidResponse }
        if http.statusCode == 429 {
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) } ?? 5
            try await Task.sleep(nanoseconds: UInt64(retryAfter) * 1_000_000_000)
            return try await fetchJSON(url: url, token: token)
        }
        guard (200..<300).contains(http.statusCode) else {
            let parsed = try? JSONDecoder().decode(SpotifyErrorResponse.self, from: data)
            let message = parsed?.error.message
            if http.statusCode == 403, let raw = String(data: data, encoding: .utf8), raw.count < 500 {
                DebugLog.error("Spotify 403 response: \(raw)")
            }
            throw SpotifyAPIError.httpError(http.statusCode, message: message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Persistence

    nonisolated private static func fetchExistingSourceTracks(context: ModelContext) -> [String: SourceTrack] {
        let spotifyRaw = Source.spotify.rawValue
        let predicate = #Predicate<SourceTrack> { $0.sourceRawValue == spotifyRaw }
        let descriptor = FetchDescriptor<SourceTrack>(predicate: predicate)
        let existing = (try? context.fetch(descriptor)) ?? []
        return Dictionary(uniqueKeysWithValues: existing.map { ($0.sourceId, $0) })
    }

    nonisolated private static func fetchExistingTrack(title: String, artistName: String, albumName: String, context: ModelContext) -> Track? {
        let predicate = #Predicate<Track> {
            $0.title == title && $0.artistName == artistName && $0.albumName == albumName
        }
        let descriptor = FetchDescriptor<Track>(predicate: predicate)
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Mapping

    nonisolated private static func makeTrack(from track: SpotifyTrack, addedAt: Date? = nil) -> Track {
        let artworkURL = Self.bestArtworkURL(from: track.album.images)
        let releaseDate = Self.parseReleaseDate(track.album.releaseDate ?? "")
        return Track(
            title: track.name,
            artistName: track.artists.first?.name ?? "Unknown Artist",
            albumName: track.album.name,
            albumArtistName: nil,
            artworkURL: artworkURL,
            durationMs: track.durationMs,
            genreNames: [],
            releaseDate: releaseDate,
            isExplicit: track.explicit,
            isrc: track.externalIds?.isrc,
            discNumber: track.discNumber,
            trackNumber: track.trackNumber,
            composerName: nil,
            addedAt: addedAt,
            lastSyncedAt: .now
        )
    }

    /// Updates Track with Spotify data. Preserves existing non-nil metadata (genres, composer, artwork)
    /// when Spotify would overwrite with empty — prefers Apple Music artwork when Track has Apple Music source.
    nonisolated private static func updateTrackPreservingExistingMetadata(_ track: Track, from spotify: SpotifyTrack, spotifyAddedAt: Date? = nil) {
        track.title = spotify.name
        track.artistName = spotify.artists.first?.name ?? "Unknown Artist"
        track.albumName = spotify.album.name
        track.durationMs = spotify.durationMs
        track.releaseDate = Self.parseReleaseDate(spotify.album.releaseDate ?? "") ?? track.releaseDate
        track.isExplicit = spotify.explicit
        if let isrc = spotify.externalIds?.isrc { track.isrc = isrc }
        track.discNumber = spotify.discNumber
        track.trackNumber = spotify.trackNumber
        track.lastSyncedAt = .now
        let spotifyArtwork = Self.bestArtworkURL(from: spotify.album.images)
        let hasAppleMusic = track.sourceTracks.contains { $0.source == .appleMusic }
        if hasAppleMusic && track.artworkURL != nil {
            /* Prefer Apple Music artwork, keep existing */
        } else if let url = spotifyArtwork {
            track.artworkURL = url
        }
        if let added = spotifyAddedAt, let existing = track.addedAt, added < existing {
            track.addedAt = added
        }
    }

    nonisolated private static func makeSourceTrack(from track: SpotifyTrack, addedAt: Date?) -> SourceTrack {
        let artworkURL = Self.bestArtworkURL(from: track.album.images)
        return SourceTrack(
            source: .spotify,
            sourceId: track.id,
            addedAt: addedAt,
            playCount: nil,
            lastPlayedDate: nil,
            rating: nil,
            popularity: track.popularity,
            previewURL: track.previewUrl.flatMap { URL(string: $0) },
            artworkURL: artworkURL,
            lastSyncedAt: .now,
            track: nil
        )
    }

    nonisolated private static func updateSourceTrack(_ sourceTrack: SourceTrack, from track: SpotifyTrack, addedAt: Date?) {
        sourceTrack.addedAt = addedAt
        sourceTrack.popularity = track.popularity
        sourceTrack.previewURL = track.previewUrl.flatMap { URL(string: $0) }
        sourceTrack.artworkURL = Self.bestArtworkURL(from: track.album.images)
        sourceTrack.lastSyncedAt = .now
    }

    nonisolated private static func bestArtworkURL(from images: [SpotifyImage]) -> URL? {
        let targetSize = 150
        let suitable = images.filter { ($0.width ?? 0) >= targetSize || ($0.height ?? 0) >= targetSize }
        return (suitable.last ?? images.last)?.url
    }

    nonisolated private static func parseReleaseDate(_ s: String) -> Date? {
        let formatters: [(String, DateFormatter)] = [
            ("yyyy-MM-dd", {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                f.timeZone = TimeZone(identifier: "UTC")
                return f
            }()),
            ("yyyy-MM", {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM"
                f.timeZone = TimeZone(identifier: "UTC")
                return f
            }()),
            ("yyyy", {
                let f = DateFormatter()
                f.dateFormat = "yyyy"
                f.timeZone = TimeZone(identifier: "UTC")
                return f
            }()),
        ]
        for (_, formatter) in formatters {
            if let d = formatter.date(from: s) { return d }
        }
        return nil
    }

    nonisolated private static func parseISO8601(_ s: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var d = formatter.date(from: s)
        if d == nil {
            formatter.formatOptions = [.withInternetDateTime]
            d = formatter.date(from: s)
        }
        return d
    }

    // MARK: - Playlist Sync

    func syncPlaylists() async {
        DebugLog.log("Spotify API: playlist sync starting...")
        guard let container = modelContainer else { return }
        guard authService.isConnected else { return }

        let token: String
        do {
            token = try await authService.getAccessToken()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }

        let result: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            do {
                var existingSourceTracks = Self.fetchExistingSourceTracks(context: context)
                var existingPlaylists = Self.fetchExistingPlaylists(context: context)

                var nextURL: URL? = URL(string: "\(spotifyAPIBase)/me/playlists")!
                nextURL?.append(queryItems: [
                    URLQueryItem(name: "limit", value: "\(pageLimit)"),
                    URLQueryItem(name: "offset", value: "0"),
                ])

                while let url = nextURL {
                    let page: SpotifyPlaylistsResponse = try await Self.fetchJSON(url: url, token: token)
                    for item in page.items {
                        try await Self.upsertPlaylist(item, context: context, token: token, existingSourceTracks: &existingSourceTracks, existingPlaylists: &existingPlaylists)
                    }
                    if let nextStr = page.next, let next = URL(string: nextStr) {
                        nextURL = next
                        await Task.yield()
                    } else {
                        nextURL = nil
                    }
                }

                try context.save()
                DebugLog.log("Spotify API: playlist sync complete")
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value

        if case .failure(let error) = result {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            DebugLog.error("Spotify API: playlist sync failed - \(error.localizedDescription)")
        }
    }

    nonisolated private static func fetchExistingPlaylists(context: ModelContext) -> [String: Playlist] {
        let spotifyRaw = Source.spotify.rawValue
        let predicate = #Predicate<Playlist> { $0.sourceRawValue == spotifyRaw }
        let descriptor = FetchDescriptor<Playlist>(predicate: predicate)
        let existing = (try? context.fetch(descriptor)) ?? []
        return Dictionary(uniqueKeysWithValues: existing.map { ($0.sourceId, $0) })
    }

    nonisolated private static func upsertPlaylist(_ item: SpotifyPlaylistItem, context: ModelContext, token: String, existingSourceTracks: inout [String: SourceTrack], existingPlaylists: inout [String: Playlist]) async throws {
        let playlistId = item.id
        let now = Date.now
        let trackCount = item.tracks?.total ?? 0
        let artworkURL = bestArtworkURL(from: item.images)
        let ownerName = item.owner.displayName

        let playlist: Playlist
        if let existing = existingPlaylists[playlistId] {
            playlist = existing
            playlist.name = item.name
            playlist.descriptionText = item.description
            playlist.artworkURL = artworkURL
            playlist.trackCount = trackCount
            playlist.ownerName = ownerName
            playlist.isPublic = item.public
            playlist.lastSyncedAt = now
        } else {
            playlist = Playlist(
                source: .spotify,
                sourceId: playlistId,
                name: item.name,
                descriptionText: item.description,
                artworkURL: artworkURL,
                trackCount: trackCount,
                ownerName: ownerName,
                isPublic: item.public,
                lastSyncedAt: now
            )
            context.insert(playlist)
            existingPlaylists[playlistId] = playlist
        }

        for existingPT in Array(playlist.playlistTracks) {
            context.delete(existingPT)
        }

        var nextURL: URL? = URL(string: "\(spotifyAPIBase)/playlists/\(playlistId)/tracks")!
        nextURL?.append(queryItems: [
            URLQueryItem(name: "limit", value: "\(pageLimit)"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "additional_types", value: "track"),
        ])
        var position = 0

        while let url = nextURL {
            let page: SpotifyPlaylistTracksResponse = try await fetchJSON(url: url, token: token)
            for playlistItem in page.items {
                guard let spotifyTrack = playlistItem.track else { continue }
                let spotifyId = spotifyTrack.id
                let addedAt = parseISO8601(playlistItem.addedAt ?? "")

                let track: Track
                if let sourceTrack = existingSourceTracks[spotifyId] {
                    if let t = sourceTrack.track {
                        track = t
                    } else { continue }
                } else {
                    let title = spotifyTrack.name
                    let artistName = spotifyTrack.artists.first?.name ?? "Unknown Artist"
                    let albumName = spotifyTrack.album.name
                    let existingTrack = fetchExistingTrack(title: title, artistName: artistName, albumName: albumName, context: context)
                    if let existingTrack {
                        track = existingTrack
                        let sourceTrack = makeSourceTrack(from: spotifyTrack, addedAt: addedAt)
                        sourceTrack.track = existingTrack
                        context.insert(sourceTrack)
                        existingSourceTracks[spotifyId] = sourceTrack
                        updateTrackPreservingExistingMetadata(existingTrack, from: spotifyTrack, spotifyAddedAt: addedAt)
                    } else {
                        track = makeTrack(from: spotifyTrack, addedAt: addedAt)
                        context.insert(track)
                        let sourceTrack = makeSourceTrack(from: spotifyTrack, addedAt: addedAt)
                        sourceTrack.track = track
                        context.insert(sourceTrack)
                        existingSourceTracks[spotifyId] = sourceTrack
                    }
                }

                let playlistTrack = PlaylistTrack(position: position, addedAt: addedAt, playlist: playlist, track: track)
                context.insert(playlistTrack)
                position += 1
            }

            if let nextStr = page.next, let next = URL(string: nextStr) {
                nextURL = next
                await Task.yield()
            } else {
                nextURL = nil
            }
        }

        playlist.trackCount = position
    }

    // MARK: - Album Sync

    func syncAlbums() async {
        DebugLog.log("Spotify API: album sync starting...")
        guard let container = modelContainer else { return }
        guard authService.isConnected else { return }

        let token: String
        do {
            token = try await authService.getAccessToken()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return
        }

        let result: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            do {
                var existingAlbums = Self.fetchExistingAlbums(context: context)

                var nextURL: URL? = URL(string: "\(spotifyAPIBase)/me/albums")!
                nextURL?.append(queryItems: [
                    URLQueryItem(name: "limit", value: "\(pageLimit)"),
                    URLQueryItem(name: "offset", value: "0"),
                ])

                while let url = nextURL {
                    let page: SpotifySavedAlbumsResponse = try await Self.fetchJSON(url: url, token: token)
                    for item in page.items {
                        Self.upsertAlbum(item.album, context: context, existingAlbums: &existingAlbums)
                    }
                    if let nextStr = page.next, let next = URL(string: nextStr) {
                        nextURL = next
                        await Task.yield()
                    } else {
                        nextURL = nil
                    }
                }

                try context.save()
                DebugLog.log("Spotify API: album sync complete")
                return .success(())
            } catch {
                return .failure(error)
            }
        }.value

        if case .failure(let error) = result {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            DebugLog.error("Spotify API: album sync failed - \(error.localizedDescription)")
        }
    }

    nonisolated private static func fetchExistingAlbums(context: ModelContext) -> [String: Album] {
        let spotifyRaw = Source.spotify.rawValue
        let predicate = #Predicate<Album> { $0.sourceRawValue == spotifyRaw }
        let descriptor = FetchDescriptor<Album>(predicate: predicate)
        let existing = (try? context.fetch(descriptor)) ?? []
        return Dictionary(uniqueKeysWithValues: existing.map { ($0.sourceId, $0) })
    }

    nonisolated private static func upsertAlbum(_ spotifyAlbum: SpotifyAlbumFull, context: ModelContext, existingAlbums: inout [String: Album]) {
        let albumId = spotifyAlbum.id
        let now = Date.now
        let artistName = spotifyAlbum.artists.first?.name ?? "Unknown Artist"
        let artworkURL = bestArtworkURL(from: spotifyAlbum.images)
        let releaseDate = parseReleaseDate(spotifyAlbum.releaseDate)

        if let existing = existingAlbums[albumId] {
            existing.name = spotifyAlbum.name
            existing.artistName = artistName
            existing.artworkURL = artworkURL
            existing.releaseDate = releaseDate
            existing.trackCount = spotifyAlbum.totalTracks
            existing.genreNames = spotifyAlbum.genres ?? []
            existing.lastSyncedAt = now
        } else {
            let album = Album(
                source: .spotify,
                sourceId: albumId,
                name: spotifyAlbum.name,
                artistName: artistName,
                artworkURL: artworkURL,
                releaseDate: releaseDate,
                trackCount: spotifyAlbum.totalTracks,
                genreNames: spotifyAlbum.genres ?? [],
                lastSyncedAt: now
            )
            context.insert(album)
            existingAlbums[albumId] = album
        }
    }
}

private struct SpotifyErrorResponse: Decodable {
    let error: SpotifyErrorDetail
}

private struct SpotifyErrorDetail: Decodable {
    let status: Int
    let message: String
}

enum SpotifyAPIError: LocalizedError {
    case invalidResponse
    case httpError(Int, message: String? = nil)
    case rateLimited(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from Spotify."
        case .httpError(let code, let msg):
            if let msg, !msg.isEmpty { return "Spotify (\(code)): \(msg)" }
            return "Spotify error (\(code))."
        case .rateLimited(let msg): return msg
        }
    }
}
