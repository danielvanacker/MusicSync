import Foundation
import SwiftData

@Model
final class PlaylistTrack {
    var position: Int
    var addedAt: Date?
    var playlist: Playlist?
    var track: Track?

    init(
        position: Int,
        addedAt: Date? = nil,
        playlist: Playlist? = nil,
        track: Track? = nil
    ) {
        self.position = position
        self.addedAt = addedAt
        self.playlist = playlist
        self.track = track
    }
}
