import MusicKit
import SwiftData
import SwiftUI

enum LibrarySourceFilter: String, CaseIterable {
    case all
    case appleMusic
    case spotify
    case both

    var label: String {
        switch self {
        case .all: return "All"
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        case .both: return "Both"
        }
    }
}

enum LibraryTab: String, CaseIterable {
    case songs
    case playlists
    case albums

    var label: String {
        switch self {
        case .songs: return "Songs"
        case .playlists: return "Playlists"
        case .albums: return "Albums"
        }
    }

    var systemImage: String {
        switch self {
        case .songs: return "music.note.list"
        case .playlists: return "music.note.list"
        case .albums: return "square.stack"
        }
    }
}

enum LibrarySortOption: String, CaseIterable {
    case recentlyAdded
    case title
    case artist
    case album
    case playCount

    var label: String {
        switch self {
        case .recentlyAdded: return "Recently Added"
        case .title: return "Title"
        case .artist: return "Artist"
        case .album: return "Album"
        case .playCount: return "Play Count"
        }
    }

    var systemImage: String {
        switch self {
        case .recentlyAdded: return "clock.arrow.circlepath"
        case .title: return "textformat"
        case .artist: return "music.mic"
        case .album: return "square.stack"
        case .playCount: return "play.circle"
        }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var musicService: AppleMusicService
    @EnvironmentObject var spotifyAuthService: SpotifyAuthService
    @EnvironmentObject var spotifyAPIService: SpotifyAPIService
    @EnvironmentObject var syncService: SyncService
    @Query(sort: \Track.addedAt, order: .reverse) private var allTracks: [Track]
    @State private var showConnectSheet = false
    @State private var disconnectConfirmationSource: Source?
    @State private var selectedSourceFilter: LibrarySourceFilter = .all
    @State private var selectedSortOption: LibrarySortOption = .recentlyAdded
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var displayedTracks: [Track] = []
    @State private var displayedTracksVersion = 0
    @State private var showSyncedToast = false
    @State private var syncedToastTask: Task<Void, Never>?
    @State private var selectedTab: LibraryTab = .songs

    private var sourceFilteredTracks: [Track] {
        switch selectedSourceFilter {
        case .all:
            return allTracks
        case .appleMusic:
            return allTracks.filter { $0.sourceTracks.contains { $0.sourceRawValue == Source.appleMusic.rawValue } }
        case .spotify:
            return allTracks.filter { $0.sourceTracks.contains { $0.sourceRawValue == Source.spotify.rawValue } }
        case .both:
            return allTracks.filter { track in
                track.sourceTracks.contains { $0.sourceRawValue == Source.appleMusic.rawValue }
                && track.sourceTracks.contains { $0.sourceRawValue == Source.spotify.rawValue }
            }
        }
    }

    private func computeDisplayedTracks() async -> [Track] {
        let sourceFiltered = sourceFilteredTracks
        let query = debouncedSearchText
        let sortOption = selectedSortOption

        struct SortKey: Sendable {
            let index: Int
            let title: String
            let artist: String
            let album: String
            let searchable: String
            let addedAt: Date
            let playCount: Int
        }

        let needsPlayCount = sortOption == .playCount
        let keys: [SortKey] = sourceFiltered.enumerated().map { index, track in
            let playCount: Int
            if needsPlayCount {
                playCount = track.sourceTracks.first { $0.source == .appleMusic }?.playCount ?? 0
            } else {
                playCount = 0
            }
            let t = track.title; let a = track.artistName; let b = track.albumName
            return SortKey(
                index: index,
                title: t,
                artist: a,
                album: b,
                searchable: "\(t) \(a) \(b)".localizedLowercase,
                addedAt: track.addedAt ?? .distantPast,
                playCount: playCount
            )
        }

        let indices = await Task.detached(priority: .userInitiated) {
            var filtered = keys
            if !query.isEmpty {
                let q = query.localizedLowercase
                filtered = filtered.filter { $0.searchable.contains(q) }
            }
            switch sortOption {
            case .recentlyAdded:
                filtered.sort { $0.addedAt > $1.addedAt }
            case .title:
                filtered.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            case .artist:
                filtered.sort { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
            case .album:
                filtered.sort { $0.album.localizedCaseInsensitiveCompare($1.album) == .orderedAscending }
            case .playCount:
                filtered.sort { $0.playCount > $1.playCount }
            }
            return filtered.map(\.index)
        }.value

        return indices.map { sourceFiltered[$0] }
    }

    private func count(for filter: LibrarySourceFilter) -> Int {
        switch filter {
        case .all:
            return allTracks.count
        case .appleMusic:
            return allTracks.filter { $0.sourceTracks.contains { $0.sourceRawValue == Source.appleMusic.rawValue } }.count
        case .spotify:
            return allTracks.filter { $0.sourceTracks.contains { $0.sourceRawValue == Source.spotify.rawValue } }.count
        case .both:
            return allTracks.filter { track in
                track.sourceTracks.contains { $0.sourceRawValue == Source.appleMusic.rawValue }
                && track.sourceTracks.contains { $0.sourceRawValue == Source.spotify.rawValue }
            }.count
        }
    }

    private var hasAnySource: Bool {
        musicService.authorizationStatus == .authorized || spotifyAuthService.isConnected
    }

    var body: some View {
        Group {
            if hasAnySource {
                ZStack(alignment: .top) {
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        libraryView
                            .searchable(text: $searchText, prompt: "Search songs")
                            .navigationTitle("Songs")
                            .toolbar { songsToolbar }
                    }
                    .tabItem {
                        Label(LibraryTab.songs.label, systemImage: LibraryTab.songs.systemImage)
                    }
                    .tag(LibraryTab.songs)

                    NavigationStack {
                        PlaylistListView()
                            .navigationTitle("Playlists")
                            .toolbar { libraryToolbar }
                    }
                    .tabItem {
                        Label(LibraryTab.playlists.label, systemImage: LibraryTab.playlists.systemImage)
                    }
                    .tag(LibraryTab.playlists)

                    NavigationStack {
                        AlbumListView()
                            .navigationTitle("Albums")
                            .toolbar { libraryToolbar }
                    }
                    .tabItem {
                        Label(LibraryTab.albums.label, systemImage: LibraryTab.albums.systemImage)
                    }
                    .tag(LibraryTab.albums)
                }
                syncNotificationOverlay
                }
            } else {
                NavigationStack {
                    welcomeView
                }
            }
        }
        .onAppear {
            DebugLog.log("ContentView appeared, checking auth")
            musicService.checkAuthorizationStatus()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                musicService.checkAuthorizationStatus()
            }
        }
        .sheet(isPresented: $showConnectSheet) {
            connectSheetContent
                .environmentObject(musicService)
                .environmentObject(spotifyAuthService)
                .environmentObject(spotifyAPIService)
                .environmentObject(syncService)
        }
    }

    private var connectSheetContent: some View {
        NavigationStack {
            ScrollView {
                connectSourcesView
                    .padding(.vertical, 24)
            }
                .navigationTitle("Music Sources")
                .onAppear {
                    musicService.checkAuthorizationStatus()
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showConnectSheet = false
                        }
                    }
                }
                .alert(disconnectConfirmationSource == .appleMusic ? "Disconnect Apple Music" : "Disconnect Spotify", isPresented: .init(
                    get: { disconnectConfirmationSource != nil },
                    set: { if !$0 { disconnectConfirmationSource = nil } }
                )) {
                    Button("Cancel", role: .cancel) {
                        disconnectConfirmationSource = nil
                    }
                    Button("Disconnect", role: .destructive) {
                        if let source = disconnectConfirmationSource {
                            disconnectSource(source)
                        }
                        disconnectConfirmationSource = nil
                    }
                } message: {
                    if disconnectConfirmationSource == .appleMusic {
                        Text("All Apple Music data will be removed from the app. You will be redirected to Settings to disable access.")
                    } else if disconnectConfirmationSource == .spotify {
                        Text("All Spotify data will be removed from this app. You will be redirected to Spotify's connected apps page to revoke access.")
                    }
                }
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "music.note.list")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Music Library Viewer")
                .font(.title2.bold())

            Text("Connect your music sources to view your library.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            connectSourcesView

            Spacer()
        }
    }

    @ViewBuilder
    private var connectSourcesView: some View {
        VStack(spacing: 16) {
            Group {
                switch musicService.authorizationStatus {
                case .authorized:
                    Button {
                        disconnectConfirmationSource = .appleMusic
                    } label: {
                        Label("Disconnect Apple Music", systemImage: "xmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                case .denied, .restricted:
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Re-enable Apple Music", systemImage: "apple.logo")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.tint)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                case .notDetermined:
                    Button {
                        Task {
                            await musicService.requestAuthorization()
                        }
                    } label: {
                        Label("Connect Apple Music", systemImage: "apple.logo")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.tint)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                    }
                @unknown default:
                    EmptyView()
                }
            }

            Group {
                if spotifyAuthService.isConnected {
                    Button {
                        disconnectConfirmationSource = .spotify
                    } label: {
                        Label("Disconnect Spotify", systemImage: "xmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                    Task {
                        await spotifyAuthService.connect()
                        if spotifyAuthService.isConnected {
                            await syncService.syncSource(.spotify)
                        }
                    }
                    } label: {
                        Label("Connect Spotify", systemImage: "waveform")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(white: 0.9))
                            .foregroundStyle(.primary)
                            .cornerRadius(12)
                    }
                    .disabled(!spotifyAuthService.hasValidClientId)
                }
            }

            if !spotifyAuthService.hasValidClientId, !spotifyAuthService.isConnected {
                Text("Add SPOTIFY_CLIENT_ID to Info.plist to enable Spotify.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let error = spotifyAuthService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            syncStatusSection
        }
        .padding(.horizontal, 40)
    }

    @ViewBuilder
    private var syncStatusSection: some View {
        if hasAnySource {
            VStack(alignment: .leading, spacing: 8) {
                Text("Sync status")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                if musicService.authorizationStatus == .authorized {
                    sourceStatusRow(source: .appleMusic, status: syncService.appleMusicStatus)
                }
                if spotifyAuthService.isConnected {
                    sourceStatusRow(source: .spotify, status: syncService.spotifyStatus)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func sourceStatusRow(source: Source, status: SourceSyncStatus) -> some View {
        HStack {
            Text(source == .appleMusic ? "Apple Music" : "Spotify")
                .font(.subheadline)
            Spacer()
            switch status {
            case .idle:
                Text("Ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .syncing:
                Text("Syncing...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .error(let msg):
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            case .completed(let date):
                Text(relativeTime(from: date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await syncService.syncSource(source) }
            } label: {
                if status.isSyncing {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text("Sync")
                        .font(.caption.bold())
                }
            }
            .disabled(status.isSyncing)
        }
    }

    private func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60)) min ago" }
        if interval < 86400 { return "\(Int(interval / 3600)) hr ago" }
        return "\(Int(interval / 86400)) days ago"
    }

    private func disconnectSource(_ source: Source) {
        deleteRecords(for: source)

        switch source {
        case .appleMusic:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .spotify:
            spotifyAuthService.disconnect()
            if let url = URL(string: "https://www.spotify.com/account/apps/") {
                UIApplication.shared.open(url)
            }
        }

        syncService.resetStatus(for: source)
    }

    private func deleteRecords(for source: Source) {
        let sourceRaw = source.rawValue

        let sourceTrackPredicate = #Predicate<SourceTrack> { $0.sourceRawValue == sourceRaw }
        let sourceTrackDescriptor = FetchDescriptor<SourceTrack>(predicate: sourceTrackPredicate)
        if let sourceTracks = try? modelContext.fetch(sourceTrackDescriptor) {
            for sourceTrack in sourceTracks {
                modelContext.delete(sourceTrack)
            }
        }

        let playlistPredicate = #Predicate<Playlist> { $0.sourceRawValue == sourceRaw }
        let playlistDescriptor = FetchDescriptor<Playlist>(predicate: playlistPredicate)
        if let playlists = try? modelContext.fetch(playlistDescriptor) {
            for playlist in playlists {
                modelContext.delete(playlist)
            }
        }

        let albumPredicate = #Predicate<Album> { $0.sourceRawValue == sourceRaw }
        let albumDescriptor = FetchDescriptor<Album>(predicate: albumPredicate)
        if let albums = try? modelContext.fetch(albumDescriptor) {
            for album in albums {
                modelContext.delete(album)
            }
        }

        try? modelContext.save()

        let orphanPredicate = #Predicate<Track> { $0.sourceTracks.isEmpty }
        let orphanDescriptor = FetchDescriptor<Track>(predicate: orphanPredicate)
        if let orphanedTracks = try? modelContext.fetch(orphanDescriptor) {
            for track in orphanedTracks {
                modelContext.delete(track)
            }
            try? modelContext.save()
        }
    }

    private var libraryView: some View {
        VStack(spacing: 0) {
            sourceFilterPicker
            LibraryTrackList(tracks: displayedTracks, version: displayedTracksVersion)
                .equatable()
        }
        .navigationDestination(for: Track.self) { track in
            TrackDetailView(track: track)
        }
        .environment(\.artworkLoadingEnabled, !syncService.isSyncing)
        .listStyle(.plain)
        .task(id: searchText) {
            try? await Task.sleep(for: .milliseconds(450))
            debouncedSearchText = searchText
        }
        .task(id: "filter-\(debouncedSearchText)-\(selectedSourceFilter.rawValue)-\(selectedSortOption.rawValue)-\(allTracks.count)") {
            displayedTracks = await computeDisplayedTracks()
            displayedTracksVersion += 1
        }
        .task {
            DebugLog.log("Library view: \(allTracks.count) tracks in DB, isSyncing=\(syncService.isSyncing)")
            if allTracks.isEmpty && !syncService.isSyncing {
                DebugLog.log("Library: empty, starting sync")
                await syncService.syncAll()
            }
        }
        .onChange(of: syncService.isSyncing) { _, isSyncing in
            if !isSyncing, syncService.firstErrorMessage == nil, syncService.lastSyncedAt != nil {
                syncedToastTask?.cancel()
                showSyncedToast = true
                syncedToastTask = Task {
                    defer { syncedToastTask = nil }
                    do {
                        try await Task.sleep(for: .seconds(3))
                        if !Task.isCancelled { showSyncedToast = false }
                    } catch {
                        // Cancelled – leave toast as-is until next sync
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var syncNotificationOverlay: some View {
        if showSyncedToast, let date = syncService.lastSyncedAt {
            syncBanner(text: "Synced at \(formattedSyncTime(date))", isProgress: false)
        } else if let error = syncService.firstErrorMessage {
            syncErrorBanner(message: error)
        }
    }

    private func syncBanner(text: String, isProgress: Bool) -> some View {
        HStack(spacing: 8) {
            if isProgress {
                ProgressView()
                    .scaleEffect(0.8)
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.top, 8)
        .padding(.horizontal, 16)
    }

    private func syncErrorBanner(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button("Retry") {
                Task { await syncService.syncAll(force: true) }
            }
            .font(.subheadline.bold())
            Button("Dismiss") {
                syncService.dismissErrors()
            }
            .font(.subheadline)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.top, 8)
        .padding(.horizontal, 16)
    }

    private func formattedSyncTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    @ToolbarContentBuilder
    private var songsToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                ForEach(LibrarySortOption.allCases, id: \.self) { option in
                    Button {
                        selectedSortOption = option
                    } label: {
                        Label(option.label, systemImage: option.systemImage)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down.circle")
                    .accessibilityLabel("Sort")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if syncService.isSyncing {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Syncing")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showConnectSheet = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if syncService.isSyncing {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Syncing")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showConnectSheet = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }

    private var sourceFilterPicker: some View {
        Picker("Source", selection: $selectedSourceFilter) {
            ForEach(LibrarySourceFilter.allCases, id: \.self) { filter in
                Text("\(filter.label) (\(count(for: filter).formatted(.number)))")
                    .tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

}

// MARK: - Library Track List (Equatable to avoid re-render on every keystroke)

struct LibraryTrackList: View, Equatable {
    let tracks: [Track]
    let version: Int

    @EnvironmentObject var syncService: SyncService

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.version == rhs.version
    }

    var body: some View {
        List {
            Section {
                ForEach(tracks) { track in
                    NavigationLink(value: track) {
                        TrackRowView(track: track)
                    }
                }
            } header: {
                Text("\(tracks.count) songs")
                    .textCase(nil)
            }
        }
        .listStyle(.plain)
    }
}

#Preview {
    let appleMusic = AppleMusicService()
    let auth = SpotifyAuthService(clientId: "preview")
    let spotifyAPI = SpotifyAPIService(authService: auth)
    ContentView()
        .environmentObject(appleMusic)
        .environmentObject(auth)
        .environmentObject(spotifyAPI)
        .environmentObject(SyncService(appleMusicService: appleMusic, spotifyAPIService: spotifyAPI, spotifyAuthService: auth))
        .modelContainer(for: [Track.self, SourceTrack.self, Playlist.self, PlaylistTrack.self, Album.self], inMemory: true)
}
