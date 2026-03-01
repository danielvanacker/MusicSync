import Foundation
import SwiftData

/// ISRC-based deduplication: merges Track rows that have the same ISRC across different sources.
/// Applies canonical metadata strategy when merging.
/// Can run on any thread; use with a ModelContext created on that thread.
/// - Returns: Number of duplicate tracks merged (removed).
nonisolated func runDedup(context: ModelContext) throws -> Int {
    let descriptor = FetchDescriptor<Track>()
    let allTracks = (try? context.fetch(descriptor)) ?? []
    var mergedCount = 0

    let tracksByIsrc = Dictionary(
        grouping: allTracks.filter { ($0.isrc ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased().isEmpty == false },
        by: { ($0.isrc ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
    )

    for (_, group) in tracksByIsrc where group.count > 1 {
        let survivor = pickSurvivor(from: group)
        let orphans = group.filter { $0.id != survivor.id }
        if orphans.isEmpty { continue }

        for orphan in orphans {
            for sourceTrack in orphan.sourceTracks {
                sourceTrack.track = survivor
            }
            mergedCount += 1
        }
        applyCanonicalMetadata(to: survivor, from: group)
        for orphan in orphans {
            context.delete(orphan)
        }
    }

    if mergedCount > 0 {
        try context.save()
    }
    return mergedCount
}

private nonisolated func pickSurvivor(from tracks: [Track]) -> Track {
    let withAppleMusic = tracks.filter { $0.sourceTracks.contains { $0.source == .appleMusic } }
    return withAppleMusic.first ?? tracks[0]
}

private nonisolated func applyCanonicalMetadata(to survivor: Track, from allTracksInGroup: [Track]) {
    let others = allTracksInGroup.filter { $0.id != survivor.id }
    let all = [survivor] + others

    let appleMusicArtwork = all.compactMap { $0.sourceTracks.contains { $0.source == .appleMusic } ? $0.artworkURL : nil }.first
    let fallbackArtwork = all.compactMap(\.artworkURL).first
    survivor.artworkURL = appleMusicArtwork ?? fallbackArtwork ?? survivor.artworkURL

    let addedDates = all.compactMap(\.addedAt)
    if let earliest = addedDates.min() {
        survivor.addedAt = earliest
    }

    var mergedGenres: Set<String> = Set(survivor.genreNames)
    for t in others {
        mergedGenres.formUnion(t.genreNames)
    }
    if !mergedGenres.isEmpty {
        survivor.genreNames = mergedGenres.sorted()
    }

    if survivor.albumArtistName == nil {
        survivor.albumArtistName = others.compactMap(\.albumArtistName).first
    }
    if survivor.composerName == nil {
        survivor.composerName = others.compactMap(\.composerName).first
    }
    if survivor.releaseDate == nil {
        survivor.releaseDate = others.compactMap(\.releaseDate).first
    }
}
