import SwiftUI
import MusicKit

struct ContentView: View {
    @EnvironmentObject var musicService: MusicService

    var body: some View {
        NavigationStack {
            Group {
                switch musicService.authorizationStatus {
                case .notDetermined:
                    welcomeView
                case .authorized:
                    songListView
                case .denied, .restricted:
                    deniedView
                @unknown default:
                    welcomeView
                }
            }
            .navigationTitle("My Library")
        }
        .onAppear {
            musicService.checkAuthorizationStatus()
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

            Text("View all the songs saved in your Apple Music library.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                Task {
                    await musicService.requestAuthorization()
                }
            } label: {
                Text("Connect Apple Music")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.tint)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }

    private var songListView: some View {
        Group {
            if musicService.isLoading && musicService.songs.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading your library...")
                        .foregroundStyle(.secondary)
                }
            } else if let error = musicService.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                    Text("Something went wrong")
                        .font(.headline)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Button("Try Again") {
                        Task { await musicService.fetchLibrarySongs() }
                    }
                }
            } else {
                List {
                    Section {
                        ForEach(musicService.songs, id: \.id) { song in
                            SongRowView(song: song)
                        }
                    } header: {
                        Text("\(musicService.songCount) songs")
                            .textCase(nil)
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await musicService.fetchLibrarySongs()
                }
            }
        }
        .task {
            if musicService.songs.isEmpty && !musicService.isLoading {
                await musicService.fetchLibrarySongs()
            }
        }
    }

    private var deniedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Access Denied")
                .font(.title2.bold())

            Text("MusicSync needs access to your Apple Music library. You can enable this in Settings.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.tint)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(MusicService())
}
