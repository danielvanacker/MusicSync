# MusicSync – Current Behaviour

This document summarizes how the app behaves today. Use it as a reference instead of parsing the codebase. Each section links to the relevant files.

---

## 1. Data Model

### Track

- **File:** `[MusicSync/Models/Track.swift](../MusicSync/Models/Track.swift)`
- Canonical track metadata: title, artist, album, duration, artwork, genres, ISRC, etc.
- One-to-many relationship to `SourceTrack`. A track can have multiple SourceTracks (e.g. same song in Apple Music and Spotify).
- **Unique constraint:** `#Unique<Track>([\.title, \.artistName, \.albumName])` – no two Tracks can share the same (title, artistName, albumName).

### SourceTrack

- **File:** `[MusicSync/Models/SourceTrack.swift](../MusicSync/Models/SourceTrack.swift)`
- Represents one track from one source (Apple Music or Spotify). Holds source-specific metadata: `playCount`, `lastPlayedDate`, `rating` (Apple Music); `popularity`, `previewURL` (Spotify).
- **Unique constraint:** `#Unique<SourceTrack>([\.sourceRawValue, \.sourceId])` – one SourceTrack per (source, sourceId).

### Playlist

- **File:** `[MusicSync/Models/Playlist.swift](../MusicSync/Models/Playlist.swift)`
- Playlist metadata: `sourceRawValue`, `sourceId`, `name`, `descriptionText`, `artworkURL`, `trackCount`, `ownerName`, `isPublic`, `lastSyncedAt`.
- One-to-many relationship to `PlaylistTrack` (cascade delete).
- **Unique constraint:** `#Unique<Playlist>([\.sourceRawValue, \.sourceId])` – one Playlist per (source, sourceId).

### PlaylistTrack

- **File:** `[MusicSync/Models/PlaylistTrack.swift](../MusicSync/Models/PlaylistTrack.swift)`
- Join model linking `Playlist` to `Track`. Holds `position`, `addedAt`, and relationships to both.

### Album

- **File:** `[MusicSync/Models/Album.swift](../MusicSync/Models/Album.swift)`
- Standalone album metadata: `sourceRawValue`, `sourceId`, `name`, `artistName`, `artworkURL`, `releaseDate`, `trackCount`, `genreNames`, `lastSyncedAt`.
- No direct relationship to `Track` (tracks store `albumName`; album detail view matches by string).
- **Unique constraint:** `#Unique<Album>([\.sourceRawValue, \.sourceId])` – one Album per (source, sourceId).

### Source

- **File:** `[MusicSync/Models/Source.swift](../MusicSync/Models/Source.swift)`
- Enum: `appleMusic` | `spotify`.

---

## 2. Sync Flow

### Orchestration

- **File:** `[MusicSync/Services/SyncService.swift](../MusicSync/Services/SyncService.swift)`
- Sync runs on a background thread via `Task.detached(priority: .userInitiated)`. Each service (Apple Music, Spotify) and dedup use a separate `ModelContext(container)` created in the detached task, so the main thread stays responsive.
- Two public entry points:
  - `syncAll(force:)` – syncs all connected sources sequentially (Apple Music first, then Spotify). With `force: false` (default), sources that completed within the last 5 minutes are skipped. With `force: true` (pull-to-refresh), all sources sync unconditionally.
  - `syncSource(_:)` – syncs a single source, always runs regardless of staleness. Used when connecting a new source (e.g. connecting Spotify only syncs Spotify).
- Syncs run sequentially; errors in one source do not block the other. All sync calls are queued to prevent concurrent execution.
- **Per-source order:** For each source, sync runs: tracks → playlists → albums (playlists depend on tracks for linking).
- **Post-sync dedup:** After sync completes, `runDedup(context:)` runs. Merge count is logged.
- **`lastSyncedAt`:** Set when a sync run (all sources + dedup) completes. Used for the "Synced at X" notification.
- **`dismissErrors()`:** Clears error state for all sources when the user dismisses the error banner.
- Triggers: pull-to-refresh (`force: true`), Connect Spotify (`syncSource(.spotify)`), auto-sync when library is empty, error retry.

### Apple Music Sync

- **File:** `[MusicSync/Services/AppleMusicService.swift](../MusicSync/Services/AppleMusicService.swift)`
- **Tracks:** Fetches via `MusicLibraryRequest<Song>` (MusicKit), paginated. For each song: looks up existing `SourceTrack` by Apple Music `sourceId`. If found → updates Track + SourceTrack. If not found → creates new Track + SourceTrack, links them, inserts both.
- **Playlists:** Fetches via `MusicLibraryRequest<MusicKit.Playlist>`. For each playlist, loads tracks via `.with([.tracks])`. Links to existing Track records by Apple Music `sourceId`; creates new Track + SourceTrack for unmatched playlist tracks.
- **Albums:** Fetches via `MusicLibraryRequest<MusicKit.Album>`. Maps to `Album` model and upserts.

### Spotify Sync

- **File:** `[MusicSync/Services/SpotifyAPIService.swift](../MusicSync/Services/SpotifyAPIService.swift)`
- **Tracks:** Fetches `/me/tracks` (paginated).
- **Early-exit optimisation:** On the first page, if the API `total` matches the number of existing Spotify SourceTracks in the DB, the sync exits immediately (no tracks added or removed).
- For each saved track: looks up existing `SourceTrack` by Spotify `sourceId`.
  - If found → updates SourceTrack and Track (using `updateTrackPreservingExistingMetadata`).
  - If not found → checks for existing `Track` by (title, artistName, albumName). If found → creates only SourceTrack and links; updates Track with preserving merge. If not found → creates new Track + SourceTrack.
- **Playlists:** Fetches `GET /me/playlists` (paginated), then `GET /playlists/{id}/tracks` per playlist. Links to existing Track records by Spotify `sourceId`; creates new Track + SourceTrack for unmatched playlist tracks. Requires `playlist-read-private` scope.
- **Albums:** Fetches `GET /me/albums` (paginated). Maps to `Album` model and upserts.

### Sync Order and Merging

- Apple Music always syncs first. Spotify syncs second.
- **No pruning:** Sync only adds and updates. Items removed from the user's library (tracks, playlists, albums) are not deleted locally. The only removal during sync is: (1) playlist track re-ordering (playlist tracks are replaced on re-sync per playlist), (2) dedup of duplicate tracks.
- **Title/artist/album matching:** Spotify looks up existing Track by (title, artistName, albumName) before creating. If found, it attaches a new SourceTrack instead of creating a duplicate Track. Uses `updateTrackPreservingExistingMetadata` so Apple Music genres, composer, and artwork are not overwritten.
- **ISRC dedup:** After sync, `runDedup` merges Tracks with the same ISRC across sources.
- **Implicit merging (legacy):** `Track` also has `#Unique` on (title, artistName, albumName). If SwiftData ever upserts, the Spotify path above avoids metadata degradation.

### Post-Sync Dedup (ISRC-Based)

- **File:** `[MusicSync/Services/DedupService.swift](../MusicSync/Services/DedupService.swift)`
- After Apple Music and Spotify sync complete, `runDedup(context:)` runs.
- Groups Tracks by ISRC (case-insensitive, trimmed). Skips tracks with no ISRC.
- For each group with 2+ Tracks: picks survivor (prefer Track with Apple Music source), re-points all SourceTracks from orphans to survivor, applies canonical metadata, deletes orphans.
- **Canonical metadata:** Prefer Apple Music artwork; take earliest `addedAt`; merge `genreNames` (union); preserve non-nil `albumArtistName`, `composerName`, `releaseDate`.
- Logs merge count when > 0 (e.g. "Dedup: merged 5 duplicate track(s) by ISRC").

---

## 3. Metadata Merge Behaviour

When a track exists in both services:

- **Spotify attaching to existing Track:** Before creating a new Track, Spotify checks for an existing one by (title, artistName, albumName). If found, it only creates a SourceTrack and links it. `updateTrackPreservingExistingMetadata` preserves genres and composer (never overwrites with empty); prefers Apple Music artwork when the Track has an Apple Music source; updates `addedAt` only if Spotify's is earlier.
- **ISRC dedup:** When `runDedup` merges Tracks by ISRC, canonical metadata is applied (see Post-Sync Dedup above).

---

## 4. Library View

### Source

- **File:** `[MusicSync/ContentView.swift](../MusicSync/ContentView.swift)`

### Tab Structure

- **Songs** – Track library with source filter, sort, and search (original `libraryView`).
- **Playlists** – List of playlists with source filter and search. Detail view shows ordered track list.
- **Albums** – List of albums with source filter and search. Detail view shows tracks matching album name + artist (from Track records).

### Sync UX (Background + Notification)

- Sync runs in the background. The library (filter picker + track list) stays visible at all times; there is no full-screen takeover.
- **Sync buttons:** In Settings (Music Sources sheet), each connected source has a "Sync" button. Tap to sync Apple Music only or Spotify only.
- **Notification overlay:** A small banner at the top of the library shows:
  - *While syncing:* "Syncing..." with a spinner.
  - *When done:* "Synced at [time]" (e.g. "just now" or "2:34 PM"). Auto-dismisses after ~3 seconds.
  - *On error:* Error message with Retry and Dismiss. Retry runs `syncAll(force: true)`; Dismiss calls `syncService.dismissErrors()`.

### Filters

- **All** – all Tracks (`allTracks.count`).
- **Apple Music** – Tracks that have at least one SourceTrack with `source == .appleMusic`.
- **Spotify** – Tracks that have at least one SourceTrack with `source == .spotify`.
- **Both** – Tracks that have SourceTracks from both sources.

Counts are based on Track rows (unique tracks), not SourceTrack rows.

### Sort Options

- Recently added, Title, Artist, Album, Play count.
- Play count comes from the Apple Music `SourceTrack`; Spotify doesn’t provide it.

### Search

- Debounced (~450ms). Filters by title, artist, album (case-insensitive substring).

### Data Flow

- `@Query(sort: \Track.addedAt, order: .reverse) private var allTracks`
- `sourceFilteredTracks` applies the selected source filter.
- `computeDisplayedTracks()` applies search and sort in a detached task.
- `LibraryTrackList` renders the list with a “X songs” header.

---

## 5. Track Row

### Source

- **File:** `[MusicSync/Views/TrackRowView.swift](../MusicSync/Views/TrackRowView.swift)`

### Behaviour

- Shows artwork (or placeholder), title, artist.
- **Source badges:** One icon per `SourceTrack` (Apple Music icon, Spotify icon). Tracks in both services show both icons.

---

## 6. Track Detail View

### Source

- **File:** `[MusicSync/Views/TrackDetailView.swift](../MusicSync/Views/TrackDetailView.swift)`

### Sections

1. **Header** – Artwork, title, artist, album (from Track).
2. **Source badges** – One badge per SourceTrack (e.g. “Apple Music”, “Spotify”).
3. **Track Info** – Duration, disc, track, genre, release date, explicit, ISRC, composer (from Track).
4. **Apple Music** – Only if there is an Apple Music SourceTrack: play count, last played, rating, added date.
5. **Spotify** – Only if there is a Spotify SourceTrack: popularity, added date, 30s preview player.
6. **Sync Info** – Last synced time.

Per-source sections show metadata from the corresponding `SourceTrack`.

---

## 7. Playlist and Album Views

### PlaylistListView / PlaylistDetailView

- **Files:** `[PlaylistListView.swift](../MusicSync/Views/PlaylistListView.swift)`, `[PlaylistDetailView.swift](../MusicSync/Views/PlaylistDetailView.swift)`
- List view: artwork, name, track count, owner, source badge. Source filter (All / Apple Music / Spotify). Search.
- Detail view: header (artwork, name, owner, track count, source badge), ordered track list (via `PlaylistTrack`), navigation to `TrackDetailView`.

### AlbumListView / AlbumDetailView

- **Files:** `[AlbumListView.swift](../MusicSync/Views/AlbumListView.swift)`, `[AlbumDetailView.swift](../MusicSync/Views/AlbumDetailView.swift)`
- List view: artwork, name, artist, release date, source badge. Source filter (All / Apple Music / Spotify). Search.
- Detail view: header (artwork, name, artist, release date, track count, source badge), genres, track list (filtered from Track by `albumName` + `artistName`), navigation to `TrackDetailView`.

---

## 8. Connect / Settings

### Source

- **File:** `[MusicSync/ContentView.swift](../MusicSync/ContentView.swift)` – `connectSheetContent`, `connectSourcesView`, `disconnectSource`, `deleteRecords`.

### Behaviour

- Apple Music: system auth; disconnect opens Settings (data is deleted in-app).
- Spotify: OAuth PKCE (`[SpotifyAuthService.swift](../MusicSync/Services/SpotifyAuthService.swift)`); disconnect deletes tokens locally, removes data, and opens spotify.com/account/apps for the user to revoke. Client ID is read from Info.plist (falls back to env var for development).
- `deleteRecords(for:)` deletes all SourceTracks, Playlists, and Albums for that source (Playlist cascade-deletes PlaylistTracks), then deletes Tracks with no remaining SourceTracks.
