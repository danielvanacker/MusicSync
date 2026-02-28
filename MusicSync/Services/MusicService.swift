import Foundation
import MusicKit

@MainActor
class MusicService: ObservableObject {
    @Published var authorizationStatus: MusicAuthorization.Status = .notDetermined
    @Published var songs: [Song] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    var songCount: Int { songs.count }

    func requestAuthorization() async {
        let status = await MusicAuthorization.request()
        authorizationStatus = status

        if status == .authorized {
            await fetchLibrarySongs()
        }
    }

    func checkAuthorizationStatus() {
        authorizationStatus = MusicAuthorization.currentStatus
    }

    func fetchLibrarySongs() async {
        isLoading = true
        errorMessage = nil
        songs = []

        do {
            var allSongs: [Song] = []
            var request = MusicLibraryRequest<Song>()
            request.sort(by: \.dateAdded, ascending: false)

            var response = try await request.response()
            allSongs.append(contentsOf: response.items)

            while response.hasNextBatch {
                response = try await response.nextBatch()!
                allSongs.append(contentsOf: response.items)
            }

            songs = allSongs
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
