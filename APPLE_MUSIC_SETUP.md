# Apple MusicKit Integration Setup Guide

This guide explains how to set up Apple MusicKit for the NihonGoStart app to enable Japanese song search, playback, and lyrics features.

## Overview

The app has been migrated from Spotify to Apple MusicKit for better integration with iOS and improved Japanese music support.

## Prerequisites

1. **Apple Developer Program Membership** ($99/year)
   - Required to create MusicKit keys and access Apple Music API
   - Sign up at: https://developer.apple.com/programs/

## Step-by-Step Setup

### 1. Enroll in Apple Developer Program

If you haven't already:
1. Go to https://developer.apple.com/programs/
2. Enroll in the Apple Developer Program
3. Wait for enrollment to process (usually 24-48 hours)

### 2. Create an App in App Store Connect

1. Go to https://appstoreconnect.apple.com
2. Click "My Apps"
3. Click the "+" button and select "New App"
4. Fill in the app details:
   - Platform: iOS
   - Name: NihonGoStart
   - Primary Language: English
   - Bundle ID: Use your app's bundle ID (e.g., com.yourname.NihonGoStart)
   - SKU: NihonGoStart-001
5. Click "Create"

### 3. Create a MusicKit Key

1. Go to https://developer.apple.com/account/resources/identifiers/list
2. Click "Keys" in the left sidebar
3. Click the "+" button to create a new key
4. Fill in the form:
   - Key Name: "NihonGoStart MusicKit" (or any descriptive name)
   - Check the "MusicKit" checkbox under Capabilities
5. Click "Generate"
6. **IMPORTANT**: Download the .p8 private key file immediately
   - You can only download it once!
   - Save it as `MusicKit.p8` in a secure location

### 4. Extract Credentials from Your Key File

After downloading the .p8 file, you need three pieces of information:

#### Team ID
- Found in the downloaded .p8 filename
- Format: `AuthKey_<KEY_ID>.p8`
- Or go to https://developer.apple.com/account and look under "Membership Details"

#### Key ID
- Found in the downloaded .p8 filename
- Format: `AuthKey_<KEY_ID>.p8`
- The Key ID is the 10-character alphanumeric string

#### Private Key
- The content of the .p8 file (excluding header and footer)
- Must be base64 encoded

### 5. Base64 Encode Your Private Key

Open Terminal and run:

```bash
# Navigate to the folder where you saved your .p8 file
cd /path/to/your/key/folder

# Base64 encode the private key
cat MusicKit.p8 | base64 | tr -d '\n'
```

Copy the entire output - this is your base64-encoded private key.

### 6. Update Secrets.swift

Open `/NihonGoStart/Secrets.swift` and fill in your credentials:

```swift
// Apple Music Kit (for Japanese music integration)
static let appleMusicTeamId = "YOUR_TEAM_ID"  // 10-character Team ID
static let appleMusicKeyId = "YOUR_KEY_ID"    // 10-character Key ID
static let appleMusicPrivateKey = "BASE64_ENCODED_PRIVATE_KEY"  // From step 5
```

Example:
```swift
static let appleMusicTeamId = "ABCD123456"
static let appleMusicKeyId = "XYZ1234567"
static let appleMusicPrivateKey = "MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQg..."
```

### 7. Configure Xcode Project

1. Open `NihonGoStart.xcodeproj` in Xcode
2. Select your app target
3. Go to "Signing & Capabilities"
4. Ensure your Team is selected
5. Enable "MusicKit" capability if available (for future full integration)

### 8. Build and Run

1. Clean the build folder (Cmd+Shift+K)
2. Build and run (Cmd+R)
3. Navigate to the "Songs" tab
4. You should see "Connecting to Apple Music..." then be able to search for Japanese songs

## Features

### Current Implementation (v1.0)

1. **Catalog Search**
   - Search Apple Music catalog for Japanese songs
   - Search across both Japan and US stores for better coverage
   - Toggle between Japan (🇯🇵) and US (🇺🇸) storefronts

2. **Preview Playback**
   - Play 30-second previews using AVPlayer
   - Full playback requires Apple Music subscription (future enhancement)

3. **Lyrics Display**
   - Fetch synchronized lyrics from Apple Music API
   - TTML format parsing for time-synced lyrics
   - Manual lyrics input as fallback

4. **Open in Apple Music**
   - Direct link to open tracks in the Apple Music app

### Limitations

1. **Preview Only**: Currently plays 30-second previews
   - Full track playback requires implementing the full MusicKit framework
   - This requires users to have an active Apple Music subscription

2. **Lyrics Availability**: Not all tracks have synchronized lyrics available
   - Japanese lyrics may be limited for some international tracks
   - Manual lyrics input is available as fallback

3. **API Rate Limits**: Apple Music API has rate limits
   - Implement caching for frequently accessed tracks
   - Respect rate limits to avoid temporary blocking

## Testing

### Test Queries

Try searching for these popular Japanese artists:
- YOASOBI (夜よ駆けろ / ミスター)
- Ado (うっせぇわ / 新時代)
- Official髭男dism (Pretender / Crier)
- King Gnu (白日 / 三文小説)
- 米津玄師 (Lemon / ピーナッツバター)
- Aimyon (マリーゴールド / 愛を伝えたいだとか)

### Expected Behavior

1. App shows "Connecting to Apple Music..." briefly
2. Search bar becomes available
3. Searching returns Japanese songs with album art
4. Play button plays 30-second preview
5. Lyrics button opens lyrics view
6. Open in Apple Music launches the Music app

## Troubleshooting

### "Apple Music not configured" Error

**Cause**: Credentials are empty or invalid in Secrets.swift

**Solution**:
1. Verify all three fields are filled in Secrets.swift
2. Check that Team ID and Key ID are exactly 10 characters
3. Ensure private key is base64 encoded correctly
4. Try regenerating the key if issues persist

### "No songs found" Error

**Cause**: Search query or storefront issue

**Solution**:
1. Try different search terms
2. Switch between Japan and US storefronts
3. Check network connection
4. Verify API key has MusicKit permissions

### Preview Not Playing

**Cause**: Preview URL unavailable or network issue

**Solution**:
1. Check if track has preview URL (some tracks don't)
2. Verify network connection
3. Try a different track
4. Use "Open in Apple Music" to play full track

### Lyrics Not Loading

**Cause**: Lyrics not available for track

**Solution**:
1. Try a different track
2. Use manual lyrics input feature
3. Search for lyrics online and paste them

## Future Enhancements

To implement full track playback (requires Apple Music subscription):

1. Add MusicKit framework to Xcode project
2. Implement `MusicUserToken` for user authorization
3. Use `MusicPlayer` from MusicKit for full playback
4. Add subscription status checking
5. Implement offline caching for subscribed users

See Apple's MusicKit documentation:
https://developer.apple.com/documentation/musickit

## Security Notes

1. **Never commit Secrets.swift to git**
   - The file is already in .gitignore
   - Keep your private key secure
   - Rotate keys if compromised

2. **Key Rotation**
   - You can revoke and generate new keys from Apple Developer portal
   - Update Secrets.swift with new credentials
   - Old keys stop working immediately after revocation

3. **Rate Limiting**
   - Implement request throttling
   - Cache search results
   - Handle rate limit errors gracefully

## Migration from Spotify

If you previously used Spotify integration:
1. SpotifyManager.swift is still available but deprecated
2. All UI has been updated to use MusicManager
3. Data models support both for backward compatibility
4. No user data migration needed (search is real-time)

## Support

For issues with:
- **Apple Developer Program**: Contact Apple Developer Support
- **MusicKit API**: Check Apple Music API documentation
- **App Integration**: Check GitHub issues or create a new one

## Resources

- [Apple Music API Documentation](https://developer.apple.com/documentation/applemusicapi)
- [MusicKit Framework](https://developer.apple.com/musickit/)
- [Creating a MusicKit Key](https://help.apple.com/developer-account/)
- [JWT Token Generation for Apple Music](https://developer.apple.com/documentation/applemusicapi/generating_tokens_for_musickit_requests)

---

**Last Updated**: 2026-02-11
**Version**: 1.0
