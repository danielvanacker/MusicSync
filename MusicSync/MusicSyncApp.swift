import SwiftData
import SwiftUI

@main
struct MusicSyncApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appleMusicService: AppleMusicService
    @StateObject private var spotifyAuthService: SpotifyAuthService
    @StateObject private var spotifyAPIService: SpotifyAPIService
    @StateObject private var syncService: SyncService
    let modelContainer: ModelContainer

    init() {
        let appleMusic = AppleMusicService()
        let auth = SpotifyAuthService()
        let spotifyAPI = SpotifyAPIService(authService: auth)
        _appleMusicService = StateObject(wrappedValue: appleMusic)
        _spotifyAuthService = StateObject(wrappedValue: auth)
        _spotifyAPIService = StateObject(wrappedValue: spotifyAPI)
        _syncService = StateObject(wrappedValue: SyncService(
            appleMusicService: appleMusic,
            spotifyAPIService: spotifyAPI,
            spotifyAuthService: auth
        ))
        do {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let storeDir = appSupport.appendingPathComponent("MusicSync", isDirectory: true)
            try FileManager.default.createDirectory(at: storeDir, withIntermediateDirectories: true)
            let storeURL = storeDir.appendingPathComponent("default.store")
            let config = ModelConfiguration(url: storeURL)
            modelContainer = try ModelContainer(for: Track.self, SourceTrack.self, Playlist.self, PlaylistTrack.self, Album.self, configurations: config)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appleMusicService)
                .environmentObject(spotifyAuthService)
                .environmentObject(spotifyAPIService)
                .environmentObject(syncService)
                .onAppear {
                    DebugLog.log("App launched, setting model context and container")
                    appleMusicService.setModelContext(modelContainer.mainContext)
                    appleMusicService.setModelContainer(modelContainer)
                    spotifyAPIService.setModelContext(modelContainer.mainContext)
                    spotifyAPIService.setModelContainer(modelContainer)
                    syncService.setModelContext(modelContainer.mainContext)
                    syncService.setModelContainer(modelContainer)
                }
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                appleMusicService.checkAuthorizationStatus()
            }
        }
    }
}
