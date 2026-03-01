import SwiftData
import SwiftUI

struct AlbumListView: View {
    @EnvironmentObject var syncService: SyncService
    @Query(sort: \Album.name, order: .forward) private var allAlbums: [Album]
    @State private var selectedSourceFilter: LibrarySourceFilter = .all
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var displayedAlbums: [Album] = []
    @State private var displayedVersion = 0

    private var sourceFilteredAlbums: [Album] {
        switch selectedSourceFilter {
        case .all:
            return allAlbums
        case .appleMusic:
            return allAlbums.filter { $0.sourceRawValue == Source.appleMusic.rawValue }
        case .spotify:
            return allAlbums.filter { $0.sourceRawValue == Source.spotify.rawValue }
        case .both:
            return []
        }
    }

    private func computeDisplayedAlbums() -> [Album] {
        let filtered = sourceFilteredAlbums
        let query = debouncedSearchText
        if query.isEmpty {
            return filtered
        }
        let q = query.localizedLowercase
        return filtered.filter {
            $0.name.localizedLowercase.contains(q)
            || $0.artistName.localizedLowercase.contains(q)
        }
    }

    private func count(for filter: LibrarySourceFilter) -> Int {
        switch filter {
        case .all: return allAlbums.count
        case .appleMusic: return allAlbums.filter { $0.sourceRawValue == Source.appleMusic.rawValue }.count
        case .spotify: return allAlbums.filter { $0.sourceRawValue == Source.spotify.rawValue }.count
        case .both: return 0
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                sourceFilterPicker
                List {
                    Section {
                        ForEach(displayedAlbums) { album in
                            NavigationLink(value: album) {
                                AlbumRowView(album: album)
                            }
                        }
                    } header: {
                        Text("\(displayedAlbums.count) albums")
                            .textCase(nil)
                    }
                }
                .listStyle(.plain)
                .navigationDestination(for: Album.self) { album in
                    AlbumDetailView(album: album)
                }
                .environment(\.artworkLoadingEnabled, !syncService.isSyncing)
            }
        }
        .searchable(text: $searchText, prompt: "Search albums")
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(450))
            debouncedSearchText = searchText
        }
        .task(id: "filter-\(debouncedSearchText)-\(selectedSourceFilter.rawValue)-\(allAlbums.count)") {
            displayedAlbums = computeDisplayedAlbums()
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
