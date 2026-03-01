import Combine
import Foundation
import MusicKit
import SwiftData
import SwiftUI

// MARK: - SourceSyncStatus

enum SourceSyncStatus: Equatable {
    case idle
    case syncing
    case error(String)
    case completed(lastSynced: Date)

    var isSyncing: Bool {
        if case .syncing = self { return true }
        return false
    }

    var lastSyncedDate: Date? {
        if case .completed(let date) = self { return date }
        return nil
    }
}

// MARK: - SyncService

private enum SyncDefaults {
    static let lastSyncedAppleMusic = "lastSyncedAppleMusic"
    static let lastSyncedSpotify = "lastSyncedSpotify"
    static let lastSyncedAt = "lastSyncedAt"
}

@MainActor
final class SyncService: ObservableObject {
    @Published private(set) var appleMusicStatus: SourceSyncStatus = .idle
    @Published private(set) var spotifyStatus: SourceSyncStatus = .idle

    var isSyncing: Bool {
        appleMusicStatus.isSyncing || spotifyStatus.isSyncing
    }

    /// When the last full sync (all sources + dedup) completed. Used for "Synced at X" notification.
    @Published private(set) var lastSyncedAt: Date?

    /// First error from any source, for unified error display.
    var firstErrorMessage: String? {
        if case .error(let msg) = appleMusicStatus { return msg }
        if case .error(let msg) = spotifyStatus { return msg }
        return nil
    }

    private let appleMusicService: AppleMusicService
    private let spotifyAPIService: SpotifyAPIService
    private let spotifyAuthService: SpotifyAuthService
    private var modelContext: ModelContext?
    private var modelContainer: ModelContainer?
    private let defaults = UserDefaults.standard

    /// Sources that completed recently within this interval are skipped by syncAll.
    /// Pull-to-refresh and syncSource bypass this.
    private let stalenessThreshold: TimeInterval = 5 * 60

    /// Ensures sync operations run one at a time (queued).
    private var syncTask: Task<Void, Never>?

    func setModelContext(_ context: ModelContext) {
        modelContext = context
    }

    func setModelContainer(_ container: ModelContainer) {
        modelContainer = container
    }

    init(
        appleMusicService: AppleMusicService,
        spotifyAPIService: SpotifyAPIService,
        spotifyAuthService: SpotifyAuthService
    ) {
        self.appleMusicService = appleMusicService
        self.spotifyAPIService = spotifyAPIService
        self.spotifyAuthService = spotifyAuthService

        // Restore persisted sync dates
        if let interval = defaults.object(forKey: SyncDefaults.lastSyncedAppleMusic) as? TimeInterval {
            appleMusicStatus = .completed(lastSynced: Date(timeIntervalSince1970: interval))
        }
        if let interval = defaults.object(forKey: SyncDefaults.lastSyncedSpotify) as? TimeInterval {
            spotifyStatus = .completed(lastSynced: Date(timeIntervalSince1970: interval))
        }
        if let interval = defaults.object(forKey: SyncDefaults.lastSyncedAt) as? TimeInterval {
            lastSyncedAt = Date(timeIntervalSince1970: interval)
        }
    }

    // MARK: - Public API

    /// Sync all connected sources. Skips sources that completed within stalenessThreshold.
    func syncAll(force: Bool = false) async {
        let previousTask = syncTask
        let ourTask = Task {
            await previousTask?.value
            await performSync(force: force)
        }
        syncTask = ourTask
        await ourTask.value
    }

    /// Sync a single source (+ dedup). Always runs regardless of staleness.
    func syncSource(_ source: Source) async {
        let previousTask = syncTask
        let ourTask = Task {
            await previousTask?.value
            await performSyncSource(source)
        }
        syncTask = ourTask
        await ourTask.value
    }

    // MARK: - Sync implementation

    private func performSync(force: Bool) async {
        DebugLog.log("SyncService: syncAll starting (force=\(force))")

        if appleMusicService.authorizationStatus == .authorized {
            if force || isStale(.appleMusic) {
                await syncAppleMusic()
            } else {
                DebugLog.log("SyncService: skipping Apple Music (synced recently)")
            }
        } else {
            DebugLog.log("SyncService: skipping Apple Music (not authorized)")
        }

        if spotifyAuthService.isConnected {
            if force || isStale(.spotify) {
                await syncSpotify()
            } else {
                DebugLog.log("SyncService: skipping Spotify (synced recently)")
            }
        } else {
            DebugLog.log("SyncService: skipping Spotify (not connected)")
        }

        await performDedup()
        let now = Date.now
        lastSyncedAt = now
        defaults.set(now.timeIntervalSince1970, forKey: SyncDefaults.lastSyncedAt)
        DebugLog.log("SyncService: syncAll complete")
    }

    private func performSyncSource(_ source: Source) async {
        DebugLog.log("SyncService: syncing single source \(source.rawValue)")

        switch source {
        case .appleMusic:
            guard appleMusicService.authorizationStatus == .authorized else {
                DebugLog.log("SyncService: Apple Music not authorized")
                return
            }
            await syncAppleMusic()
        case .spotify:
            guard spotifyAuthService.isConnected else {
                DebugLog.log("SyncService: Spotify not connected")
                return
            }
            await syncSpotify()
        }

        await performDedup()
        let now = Date.now
        lastSyncedAt = now
        defaults.set(now.timeIntervalSince1970, forKey: SyncDefaults.lastSyncedAt)
        DebugLog.log("SyncService: single-source sync complete")
    }

    private func isStale(_ source: Source) -> Bool {
        let status: SourceSyncStatus
        switch source {
        case .appleMusic: status = appleMusicStatus
        case .spotify: status = spotifyStatus
        }
        guard let lastSynced = status.lastSyncedDate else { return true }
        return Date.now.timeIntervalSince(lastSynced) > stalenessThreshold
    }

    private func syncAppleMusic() async {
        DebugLog.log("SyncService: syncing Apple Music...")
        appleMusicStatus = .syncing

        await appleMusicService.syncLibrary()
        if appleMusicService.errorMessage == nil {
            await appleMusicService.syncPlaylists()
        }
        if appleMusicService.errorMessage == nil {
            await appleMusicService.syncAlbums()
        }

        if let error = appleMusicService.errorMessage {
            appleMusicStatus = .error(error)
            DebugLog.error("SyncService: Apple Music failed - \(error)")
        } else {
            let now = Date.now
            appleMusicStatus = .completed(lastSynced: now)
            defaults.set(now.timeIntervalSince1970, forKey: SyncDefaults.lastSyncedAppleMusic)
            DebugLog.log("SyncService: Apple Music completed")
        }
    }

    private func syncSpotify() async {
        DebugLog.log("SyncService: syncing Spotify...")
        spotifyStatus = .syncing

        await spotifyAPIService.syncLibrary()
        guard spotifyAPIService.errorMessage == nil else {
            spotifyStatus = .error(spotifyAPIService.errorMessage!)
            DebugLog.error("SyncService: Spotify failed - \(spotifyAPIService.errorMessage!)")
            return
        }

        await spotifyAPIService.syncPlaylists()
        if spotifyAPIService.errorMessage != nil {
            DebugLog.error("SyncService: playlist sync failed (continuing) - \(spotifyAPIService.errorMessage!)")
            spotifyAPIService.errorMessage = nil
        }

        await spotifyAPIService.syncAlbums()
        if let error = spotifyAPIService.errorMessage {
            spotifyStatus = .error(error)
            DebugLog.error("SyncService: Spotify failed - \(error)")
        } else {
            let now = Date.now
            spotifyStatus = .completed(lastSynced: now)
            defaults.set(now.timeIntervalSince1970, forKey: SyncDefaults.lastSyncedSpotify)
            DebugLog.log("SyncService: Spotify completed")
        }
    }

    private func performDedup() async {
        guard let container = modelContainer else { return }
        do {
            let merged = try await Task.detached(priority: .userInitiated) {
                let context = ModelContext(container)
                context.autosaveEnabled = false
                return try runDedup(context: context)
            }.value
            if merged > 0 {
                DebugLog.log("SyncService: merged \(merged) duplicate track(s)")
            }
        } catch {
            DebugLog.error("SyncService: dedup failed - \(error.localizedDescription)")
        }
    }

    /// Clear error state for a source so the UI can show idle/completed instead.
    func clearError(for source: Source) {
        switch source {
        case .appleMusic:
            if case .error = appleMusicStatus {
                appleMusicStatus = appleMusicService.isLoading ? .syncing : .idle
            }
        case .spotify:
            if case .error = spotifyStatus {
                spotifyStatus = spotifyAPIService.isLoading ? .syncing : .idle
            }
        }
    }

    /// Dismiss error state for all sources (e.g. when user dismisses error banner).
    func dismissErrors() {
        if case .error = appleMusicStatus { appleMusicStatus = .idle }
        if case .error = spotifyStatus { spotifyStatus = .idle }
    }

    /// Reset status to idle (e.g. when user dismisses an error).
    func resetStatus(for source: Source) {
        switch source {
        case .appleMusic:
            appleMusicStatus = .idle
        case .spotify:
            spotifyStatus = .idle
        }
    }
}
