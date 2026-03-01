import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import UIKit

private final class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthContextProvider()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if let key = windowScene.windows.first(where: \.isKeyWindow) { return key }
            if let first = windowScene.windows.first { return first }
        }
        return UIWindow()
    }
}

private let spotifyAuthBase = "https://accounts.spotify.com"
private let spotifyTokenURL = URL(string: "\(spotifyAuthBase)/api/token")!
private let keychainService = "com.danielvanacker.MusicSync.spotify"
private let accessTokenKey = "spotify_access_token"
private let refreshTokenKey = "spotify_refresh_token"
private let tokenExpiryKey = "spotify_token_expiry"

struct SpotifyTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
}

@MainActor
final class SpotifyAuthService: ObservableObject {
    @Published private(set) var isConnected = false
    @Published var errorMessage: String?

    private let clientId: String
    private let redirectURI: String
    private let scopes = ["user-library-read", "user-top-read", "playlist-read-private", "playlist-read-collaborative"]

    init(clientId: String? = nil, redirectURI: String = "musicsync://callback") {
        self.clientId = clientId
            ?? ProcessInfo.processInfo.environment["SPOTIFY_CLIENT_ID"]
            ?? (Bundle.main.object(forInfoDictionaryKey: "SPOTIFY_CLIENT_ID") as? String)
            ?? ""
        self.redirectURI = redirectURI
        if self.clientId.isEmpty {
            DebugLog.error("Spotify Client ID: EMPTY – set SPOTIFY_CLIENT_ID in Info.plist")
        } else {
            DebugLog.log("Spotify Client ID loaded: \(self.clientId.prefix(8))...")
        }
        loadConnectionState()
        DebugLog.log("Spotify init: isConnected=\(self.isConnected)")
    }

    private func loadConnectionState() {
        isConnected = (try? KeychainHelper.load(for: accessTokenKey, service: keychainService)) != nil
    }

    var hasValidClientId: Bool {
        !clientId.isEmpty
    }

    func connect() async {
        DebugLog.log("Spotify connect() called")
        guard hasValidClientId else {
            errorMessage = "Spotify Client ID not configured. See README for setup."
            DebugLog.error("Connect aborted: no Client ID")
            return
        }
        errorMessage = nil

        let (verifier, challenge) = makePKCEPair()
        let state = String.randomBase64(length: 16)
        let authURL = makeAuthorizeURL(codeChallenge: challenge, state: state)
        DebugLog.log("Opening Spotify auth URL...")

        let callbackURL: URL? = await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "musicsync"
            ) { url, error in
                if error != nil {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: url)
            }
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = WebAuthContextProvider.shared
            if !session.start() {
                continuation.resume(returning: nil)
            }
        }

        guard let url = callbackURL else {
            errorMessage = "Spotify sign-in was cancelled."
            DebugLog.log("Spotify sign-in cancelled (no callback URL)")
            return
        }

        DebugLog.log("Spotify callback received: \(url.absoluteString.prefix(80))...")
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value,
              returnedState == state
        else {
            errorMessage = "Invalid callback from Spotify."
            DebugLog.error("Invalid callback: missing code, wrong state, or malformed URL")
            return
        }

        DebugLog.log("Exchanging code for tokens...")
        do {
            let (tokens, grantedScopes) = try await exchangeCode(code, verifier: verifier)
            DebugLog.log("Spotify granted scopes: \(grantedScopes ?? "none")")
            try saveTokens(tokens)
            isConnected = true
            DebugLog.log("Spotify connected successfully")
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            DebugLog.error("Spotify token exchange failed: \(error.localizedDescription)")
        }
    }

    func disconnect() {
        DebugLog.log("Spotify disconnect()")
        try? KeychainHelper.delete(for: accessTokenKey, service: keychainService)
        try? KeychainHelper.delete(for: refreshTokenKey, service: keychainService)
        try? KeychainHelper.delete(for: tokenExpiryKey, service: keychainService)
        isConnected = false
        errorMessage = nil
    }

    func getAccessToken() async throws -> String {
        if let token = try? getValidAccessToken() {
            return token
        }
        if let refresh = try? KeychainHelper.load(for: refreshTokenKey, service: keychainService).utf8String,
           let tokens = try? await refreshTokens(refreshToken: refresh)
        {
            DebugLog.log("Spotify token refreshed")
            try saveTokens(tokens)
            return tokens.accessToken
        }
        DebugLog.error("Spotify getAccessToken: not authenticated, refresh failed")
        throw SpotifyAuthError.notAuthenticated
    }

    private func getValidAccessToken() throws -> String? {
        guard let data = try? KeychainHelper.load(for: accessTokenKey, service: keychainService),
              let token = data.utf8String
        else { return nil }
        let expiry = (try? KeychainHelper.load(for: tokenExpiryKey, service: keychainService))
            .flatMap { try? JSONDecoder().decode(Date.self, from: $0) }
        if let expiry, expiry > Date().addingTimeInterval(60) {
            return token
        }
        return nil
    }

    private func makePKCEPair() -> (verifier: String, challenge: String) {
        let verifier = String.randomBase64(length: 64)
        let challenge = Data(verifier.utf8).sha256Base64URL
        return (verifier, challenge)
    }

    private func makeAuthorizeURL(codeChallenge: String, state: String) -> URL {
        var comp = URLComponents(string: "\(spotifyAuthBase)/authorize")!
        comp.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "show_dialog", value: "true"),
        ]
        return comp.url!
    }

    private func exchangeCode(_ code: String, verifier: String) async throws -> (SpotifyTokens, String?) {
        var req = URLRequest(url: spotifyTokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientId,
            "code_verifier": verifier,
        ]
        .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
        .joined(separator: "&")
        .data(using: .utf8)

        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse else { throw SpotifyAuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let err = try? JSONDecoder().decode(SpotifyTokenError.self, from: data) {
                throw SpotifyAuthError.tokenError(err.error, err.errorDescription)
            }
            throw SpotifyAuthError.httpError(http.statusCode)
        }

        let body = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        let tokens = SpotifyTokens(
            accessToken: body.accessToken,
            refreshToken: body.refreshToken ?? "",
            expiresIn: body.expiresIn
        )
        return (tokens, body.scope)
    }

    private func refreshTokens(refreshToken: String) async throws -> SpotifyTokens {
        var req = URLRequest(url: spotifyTokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ]
        .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
        .joined(separator: "&")
        .data(using: .utf8)

        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SpotifyAuthError.notAuthenticated
        }

        let body = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        return SpotifyTokens(
            accessToken: body.accessToken,
            refreshToken: body.refreshToken ?? refreshToken,
            expiresIn: body.expiresIn
        )
    }

    private func saveTokens(_ tokens: SpotifyTokens) throws {
        try KeychainHelper.save(Data(tokens.accessToken.utf8), for: accessTokenKey, service: keychainService)
        try KeychainHelper.save(Data(tokens.refreshToken.utf8), for: refreshTokenKey, service: keychainService)
        let expiry = Date().addingTimeInterval(TimeInterval(tokens.expiresIn))
        try KeychainHelper.save(try JSONEncoder().encode(expiry), for: tokenExpiryKey, service: keychainService)
    }
}

private struct SpotifyTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
    }
}

private struct SpotifyTokenError: Codable {
    let error: String
    let errorDescription: String?
}

enum SpotifyAuthError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case tokenError(String, String?)
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not connected to Spotify."
        case .invalidResponse: return "Invalid response from Spotify."
        case .tokenError(let err, let desc): return desc ?? err
        case .httpError(let code): return "Spotify error (\(code))."
        }
    }
}

private extension String {
    static func randomBase64(length: Int) -> String {
        var data = Data(count: length)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, length, $0.baseAddress!) }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension Data {
    var sha256Base64URL: String {
        let hash = SHA256.hash(data: self)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    var utf8String: String? {
        String(data: self, encoding: .utf8)
    }
}
