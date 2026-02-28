import SwiftUI

@main
struct MusicSyncApp: App {
    @StateObject private var musicService = MusicService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(musicService)
        }
    }
}
