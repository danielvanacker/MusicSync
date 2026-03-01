# MusicSync

Sync your music library from Apple Music and Spotify into one place.

## Spotify Setup

To use Spotify integration, you need to register an app in the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard).

### 1. Create an app

1. Go to [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard)
2. Log in with your Spotify account
3. Click **Create app** → fill in name and description → **Create**

### 2. Configure redirect URI

1. Open your app in the dashboard
2. Go to **Settings**
3. Under **Redirect URIs**, add:
   ```
   musicsync://callback
   ```
4. Click **Add** then **Save**

### 3. Get your Client ID

1. In the app settings, copy the **Client ID**
2. Create a local secrets config:
   ```bash
   cp MusicSync/Secrets.xcconfig.example MusicSync/Secrets.xcconfig
   ```
3. Edit `MusicSync/Secrets.xcconfig` and replace the placeholder with your Client ID:
   ```
   SPOTIFY_CLIENT_ID = your_spotify_client_id
   ```
4. `Secrets.xcconfig` is git-ignored — do not commit it when using a shared repo.

### 4. Scopes

The app requests:
- `user-library-read` – access to your saved tracks
- `user-top-read` – access to your top artists/tracks (for future use)

## Behaviour

See [docs/BEHAVIOUR.md](docs/BEHAVIOUR.md) for a summary of current behaviour (sync flow, deduplication, filters, metadata merge). Useful for agents and contributors who need to understand the app without parsing the codebase.

## Architecture

- **Track** / **SourceTrack** – SwiftData models for unified library
- **AppleMusicService** – MusicKit sync to SwiftData
- **SpotifyAuthService** – OAuth PKCE flow, token storage in Keychain
- **SpotifyAPIService** – Web API fetch of saved tracks, SwiftData persistence
