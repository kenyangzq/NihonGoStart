# Apple MusicKit Integration - Implementation Summary

## Overview
Successfully implemented Apple MusicKit integration to replace Spotify in the NihonGoStart app.

## Files Created

### 1. `/NihonGoStart/Managers/MusicManager.swift`
- **Purpose**: Core Apple Music integration manager
- **Key Features**:
  - JWT token generation for Apple Music API authentication
  - Catalog search across Japanese and US storefronts
  - Preview playback using AVPlayer
  - Synchronized lyrics fetching with TTML parsing
  - Storefront selection (Japan 🇯🇵 / US 🇺🇸)

- **Main Components**:
  - `MusicJWTGenerator`: Generates developer tokens using ES256 signing
  - `MusicManager`: Singleton manager for all Apple Music operations
  - API calls: Search catalog, fetch lyrics, get track details
  - Playback controls: Play, pause, stop, toggle
  - Storefront management: User preference for JP/US stores

### 2. `/APPLE_MUSIC_SETUP.md`
- **Purpose**: Comprehensive setup guide for developers
- **Contents**:
  - Prerequisites (Apple Developer Program)
  - Step-by-step MusicKit key creation
  - Base64 encoding instructions for private key
  - Configuration steps for Secrets.swift
  - Testing procedures and troubleshooting
  - Future enhancement roadmap

## Files Modified

### 1. `/NihonGoStart/Secrets.swift`
**Changes**:
- Added Apple MusicKit credentials placeholders:
  - `appleMusicTeamId`: 10-character Team ID from Apple Developer account
  - `appleMusicKeyId`: 10-character Key ID from MusicKit key
  - `appleMusicPrivateKey`: Base64-encoded .p8 private key content
- Marked Spotify credentials as deprecated

### 2. `/NihonGoStart/Models/DataModels.swift`
**Changes**:
- Added Apple Music data models:
  - `AppleMusicTrack`: Track information with catalog ID, artwork, duration
  - `AppleMusicLyric`: Synchronized lyric with timestamps
  - `AppleMusicAlbum`: Album information
- Kept Spotify models for backward compatibility

### 3. `/NihonGoStart/Views/Songs/SongsView.swift`
**Complete rewrite** to use Apple Music:
- Changed color scheme from green (Spotify) to red (Apple Music)
- Added `StorefrontPickerBar`: Toggle between Japan/US storefronts
- Updated search to use `MusicManager`
- Modified `SongRowView`: Display track duration
- Updated `LyricsView`: Fetch from Apple Music API with TTML parsing
- Removed user login/profile features (not needed for Apple Music catalog search)
- Changed all references from `SpotifyTrack` to `AppleMusicTrack`

### 4. `/NihonGoStart/Managers/SpotifyManager.swift`
**Changes**:
- Fixed `override` keyword on `init()` method to resolve compilation error
- File kept for backward compatibility but no longer used in main UI

## Key Implementation Details

### JWT Token Generation
```swift
class MusicJWTGenerator {
    - Uses ES256 algorithm with P256.Signing.PrivateKey
    - Creates tokens valid for 6 months
    - Includes: Team ID, Key ID, issued/expired timestamps
    - Base64URL encoding for header, payload, and signature
}
```

### Catalog Search
```swift
func searchJapaneseSongs(query: String) async
- Searches both Japan (jp) and US (us) storefronts
- Deduplicates results by track ID
- Returns up to 20 tracks from each storefront
- Parses artwork URL templates (replaces {w} and {h} placeholders)
```

### Lyrics Fetching
```swift
func fetchLyrics(for track: AppleMusicTrack) async
- Calls Apple Music lyrics endpoint
- Parses TTML (Timed Text Markup Language) format
- Extracts synchronized lyrics with start/end times
- Falls back to manual input if not available
```

### Playback
```swift
func playTrack(_ track: AppleMusicTrack)
- Uses AVPlayer for preview playback
- Currently plays 30-second previews
- Full playback requires MusicKit subscription (future enhancement)
- Automatically fetches lyrics when playing
```

## Architecture Changes

### Before (Spotify)
```
SpotifyManager → SongsView
├── User authentication (OAuth with PKCE)
├── Catalog search (Spotify Web API)
├── Preview playback (previewURL)
├── Full playback (requires Spotify Premium)
└── No lyrics API
```

### After (Apple Music)
```
MusicManager → SongsView
├── JWT token generation (no user auth needed)
├── Catalog search (Apple Music API)
├── Preview playback (AVPlayer)
├── Lyrics fetching (TTML format)
├── Storefront selection (JP/US)
└── Full playback (future - requires MusicKit framework)
```

## Feature Comparison

| Feature | Spotify | Apple Music |
|---------|---------|-------------|
| Catalog Search | ✅ | ✅ |
| Preview Playback | ✅ 30s | ✅ 30s |
| Full Playback | ✅ (Premium) | 🔜 (Future) |
| Lyrics | ❌ | ✅ (Synced) |
| User Authentication | Required | Not needed |
| Storefront Selection | No | ✅ (JP/US) |
| Japanese Content | Good | Better |

## Setup Requirements

### Developer Requirements
1. Apple Developer Program membership ($99/year)
2. MusicKit Key created in Apple Developer portal
3. Base64-encoded private key (.p8 file)

### User Requirements (Current)
- None! Preview playback works without subscription

### User Requirements (Future - Full Playback)
- Active Apple Music subscription
- MusicKit framework integration
- User authorization via MusicUserToken

## Testing Recommendations

### Test Searches
```swift
// Popular J-Pop artists
"YOASOBI"     // 夜よ駆けろ, ミスター
"Ado"         // うっせぇわ, 新時代
"King Gnu"    // 白日, 三文小説
"米津玄師"     // Lemon, ピーナッツバター
"Aimyon"      // マリーゴールド, 愛を伝えたいだとか
```

### Expected Behavior
1. App authenticates with Apple Music API on launch
2. Search bar becomes available with JP/US storefront toggle
3. Searching returns results with album artwork
4. Play button plays 30-second preview
5. Lyrics button shows synchronized lyrics if available
6. "Open in Apple Music" launches the Music app

## Known Limitations

### Current Implementation
1. **Preview Only**: 30-second previews only
   - Full playback requires implementing MusicKit framework
   - Requires user Apple Music subscription

2. **Lyrics Availability**: Not all tracks have lyrics
   - Japanese lyrics limited for international tracks
   - Manual input available as fallback

3. **API Rate Limits**: Apple Music API has usage limits
   - Need to implement caching
   - Respect rate limits

### Future Enhancements
1. Full track playback with MusicKit framework
2. User authorization for personalized recommendations
3. Recently played/history
4. Playlist creation
5. Offline caching with MusicKit subscription
6. Apple Music Sing (karaoke) features

## Security Notes

1. **Secrets.swift**: Never commit to git (already in .gitignore)
2. **Private Key**: Keep .p8 file secure; rotate if compromised
3. **JWT Tokens**: Developer tokens valid for 6 months
4. **API Keys**: Can be revoked from Apple Developer portal

## Migration Notes

### For Users
- No data migration needed (search is real-time)
- UI remains similar with improved features
- Better Japanese music availability in Apple Music catalog

### For Developers
- SpotifyManager kept but deprecated
- Can be removed completely after validation period
- Data models support both for transition

## Build Status

✅ **Build succeeds** with only minor warnings:
- Sendable warnings (non-blocking)
- Unused variable warnings (fixed)

## Documentation

- Setup Guide: `/APPLE_MUSIC_SETUP.md`
- Implementation: `/NihonGoStart/Managers/MusicManager.swift`
- Data Models: `/NihonGoStart/Models/DataModels.swift`
- UI: `/NihonGoStart/Views/Songs/SongsView.swift`

## Next Steps for Full Implementation

1. ✅ Basic catalog search - DONE
2. ✅ Preview playback - DONE
3. ✅ Lyrics fetching - DONE
4. 🔲 Full MusicKit framework integration
5. 🔲 User subscription handling
6. 🔲 Full track playback
7. 🔲 Personalized recommendations
8. 🔲 Playlist management

---

**Implementation Date**: 2026-02-11
**Version**: 1.0
**Status**: Preview implementation complete
