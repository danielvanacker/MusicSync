import Foundation
import SwiftData

@Model
final class Album: Hashable {
    #Unique<Album>([\.sourceRawValue, \.sourceId])

    var sourceRawValue: String
    var sourceId: String
    var name: String
    var artistName: String
    var artworkURL: URL?
    var releaseDate: Date?
    var trackCount: Int
    var genreNames: [String]
    var lastSyncedAt: Date

    var source: Source {
        get { Source(rawValue: sourceRawValue) ?? .appleMusic }
        set { sourceRawValue = newValue.rawValue }
    }

    init(
        source: Source,
        sourceId: String,
        name: String,
        artistName: String,
        artworkURL: URL? = nil,
        releaseDate: Date? = nil,
        trackCount: Int = 0,
        genreNames: [String] = [],
        lastSyncedAt: Date = .now
    ) {
        self.sourceRawValue = source.rawValue
        self.sourceId = sourceId
        self.name = name
        self.artistName = artistName
        self.artworkURL = artworkURL
        self.releaseDate = releaseDate
        self.trackCount = trackCount
        self.genreNames = genreNames
        self.lastSyncedAt = lastSyncedAt
    }

    static func == (lhs: Album, rhs: Album) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
