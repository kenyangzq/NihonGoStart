# MusicKit Setup Guide for NihonGoStart

This guide walks you through setting up Apple Music integration for the NihonGoStart app.

## Prerequisites

- Apple Developer Program enrollment ($99/year)
- Xcode 15+
- iOS 17.4+ device or simulator

## Step 1: Create an App in App Store Connect

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Sign in with your Apple Developer account
3. Navigate to **My Apps** → **+** → **New App**
4. Fill in the app details:
   - Platform: iOS
   - Name: NihonGoStart
   - Primary Language: English
   - Bundle ID: Select your app's bundle ID
   - SKU: Any unique identifier

**Note**: If you already have an app created, skip this step.

## Step 2: Create a MusicKit Key

1. Go to [Apple Developer - Keys](https://developer.apple.com/account/resources/keys/list)
2. Click **+** to create a new key
3. Configure the key:
   - **Key Name**: NihonGoStart MusicKit (or any descriptive name)
   - **Capabilities**: Check **MusicKit**
4. Click **Generate**
5. **IMPORTANT**: Download the `.p8` key file immediately
   - You can only download it once!
   - Save it securely (you'll need it for Step 4)

6. After downloading, note the following information:
   - **Key ID**: 10-character alphanumeric string (displayed on the keys page)
   - **Team ID**: 10-character alphanumeric string (visible in the upper-right corner of the developer portal)

## Step 3: Encode the Private Key

The `.p8` private key file needs to be base64 encoded for use in the app.

### Option 1: Using Terminal (macOS/Linux)

```bash
# Navigate to the directory where you saved the .p8 file
cd /path/to/your/keys

# Encode the private key
cat MusicKit.p8 | base64 | tr -d '\n'

# Copy the entire output (it will be a long string)
```

### Option 2: Using Online Tool

1. Open a base64 encoder tool (e.g., https://www.base64encode.org/)
2. Open your `.p8` file in a text editor
3. Copy the entire content (including the header and footer)
4. Paste into the encoder
5. Copy the encoded result

## Step 4: Add Credentials to Secrets.swift

Open `/NihonGoStart/Secrets.swift` and fill in the MusicKit credentials:

```swift
// Apple Music Kit (for Japanese music integration)
static let appleMusicTeamId = "YOUR_TEAM_ID"          // From Step 2
static let appleMusicKeyId = "YOUR_KEY_ID"            // From Step 2
static let appleMusicPrivateKey = "BASE64_ENCODED_KEY" // From Step 3
```

**Example**:
```swift
static let appleMusicTeamId = "ABC1234567"           // Your 10-character Team ID
static let appleMusicKeyId = "XYZ9876543"            // Your 10-character Key ID
static let appleMusicPrivateKey = "TUlTSUNLSVRQUklWQVRFIEtFWSLi..." // Long base64 string
```

## Step 5: Enable MusicKit Capability in Xcode

1. Open `NihonGoStart.xcodeproj` in Xcode
2. Select the **NihonGoStart** project in the project navigator
3. Select the **NihonGoStart** target
4. Go to the **Signing & Capabilities** tab
5. Click **+ Capability**
6. Search for and add **MusicKit**
7. The capability will be added to your app with the correct entitlements

## Step 6: Add KeychainManager.swift to Xcode Project

The `KeychainManager.swift` file has been created but needs to be added to your Xcode project:

1. In Xcode, right-click on the **Support** folder in the project navigator
2. Select **Add Files to "NihonGoStart"...**
3. Navigate to and select `KeychainManager.swift`
4. Ensure the **NihonGoStart** target is checked
5. Click **Add**

## Step 7: Build and Run

1. Select your target device or simulator (iOS 17.4+)
2. Build and run (Cmd+R)
3. Navigate to the **Songs** tab
4. You should see:
   - Catalog search working (no login required)
   - "Connect to Apple Music" button
   - Ability to play 30-second previews

## Testing Your Setup

### Test 1: Catalog Search (No Login Required)
1. Open the app and navigate to Songs tab
2. Search for a Japanese artist (e.g., "YOASOBI")
3. Verify search results appear
4. Tap play to hear a 30-second preview

### Test 2: User Authorization (Requires Apple ID)
1. Tap "Connect to Apple Music"
2. Sign in with your Apple ID
3. Authorize the app to access Apple Music
4. Verify status shows your subscription level

### Test 3: Full Track Playback (Requires Subscription)
1. If you have an Apple Music subscription:
2. Connect to Apple Music (Test 2)
3. Verify status shows "Apple Music Subscriber"
4. Play a track - should play the full song, not just preview
5. Look for the blue "+" button to add songs to your library

### Test 4: Library Access (Requires Subscription)
1. Connect to Apple Music
2. Find a song you like
3. Tap the blue "+" button
4. Verify "Added to Library" message appears
5. Open the Music app to confirm the song was added

## Troubleshooting

### "Setup Required" Message

**Problem**: App shows setup instructions instead of music search.

**Solution**:
- Verify `Secrets.swift` has all three MusicKit credentials
- Check that the private key is base64 encoded
- Ensure there are no typos in Team ID or Key ID

### "Authorization Failed" Alert

**Problem**: Cannot connect to Apple Music.

**Solutions**:
1. Check that MusicKit capability is enabled in Xcode
2. Verify your device/simulator is running iOS 17.4+
3. Check network connectivity
4. Ensure your app has the correct Bundle ID matching App Store Connect

### No Search Results

**Problem**: Search returns no songs.

**Solutions**:
1. Check network connectivity
2. Try searching for popular artists (e.g., "Ado", "YOASOBI")
3. Verify developer token is being generated (check console)
4. Ensure Apple Music API is accessible in your region

### Can't Play Full Tracks

**Problem**: Only previews play even with subscription.

**Solutions**:
1. Verify you have an active Apple Music subscription
2. Check that you're logged into Apple Music in the app
3. Verify status shows "Apple Music Subscriber"
4. Try logging out and back in

### Build Errors

**Problem**: Xcode shows build errors related to MusicKit.

**Solutions**:
1. Ensure deployment target is iOS 17.4 or higher
2. Clean build folder (Cmd+Shift+K)
3. Restart Xcode
4. Verify MusicKit framework is linked

## Security Best Practices

1. **Never commit Secrets.swift**: Add to `.gitignore`
2. **Protect .p8 file**: Delete after encoding
3. **Rotate keys periodically**: Create new keys every 6 months
4. **Use different keys per app**: Don't reuse keys across apps
5. **Monitor usage**: Check Apple Music API usage in App Store Connect

## Quick Reference

### MusicKit Credential Locations

| Credential | Where to Find | Format | Example |
|------------|---------------|--------|---------|
| Team ID | Apple Developer portal (top-right) | 10 chars | `ABC1234567` |
| Key ID | Keys page after creating MusicKit key | 10 chars | `XYZ9876543` |
| Private Key | Downloaded .p8 file (base64 encoded) | Long string | `TUlTSUNL...` |

### Important URLs

- **App Store Connect**: https://appstoreconnect.apple.com
- **Developer Portal**: https://developer.apple.com/account
- **Keys Management**: https://developer.apple.com/account/resources/keys/list
- **MusicKit Documentation**: https://developer.apple.com/documentation/musickit

### Support

If you encounter issues:
1. Check the Apple Developer Forums
2. Review MusicKit documentation
3. Verify all steps in this guide
4. Check Xcode console for error messages

## Next Steps

After setup is complete:
1. Test the full user flow
2. Add error handling for edge cases
3. Implement personalized recommendations
4. Add analytics to track usage
5. Consider adding Siri shortcuts for music playback
