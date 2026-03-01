import Foundation
import SwiftData

@Model
final class Track: Hashable {
    #Unique<Track>([\.title, \.artistName, \.albumName])

    var title: String
    var artistName: String
    var albumName: String
    var albumArtistName: String?
    var artworkURL: URL?
    var durationMs: Int
    var genreNames: [String]
    var releaseDate: Date?
    var isExplicit: Bool
    var isrc: String?
    var discNumber: Int?
    var trackNumber: Int?
    var composerName: String?
    var addedAt: Date?
    var lastSyncedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \SourceTrack.track)
    var sourceTracks: [SourceTrack] = []

    init(
        title: String,
        artistName: String,
        albumName: String,
        albumArtistName: String? = nil,
        artworkURL: URL? = nil,
        durationMs: Int,
        genreNames: [String] = [],
        releaseDate: Date? = nil,
        isExplicit: Bool = false,
        isrc: String? = nil,
        discNumber: Int? = nil,
        trackNumber: Int? = nil,
        composerName: String? = nil,
        addedAt: Date? = nil,
        lastSyncedAt: Date = .now
    ) {
        self.title = title
        self.artistName = artistName
        self.albumName = albumName
        self.albumArtistName = albumArtistName
        self.artworkURL = artworkURL
        self.durationMs = durationMs
        self.genreNames = genreNames
        self.releaseDate = releaseDate
        self.isExplicit = isExplicit
        self.isrc = isrc
        self.discNumber = discNumber
        self.trackNumber = trackNumber
        self.composerName = composerName
        self.addedAt = addedAt
        self.lastSyncedAt = lastSyncedAt
    }

    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
