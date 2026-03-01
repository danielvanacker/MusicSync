import Foundation
import SwiftData

@Model
final class SourceTrack {
    #Unique<SourceTrack>([\.sourceRawValue, \.sourceId])

    var sourceRawValue: String
    var sourceId: String

    var source: Source {
        get { Source(rawValue: sourceRawValue) ?? .appleMusic }
        set { sourceRawValue = newValue.rawValue }
    }
    var addedAt: Date?
    var playCount: Int?
    var lastPlayedDate: Date?
    var rating: Int?
    var popularity: Int?
    var previewURL: URL?
    var artworkURL: URL?
    var lastSyncedAt: Date

    var track: Track?

    init(
        source: Source,
        sourceId: String,
        addedAt: Date? = nil,
        playCount: Int? = nil,
        lastPlayedDate: Date? = nil,
        rating: Int? = nil,
        popularity: Int? = nil,
        previewURL: URL? = nil,
        artworkURL: URL? = nil,
        lastSyncedAt: Date = .now,
        track: Track? = nil
    ) {
        self.sourceRawValue = source.rawValue
        self.sourceId = sourceId
        self.addedAt = addedAt
        self.playCount = playCount
        self.lastPlayedDate = lastPlayedDate
        self.rating = rating
        self.popularity = popularity
        self.previewURL = previewURL
        self.artworkURL = artworkURL
        self.lastSyncedAt = lastSyncedAt
        self.track = track
    }
}
