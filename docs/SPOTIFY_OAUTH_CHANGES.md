# Spotify OAuth 2.0 Implementation Summary

## Overview

This document summarizes the code changes made to implement Spotify OAuth 2.0 authentication with PKCE in NihonGoStart.

## Files Changed

### 1. DataModels.swift
**Location:** `/NihonGoStart/Models/DataModels.swift`

**Changes:**
- Added `SpotifyUserProfile` struct with Codable conformance
- Added `SpotifyImage` struct for profile images

```swift
struct SpotifyUserProfile: Codable {
    let displayName: String?
    let id: String
    let images: [SpotifyImage]?
    let email: String?
    let product: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case id, images, email, product
    }
}

struct SpotifyImage: Codable {
    let url: String
    let height: Int?
    let width: Int?
}
```

---

### 2. SpotifyManager.swift
**Location:** `/NihonGoStart/Managers/SpotifyManager.swift`

**Major Changes:**

#### A. New Imports
```swift
import CryptoKit
import AuthenticationServices
```

#### B. Class Declaration
```swift
class SpotifyManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
```

#### C. New Properties

**OAuth Configuration:**
```swift
private let redirectURI = "nihongostart://callback"
private let tokenURL = "https://accounts.spotify.com/api/token"
private let authURL = "https://accounts.spotify.com/authorize"
private let scopes = "user-read-private user-read-email user-library-read user-top-read"
```

**UserDefaults Keys:**
```swift
private let userAccessTokenKey = "spotify_user_access_token"
private let userRefreshTokenKey = "spotify_user_refresh_token"
private let tokenExpirationKey = "spotify_token_expiration"
private let userProfileKey = "spotify_user_profile"
```

**PKCE:**
```swift
private var codeVerifier: String?
private var codeChallenge: String?
```

**Published Properties:**
```swift
@Published var userAccessToken: String?
@Published var userRefreshToken: String?
@Published var userProfile: SpotifyUserProfile?
@Published var isLoggedIn: Bool
private var tokenExpirationDate: Date?
```

#### D. New Methods

**PKCE Helpers:**
```swift
private func generateCodeVerifier() -> String
private func generateCodeChallenge(verifier: String) -> String
```

**OAuth Flow:**
```swift
private func buildAuthURL() -> URL?
func login()
func exchangeCodeForToken(code: String) async
private func extractCode(from url: URL) -> String?
```

**Token Management:**
```swift
func refreshUserAccessToken() async
```

**User Profile:**
```swift
func getUserProfile() async
```

**Session Management:**
```swift
func logout()
private func saveUserSession()
private func saveUserProfile()
private func loadUserSession()
```

**ASWebAuthenticationPresentationContextProviding:**
```swift
func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor
```

#### E. Updated Methods

**searchJapaneseSongs:**
- Now uses user access token if logged in
- Falls back to app-level token
- Auto-refreshes expired tokens

**openInSpotify:**
- Updated to use `spotify://` URL scheme for app deep link
- Falls back to web player

---

### 3. SongsView.swift
**Location:** `/NihonGoStart/Views/Songs/SongsView.swift`

**Changes:**

#### A. New State Variable
```swift
@State private var showLoginSheet = false
```

#### B. UI Updates

**Added UserProfileBar below navigation title:**
```swift
if spotifyManager.isLoggedIn, let profile = spotifyManager.userProfile {
    UserProfileBar(
        profile: profile,
        onLogout: { spotifyManager.logout() }
    )
}
```

**Updated welcome screen:**
- Changed button from "Connect to Spotify" to "Login with Spotify"
- Added explanation about personalization
- Changed action from `authenticate()` to `login()`

#### C. New Component

**UserProfileBar:**
```swift
struct UserProfileBar: View {
    let profile: SpotifyUserProfile
    let onLogout: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Profile image
            AsyncImage(url: URL(string: profile.images?.first?.url ?? ""))

            // User info
            VStack(alignment: .leading) {
                Text(profile.displayName ?? "Spotify User")
                Text(profile.product?.capitalized ?? "")
            }

            Spacer()

            // Logout button
            Button("Logout") { onLogout() }
        }
    }
}
```

---

### 4. NihonGoStartApp.swift
**Location:** `/NihonGoStart/App/NihonGoStartApp.swift`

**Changes:**

#### A. Added URL Handling
```swift
.onOpenURL { url in
    handleIncomingURL(url)
}
```

#### B. Added Handler Method
```swift
private func handleIncomingURL(_ url: URL) {
    if url.scheme == "nihongostart" {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
            Task {
                await SpotifyManager.shared.exchangeCodeForToken(code: code)
            }
        }
    }
}
```

---

## Configuration Required

### Spotify Dashboard

1. Add redirect URI: `nihongostart://callback`
2. Enable scopes:
   - user-read-private
   - user-read-email
   - user-library-read
   - user-top-read

### Xcode Target Settings

Add URL Types in Info tab:

**Type 1 (OAuth Callback):**
- Identifier: `com.ziqiyang.nihongostart.spotify`
- URL Schemes: `nihongostart`
- Role: Editor

**Type 2 (Spotify Deep Link):**
- Identifier: `com.spotify.client`
- URL Schemes: `spotify`
- Role: None

---

## Authentication Flow Diagram

```
┌─────────────┐
│ User Taps   │
│ "Login"     │
└──────┬──────┘
       │
       ▼
┌─────────────────────────┐
│ Generate PKCE:          │
│ - code_verifier         │
│ - code_challenge        │
└──────┬──────────────────┘
       │
       ▼
┌─────────────────────────┐
│ ASWebAuthenticationSession│
│ Opens Spotify Login      │
└──────┬──────────────────┘
       │
       ▼
┌─────────────────────────┐
│ User Grants Permission  │
└──────┬──────────────────┘
       │
       ▼
┌─────────────────────────┐
│ Spotify Redirects:       │
│ nihongostart://callback  │
│ ?code=AUTHORIZATION_CODE│
└──────┬──────────────────┘
       │
       ▼
┌─────────────────────────┐
│ App Receives Callback    │
│ via onOpenURL            │
└──────┬──────────────────┘
       │
       ▼
┌─────────────────────────┐
│ Exchange Code + Verifier │
│ for Access Token         │
└──────┬──────────────────┘
       │
       ▼
┌─────────────────────────┐
│ Fetch User Profile       │
│ Store Tokens             │
└──────┬──────────────────┘
       │
       ▼
┌─────────────────────────┐
│ Update UI: Show Profile  │
└─────────────────────────┘
```

---

## Token Refresh Flow

```
App Launch
    │
    ▼
Load Tokens from UserDefaults
    │
    ▼
Check Expiration
    │
    ├─→ Valid → Use existing token
    │
    └─→ Expired →
        │
        ▼
    refreshUserAccessToken()
        │
        ├─→ Success → Update tokens
        │
        └─→ Failure → Logout (user must login again)
```

---

## Key Features

### Security
- PKCE prevents authorization code interception
- No client secret in app (mobile-safe)
- Short-lived access tokens (1 hour)
- Refresh token rotation support

### User Experience
- Safari-based authentication (native feel)
- Persistent login across app launches
- Automatic token refresh
- Clear logout option

### Functionality
- Personalized search results
- User profile display
- Full track opening in Spotify app
- Future: Save favorites, playlists, etc.

---

## Testing Checklist

- [ ] Login flow completes successfully
- [ ] User profile displays correctly
- [ ] Token persists after app restart
- [ ] Token refresh works automatically
- [ ] Logout clears all user data
- [ ] Search works with user token
- [ ] Opening tracks in Spotify app works
- [ ] Fallback to app-level token works when logged out

---

## Known Limitations

1. **No Background Refresh**: Token refresh only happens on app launch
2. **UserDefaults Storage**: Not as secure as Keychain (acceptable for tokens)
3. **Single User**: Only one Spotify account can be logged in at a time

---

## Future Enhancements

1. Add Keychain storage for better security
2. Implement user's saved tracks/favorites
3. Add personalized recommendations
4. Support playlist creation/management
5. Add recently played tracks
6. Implement user's top artists/tracks
7. Add biometric lock for sensitive features

---

## Troubleshooting

**Issue**: "Invalid redirect URI"
- **Fix**: Add `nihongostart://callback` in Spotify Dashboard

**Issue**: "URL scheme not supported"
- **Fix**: Add URL scheme in Xcode target Info settings

**Issue**: Token doesn't persist
- **Fix**: Check UserDefaults is working, enable app sandbox

**Issue**: Can't open Spotify app
- **Fix**: Add `spotify://` to URL types in Info.plist

---

## References

- [Spotify Authorization Code Flow with PKCE](https://developer.spotify.com/documentation/web-api/concepts/authorization/code-flow)
- [PKCE RFC 7636](https://datatracker.ietf.org/doc/html/rfc7636)
- [ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)
- [iOS URL Schemes](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app)
