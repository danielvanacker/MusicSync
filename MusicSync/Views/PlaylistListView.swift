import SwiftData
import SwiftUI

struct PlaylistListView: View {
    @EnvironmentObject var syncService: SyncService
    @Query(sort: \Playlist.name, order: .forward) private var allPlaylists: [Playlist]
    @State private var selectedSourceFilter: LibrarySourceFilter = .all
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var displayedPlaylists: [Playlist] = []
    @State private var displayedVersion = 0

    private var sourceFilteredPlaylists: [Playlist] {
        switch selectedSourceFilter {
        case .all:
            return allPlaylists
        case .appleMusic:
            return allPlaylists.filter { $0.sourceRawValue == Source.appleMusic.rawValue }
        case .spotify:
            return allPlaylists.filter { $0.sourceRawValue == Source.spotify.rawValue }
        case .both:
            return []
        }
    }

    private func computeDisplayedPlaylists() -> [Playlist] {
        let filtered = sourceFilteredPlaylists
        let query = debouncedSearchText
        if query.isEmpty {
            return filtered
        }
        let q = query.localizedLowercase
        return filtered.filter {
            $0.name.localizedLowercase.contains(q)
            || ($0.ownerName?.localizedLowercase.contains(q) ?? false)
        }
    }

    private func count(for filter: LibrarySourceFilter) -> Int {
        switch filter {
        case .all: return allPlaylists.count
        case .appleMusic: return allPlaylists.filter { $0.sourceRawValue == Source.appleMusic.rawValue }.count
        case .spotify: return allPlaylists.filter { $0.sourceRawValue == Source.spotify.rawValue }.count
        case .both: return 0
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                sourceFilterPicker
                List {
                    Section {
                        ForEach(displayedPlaylists) { playlist in
                            NavigationLink(value: playlist) {
                                PlaylistRowView(playlist: playlist)
                            }
                        }
                    } header: {
                        Text("\(displayedPlaylists.count) playlists")
                            .textCase(nil)
                    }
                }
                .listStyle(.plain)
                .navigationDestination(for: Playlist.self) { playlist in
                    PlaylistDetailView(playlist: playlist)
                }
                .environment(\.artworkLoadingEnabled, !syncService.isSyncing)
            }
        }
        .searchable(text: $searchText, prompt: "Search playlists")
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(450))
            debouncedSearchText = searchText
        }
        .task(id: "filter-\(debouncedSearchText)-\(selectedSourceFilter.rawValue)-\(allPlaylists.count)") {
            displayedPlaylists = computeDisplayedPlaylists()
            displayedVersion += 1
        }
    }

    private var sourceFilterPicker: some View {
        Picker("Source", selection: $selectedSourceFilter) {
            Text("All (\(count(for: .all).formatted(.number)))").tag(LibrarySourceFilter.all)
            Text("Apple Music (\(count(for: .appleMusic).formatted(.number)))").tag(LibrarySourceFilter.appleMusic)
            Text("Spotify (\(count(for: .spotify).formatted(.number)))").tag(LibrarySourceFilter.spotify)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
