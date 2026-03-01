import Foundation
import SwiftData

@Model
final class Playlist: Hashable {
    #Unique<Playlist>([\.sourceRawValue, \.sourceId])

    var sourceRawValue: String
    var sourceId: String
    var name: String
    var descriptionText: String?
    var artworkURL: URL?
    var trackCount: Int
    var ownerName: String?
    var isPublic: Bool?
    var lastSyncedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \PlaylistTrack.playlist)
    var playlistTracks: [PlaylistTrack] = []

    var source: Source {
        get { Source(rawValue: sourceRawValue) ?? .appleMusic }
        set { sourceRawValue = newValue.rawValue }
    }

    init(
        source: Source,
        sourceId: String,
        name: String,
        descriptionText: String? = nil,
        artworkURL: URL? = nil,
        trackCount: Int = 0,
        ownerName: String? = nil,
        isPublic: Bool? = nil,
        lastSyncedAt: Date = .now
    ) {
        self.sourceRawValue = source.rawValue
        self.sourceId = sourceId
        self.name = name
        self.descriptionText = descriptionText
        self.artworkURL = artworkURL
        self.trackCount = trackCount
        self.ownerName = ownerName
        self.isPublic = isPublic
        self.lastSyncedAt = lastSyncedAt
    }

    static func == (lhs: Playlist, rhs: Playlist) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
