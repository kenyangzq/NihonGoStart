# Spotify OAuth Implementation - Quick Reference

## Complete Implementation Files

### 1. DataModels.swift - Add at end of file (before last `}`)

```swift
// MARK: - Spotify User Profile

struct SpotifyUserProfile: Codable {
    let displayName: String?
    let id: String
    let images: [SpotifyImage]?
    let email: String?
    let product: String? // "premium", "free", etc.

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

### 2. SpotifyManager.swift - Complete OAuth Implementation

```swift
import Foundation
import AVFoundation
import UIKit
import CryptoKit
import AuthenticationServices

class SpotifyManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = SpotifyManager()

    // MARK: - Configuration

    private let clientId: String
    private let clientSecret: String

    // OAuth Configuration
    private let redirectURI = "nihongostart://callback"
    private let tokenURL = "https://accounts.spotify.com/api/token"
    private let authURL = "https://accounts.spotify.com/authorize"
    private let scopes = [
        "user-read-private",
        "user-read-email",
        "user-library-read",
        "user-top-read"
    ].joined(separator: " ")

    // UserDefaults Keys
    private let userAccessTokenKey = "spotify_user_access_token"
    private let userRefreshTokenKey = "spotify_user_refresh_token"
    private let tokenExpirationKey = "spotify_token_expiration"
    private let userProfileKey = "spotify_user_profile"

    // PKCE
    private var codeVerifier: String?
    private var codeChallenge: String?

    // MARK: - Initialization

    init() {
        if Secrets.spotifyClientId != "" && Secrets.spotifyClientSecret != "" {
            self.clientId = Secrets.spotifyClientId
            self.clientSecret = Secrets.spotifyClientSecret
            self.needsConfiguration = false
        } else {
            self.clientId = "YOUR_CLIENT_ID"
            self.clientSecret = "YOUR_CLIENT_SECRET"
            self.needsConfiguration = true
        }
        super.init()
        loadUserSession()
    }

    // MARK: - Published Properties

    // App-level access (Client Credentials)
    @Published var accessToken: String?
    @Published var isAuthenticated = false

    // User-level access (OAuth with PKCE)
    @Published var userAccessToken: String?
    @Published var userRefreshToken: String?
    @Published var userProfile: SpotifyUserProfile?
    @Published var isLoggedIn = false

    @Published var searchResults: [SpotifyTrack] = []
    @Published var isSearching = false
    @Published var isAuthenticating = false
    @Published var errorMessage: String?
    @Published var needsConfiguration = false

    private var audioPlayer: AVPlayer?
    @Published var isPlaying = false
    @Published var currentTrack: SpotifyTrack?
    private var tokenExpirationDate: Date?

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        let codeVerifier = Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return codeVerifier
    }

    private func generateCodeChallenge(verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        let hashed = SHA256.hash(data: data)
        let challenge = Data(hashed).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return challenge
    }

    // MARK: - OAuth Login Flow

    private func buildAuthURL() -> URL? {
        codeVerifier = generateCodeVerifier()
        codeChallenge = generateCodeChallenge(verifier: codeVerifier!)

        var components = URLComponents(string: authURL)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "show_dialog", value: "true")
        ]
        return components?.url
    }

    func login() {
        guard let authURL = buildAuthURL() else {
            errorMessage = "Failed to build authorization URL"
            return
        }

        let authSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "nihongostart"
        ) { [weak self] callbackURL, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = "Authentication failed: \(error.localizedDescription)"
                }
                return
            }

            guard let callbackURL = callbackURL else {
                DispatchQueue.main.async {
                    self?.errorMessage = "Invalid callback URL"
                }
                return
            }

            guard let code = self?.extractCode(from: callbackURL) else {
                DispatchQueue.main.async {
                    self?.errorMessage = "Failed to extract authorization code"
                }
                return
            }

            Task {
                await self?.exchangeCodeForToken(code: code)
            }
        }

        authSession.presentationContextProvider = self
        authSession.start()
    }

    private func extractCode(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == "code" })?.value
    }

    func exchangeCodeForToken(code: String) async {
        guard let verifier = codeVerifier,
              let url = URL(string: tokenURL) else {
            await MainActor.run {
                self.errorMessage = "Invalid code verifier or token URL"
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_verifier", value: verifier)
        ]

        request.httpBody = bodyComponents.query?.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let accessToken = json["access_token"] as? String,
                   let refreshToken = json["refresh_token"] as? String,
                   let expiresIn = json["expires_in"] as? Int {

                    let expirationDate = Date().addingTimeInterval(TimeInterval(expiresIn))

                    await MainActor.run {
                        self.userAccessToken = accessToken
                        self.userRefreshToken = refreshToken
                        self.tokenExpirationDate = expirationDate
                        self.isLoggedIn = true
                        self.errorMessage = nil
                    }

                    saveUserSession()
                    await getUserProfile()
                } else if let error = json["error"] as? String {
                    await MainActor.run {
                        self.errorMessage = "Token exchange failed: \(error)"
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Token exchange failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Token Management

    func refreshUserAccessToken() async {
        guard let refreshToken = userRefreshToken,
              let url = URL(string: tokenURL) else {
            await MainActor.run {
                self.errorMessage = "No refresh token available"
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken)
        ]

        request.httpBody = bodyComponents.query?.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let accessToken = json["access_token"] as? String,
                   let expiresIn = json["expires_in"] as? Int {

                    let expirationDate = Date().addingTimeInterval(TimeInterval(expiresIn))

                    await MainActor.run {
                        self.userAccessToken = accessToken
                        self.tokenExpirationDate = expirationDate
                    }

                    if let newRefreshToken = json["refresh_token"] as? String {
                        await MainActor.run {
                            self.userRefreshToken = newRefreshToken
                        }
                    }

                    saveUserSession()
                } else if let error = json["error"] as? String {
                    await MainActor.run {
                        self.errorMessage = "Token refresh failed: \(error)"
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Token refresh failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - User Profile

    func getUserProfile() async {
        guard let accessToken = userAccessToken,
              let url = URL(string: "https://api.spotify.com/v1/me") else {
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            let profile = try decoder.decode(SpotifyUserProfile.self, from: data)

            await MainActor.run {
                self.userProfile = profile
            }

            saveUserProfile()
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to fetch user profile: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Session Management

    func logout() {
        userAccessToken = nil
        userRefreshToken = nil
        userProfile = nil
        isLoggedIn = false
        tokenExpirationDate = nil

        UserDefaults.standard.removeObject(forKey: userAccessTokenKey)
        UserDefaults.standard.removeObject(forKey: userRefreshTokenKey)
        UserDefaults.standard.removeObject(forKey: tokenExpirationKey)
        UserDefaults.standard.removeObject(forKey: userProfileKey)
    }

    private func saveUserSession() {
        UserDefaults.standard.set(userAccessToken, forKey: userAccessTokenKey)
        UserDefaults.standard.set(userRefreshToken, forKey: userRefreshTokenKey)
        if let expiration = tokenExpirationDate {
            UserDefaults.standard.set(expiration.timeIntervalSince1970, forKey: tokenExpirationKey)
        }
    }

    private func saveUserProfile() {
        if let profile = userProfile,
           let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: userProfileKey)
        }
    }

    private func loadUserSession() {
        userAccessToken = UserDefaults.standard.string(forKey: userAccessTokenKey)
        userRefreshToken = UserDefaults.standard.string(forKey: userRefreshTokenKey)

        if let expirationInterval = UserDefaults.standard.object(forKey: tokenExpirationKey) as? TimeInterval {
            tokenExpirationDate = Date(timeIntervalSince1970: expirationInterval)
        }

        if let profileData = UserDefaults.standard.data(forKey: userProfileKey),
           let profile = try? JSONDecoder().decode(SpotifyUserProfile.self, from: profileData) {
            userProfile = profile
        }

        if let expiration = tokenExpirationDate, expiration > Date() {
            isLoggedIn = true
        } else {
            if userRefreshToken != nil {
                Task {
                    await refreshUserAccessToken()
                }
            } else {
                isLoggedIn = false
            }
        }
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }

    // ... rest of existing methods (authenticate, searchJapaneseSongs, etc.)
}
```

---

### 3. NihonGoStartApp.swift - Add URL Handling

```swift
import SwiftUI
import WidgetKit

@main
struct NihonGoStartApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    WidgetDataProvider.shared.syncDataFromApp()
                    WidgetCenter.shared.reloadAllTimelines()
                }
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
        }
    }

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
}
```

---

### 4. SongsView.swift - Add User Profile UI

**Add to body, after navigationTitle:**
```swift
// User Profile Bar (shown when logged in)
if spotifyManager.isLoggedIn, let profile = spotifyManager.userProfile {
    UserProfileBar(
        profile: profile,
        onLogout: {
            spotifyManager.logout()
        }
    )
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(Color(UIColor.secondarySystemBackground))
}
```

**Update welcome screen button:**
```swift
Button(action: {
    spotifyManager.login()
}) {
    HStack {
        Image(systemName: "person.badge.plus")
        Text("Login with Spotify")
    }
    .foregroundColor(.white)
    .padding(.horizontal, 24)
    .padding(.vertical, 12)
    .background(Color.green)
    .cornerRadius(25)
}

Text("Login to save favorites and get personalized recommendations")
    .font(.caption)
    .foregroundColor(.secondary)
    .multilineTextAlignment(.center)
```

**Add UserProfileBar component at end of file:**
```swift
struct UserProfileBar: View {
    let profile: SpotifyUserProfile
    let onLogout: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: profile.images?.first?.url ?? "")) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color.green.opacity(0.3))
                    .overlay(Image(systemName: "person.fill").foregroundColor(.green))
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName ?? "Spotify User")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let product = profile.product {
                    Text(product.capitalized)
                        .font(.caption2)
                        .foregroundColor(product == "premium" ? .green : .secondary)
                }
            }

            Spacer()

            Button(action: onLogout) {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.portrait.and.arrow.right").font(.caption)
                    Text("Logout").font(.caption)
                }
                .foregroundColor(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.1))
                .cornerRadius(15)
            }
        }
    }
}
```

---

## Configuration Checklist

### Spotify Dashboard
- [ ] Redirect URI: `nihongostart://callback`
- [ ] Scopes enabled:
  - [ ] user-read-private
  - [ ] user-read-email
  - [ ] user-library-read
  - [ ] user-top-read

### Xcode Target Settings
- [ ] URL Scheme: `nihongostart`
- [ ] Role: Editor
- [ ] (Optional) URL Scheme: `spotify`

### Secrets.swift
- [ ] spotifyClientId configured
- [ ] spotifyClientSecret configured

---

## Testing Flow

1. **Build & Run App**
2. **Navigate to Songs Tab**
3. **Tap "Login with Spotify"**
4. **Complete Spotify Login**
5. **Verify Profile Appears**
6. **Kill App & Relaunch** (test persistence)
7. **Test Search** (should use user token)
8. **Test Logout**
9. **Verify Login Screen Returns**

---

## Key Implementation Points

### PKCE Security
- Code verifier: 32 random bytes → base64url encoded
- Code challenge: SHA256(verifier) → base64url encoded
- Prevents authorization code interception

### Token Storage
- UserDefaults for simplicity (acceptable for tokens)
- Access token: 1 hour expiry
- Refresh token: long-lived
- Auto-refresh on app launch if expired

### User Experience
- Native Safari authentication (ASWebAuthenticationSession)
- Seamless redirect back to app
- Persistent login across app launches
- Clear logout option

---

## Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| Invalid redirect URI | Add `nihongostart://callback` in Spotify Dashboard |
| URL scheme not working | Add `nihongostart` in Xcode Info → URL Types |
| Token doesn't persist | Check UserDefaults, verify app sandbox |
| Can't open Spotify app | Add `spotify://` URL scheme in Info.plist |
| Login button does nothing | Verify URL scheme, clean build, reinstall app |

---

## Next Steps

After basic OAuth is working:

1. **User Library**: Fetch and display saved tracks
2. **Top Tracks**: Show user's top Japanese tracks
3. **Playlists**: Allow creating learning playlists
4. **Recommendations**: Personalized song suggestions
5. **Keychain Storage**: Migrate from UserDefaults for better security
6. **Background Refresh**: Auto-refresh tokens in background

---

## API References

- [Spotify Web API Reference](https://developer.spotify.com/documentation/web-api)
- [Authorization Code Flow with PKCE](https://developer.spotify.com/documentation/web-api/concepts/authorization/code-flow)
- [ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)
- [CryptoKit](https://developer.apple.com/documentation/cryptokit)
