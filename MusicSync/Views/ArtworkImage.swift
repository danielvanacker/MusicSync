import SwiftUI
import UIKit

private struct ArtworkLoadingEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var artworkLoadingEnabled: Bool {
        get { self[ArtworkLoadingEnabledKey.self] }
        set { self[ArtworkLoadingEnabledKey.self] = newValue }
    }
}

private actor ArtworkImageLoader {
    static let shared = ArtworkImageLoader()

    /// Must use URLSession.shared – MusicKit registers its protocol handlers for musicKit:// URLs only on the shared session. A custom session fails with "unsupported URL".
    func load(from url: URL) async throws -> UIImage {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = UIImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }
        return image
    }
}

private let maxLoadAttempts = 4
/// Delays between retries (seconds). musicKit:// URLs often need extra time for identity/auth to resolve.
private let retryDelays: [UInt64] = [2, 5, 10]

struct ArtworkImage: View {
    let url: URL
    let size: CGFloat

    @Environment(\.artworkLoadingEnabled) private var artworkLoadingEnabled
    @Environment(\.scenePhase) private var scenePhase

    @State private var image: UIImage?
    @State private var loadAttempt = 0
    @State private var isFailed = false

    init(url: URL, size: CGFloat = 50) {
        self.url = url
        self.size = size
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: "\(url.absoluteString)-\(loadAttempt)") {
            guard artworkLoadingEnabled else { return }
            await loadImage()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, isFailed, loadAttempt < maxLoadAttempts {
                loadAttempt += 1
            }
        }
    }

    private func loadImage() async {
        do {
            let loaded = try await ArtworkImageLoader.shared.load(from: url)
            await MainActor.run {
                image = loaded
                isFailed = false
            }
        } catch {
            await MainActor.run {
                isFailed = true
            }
            if loadAttempt < maxLoadAttempts - 1 {
                let delay = loadAttempt < retryDelays.count ? retryDelays[loadAttempt] : retryDelays.last!
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                await MainActor.run {
                    loadAttempt += 1
                }
            }
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.gray.opacity(0.3))
            .overlay {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
            }
    }
}
