# Spotify OAuth 2.0 Setup Guide

This guide explains how to configure Spotify OAuth 2.0 authentication with PKCE for the NihonGoStart app.

## Overview

The app now supports two types of Spotify authentication:
1. **Client Credentials Flow** (existing) - App-level access for basic search and 30s previews
2. **Authorization Code Flow with PKCE** (new) - User login for full track access and personalization

## Spotify Dashboard Setup

### 1. Configure Redirect URI

1. Go to [Spotify Developer Dashboard](https://developer.spotify.com/dashboard)
2. Select your app (or create one if needed)
3. Go to **Redirect URIs** section
4. Add the following URI:
   ```
   nihongostart://callback
   ```
5. Click **Save**

### 2. Verify Scopes

Ensure your app has the following scopes enabled:
- `user-read-private` - Read user's profile information
- `user-read-email` - Read user's email address
- `user-library-read` - Read user's saved tracks
- `user-top-read` - Read user's top tracks and artists

## Xcode Project Configuration

### Add URL Scheme to Info.plist

Since iOS 14, URL schemes are configured in Xcode's target settings:

1. Open `NihonGoStart.xcodeproj` in Xcode
2. Select the **NihonGoStart** target (main app, not widget)
3. Go to the **Info** tab
4. Expand **URL Types** section
5. Click **+** to add a new URL type
6. Configure as follows:
   - **Identifier**: `com.ziqiyang.nihongostart.spotify`
   - **URL Schemes**: `nihongostart`
   - **Role**: Editor

### Alternative: Add to Info.plist directly

If your project uses a physical `Info.plist` file, add:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.ziqiyang.nihongostart.spotify</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>nihongostart</string>
        </array>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
    </dict>
</array>
```

### Add Spotify URL Scheme (for opening tracks)

To properly open tracks in the Spotify app, you need to declare the Spotify URL scheme:

1. In the **Info** tab of your target
2. Expand **URL Types** section
3. Add another URL type:
   - **Identifier**: `com.spotify.client`
   - **URL Schemes**: `spotify`
   - **Role**: None

## Architecture

### Authentication Flow

```
User taps "Login with Spotify"
    ↓
App generates code_verifier and code_challenge (PKCE)
    ↓
App opens Spotify authorization page in Safari
    ↓
User logs in and grants permissions
    ↓
Spotify redirects to: nihongostart://callback?code=...
    ↓
App receives callback and extracts authorization code
    ↓
App exchanges code + code_verifier for access_token
    ↓
App fetches user profile and stores tokens in UserDefaults
```

### Token Storage

Tokens are stored securely in UserDefaults (non-sensitive data):
- `spotify_user_access_token` - User's access token (1 hour expiry)
- `spotify_user_refresh_token` - Refresh token (long-lived)
- `spotify_token_expiration` - Token expiration timestamp
- `spotify_user_profile` - User profile (JSON encoded)

### Token Refresh

When the app launches:
1. Load saved tokens from UserDefaults
2. Check if token is expired
3. If expired, use refresh token to get new access token
4. If refresh fails, user must login again

## New Features

### User Profile

When logged in, users see:
- Display name
- Profile picture
- Account type (Free/Premium)
- Logout button

### Enhanced Search

- When logged in, search uses user's access token for personalized results
- When logged out, falls back to app-level token for basic search

### Full Track Support

- Users can now open full tracks in the Spotify app
- Works even with free accounts (opens in Spotify app)
- Preview playback still available for 30s clips

## Code Structure

### SpotifyManager Updates

**New Properties:**
```swift
@Published var userAccessToken: String?
@Published var userRefreshToken: String?
@Published var userProfile: SpotifyUserProfile?
@Published var isLoggedIn: Bool
```

**New Methods:**
```swift
func login()                              // Start OAuth flow
func logout()                             // Clear user session
func refreshUserAccessToken() async       // Refresh expired token
func getUserProfile() async               // Fetch user data
func exchangeCodeForToken(code: String)   // Handle OAuth callback
```

**PKCE Helpers:**
```swift
private func generateCodeVerifier() -> String
private func generateCodeChallenge(verifier: String) -> String
```

### Data Models

**New in DataModels.swift:**
```swift
struct SpotifyUserProfile: Codable
struct SpotifyImage: Codable
```

### SongsView Updates

**New UI Components:**
- `UserProfileBar` - Shows user profile and logout button
- Updated welcome screen with "Login with Spotify" button
- Shows user profile when logged in

## Testing

### Manual Testing

1. **Login Flow:**
   - Launch app
   - Go to Songs tab
   - Tap "Login with Spotify"
   - Complete Spotify authorization
   - Verify profile appears at top

2. **Token Persistence:**
   - Login successfully
   - Kill app (force close)
   - Relaunch app
   - Verify user is still logged in

3. **Logout:**
   - Tap logout button
   - Verify profile disappears
   - Verify login screen appears

4. **Search:**
   - Search for Japanese music
   - Verify results appear
   - Try opening in Spotify app

### Debugging

Enable OAuth logging by checking console for:
- "Authentication failed: ..." - OAuth flow errors
- "Token exchange failed: ..." - Token exchange errors
- "Token refresh failed: ..." - Refresh token errors

## Security Considerations

### PKCE Benefits

- Prevents authorization code interception attacks
- No client secret required in app (mobile-safe)
- Code verifier ensures the same app that requested auth is redeeming it

### Token Storage

**Why UserDefaults is OK:**
- Access tokens are short-lived (1 hour)
- Refresh tokens are specific to this app instance
- No sensitive data (passwords) is stored

**Future Improvements:**
- Use Keychain for better security
- Add token encryption
- Implement biometric lock

## Troubleshooting

### "Invalid redirect URI"

- Ensure `nihongostart://callback` is added in Spotify Dashboard
- Check URL scheme is configured in Xcode target settings
- Clean build folder (Cmd+Shift+K)

### "Authentication failed"

- Check network connectivity
- Verify Client ID in Secrets.swift
- Check Spotify app status (should be "Development" or "Production")

### Token not persisting

- Check UserDefaults is being saved
- Verify app sandbox allows UserDefaults
- Check for any background app termination issues

### Can't open in Spotify app

- Verify Spotify app is installed
- Check `spotify://` URL scheme is declared in Info.plist
- Test with `https://open.spotify.com/` fallback

## Migration Notes

### Existing Users

- Existing app-level authentication still works
- User login is optional but recommended
- No breaking changes to existing features

### Future Enhancements

Potential features enabled by OAuth:
- Save favorite tracks
- Get personalized recommendations
- Create and manage playlists
- Access recently played tracks
- Get user's top artists and tracks

## References

- [Spotify Authorization Guide](https://developer.spotify.com/documentation/web-api/concepts/authorization)
- [PKCE RFC 7636](https://datatracker.ietf.org/doc/html/rfc7636)
- [ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)
