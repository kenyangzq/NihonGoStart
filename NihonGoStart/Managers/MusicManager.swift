import Foundation
import AVFoundation
import UIKit
import CryptoKit
import AuthenticationServices
import MusicKit

// MARK: - Apple Music JWT Generator

class MusicJWTGenerator {
    private let teamId: String
    private let keyId: String
    private let privateKey: String

    init(teamId: String, keyId: String, privateKey: String) {
        self.teamId = teamId
        self.keyId = keyId
        self.privateKey = privateKey
    }

    func generateDeveloperToken() -> String? {
        guard let privateKeyData = Data(base64Encoded: privateKey) else {
            print("Failed to decode private key")
            return nil
        }

        let header = [
            "alg": "ES256",
            "kid": keyId
        ]

        let currentTime = Date().timeIntervalSince1970
        let expirationTime = currentTime + (6 * 30 * 24 * 60 * 60) // 6 months

        let payload = [
            "iss": teamId,
            "iat": Int(currentTime),
            "exp": Int(expirationTime),
            "sub": "MusicKitUser"
        ] as [String: Any]

        guard let headerData = try? JSONSerialization.data(withJSONObject: header),
              let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
            return nil
        }

        let headerBase64 = headerData.base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")

        let payloadBase64 = payloadData.base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")

        let signingInput = "\(headerBase64).\(payloadBase64)"

        guard let signature = signWithES256(signingInput, privateKeyData: privateKeyData) else {
            return nil
        }

        return "\(headerBase64).\(payloadBase64).\(signature)"
    }

    private func signWithES256(_ message: String, privateKeyData: Data) -> String? {
        guard let privateKey = try? P256.Signing.PrivateKey(rawRepresentation: privateKeyData) else {
            // Try as PEM format
            return nil
        }

        guard let messageData = message.data(using: .utf8) else { return nil }

        let signature = try? privateKey.signature(for: messageData)

        guard let signature = signature else { return nil }

        let signatureData = signature.rawRepresentation

        return signatureData.base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
    }
}

// MARK: - Music Manager

@MainActor
class MusicManager: NSObject, ObservableObject {
    static let shared = MusicManager()

    // MARK: - Configuration

    private let teamId: String
    private let keyId: String
    private let privateKey: String

    // Apple Music API Endpoints
    private let apiBaseURL = "https://api.music.apple.com/v1"
    private let japanStorefront = "jp"
    private let usStorefront = "us"

    // Music Catalog Search API - Developer token for catalog operations
    private var developerToken: String?

    // MARK: - MusicKit

    private var musicPlayer: MusicPlayer?
    @Published var applicationMusicPlayer: ApplicationMusicPlayer?
    private let keychainManager = KeychainManager.shared

    // MARK: - Published Properties

    @Published var isConfigured = false
    @Published var isUserAuthenticated = false // User has authorized with their Apple ID
    @Published var hasDeveloperToken = false // Developer token is configured
    @Published var isAuthenticating = false
    @Published var searchResults: [AppleMusicTrack] = []
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var subscriptionStatus: MusicSubscriptionStatus = .unknown
    @Published var countryCode: String?

    // Legacy playback (for preview only)
    private var audioPlayer: AVPlayer?
    private var playerItem: AVPlayerItem?
    @Published var isPlaying = false
    @Published var currentTrack: AppleMusicTrack?
    @Published var currentLyrics: [AppleMusicLyric] = []

    // Storefront preference (can be changed by user)
    @Published var preferredStorefront: String = "jp" // Default to Japan store

    private var timeObserver: Any?

    // MARK: - Music Subscription Status

    enum MusicSubscriptionStatus {
        case unknown
        case subscribed
        case notSubscribed
        case noAppleMusic

        var displayName: String {
            switch self {
            case .unknown: return "Unknown"
            case .subscribed: return "Apple Music Subscriber"
            case .notSubscribed: return "Free Account"
            case .noAppleMusic: return "No Apple Music"
            }
        }

        var canPlayFullTracks: Bool {
            switch self {
            case .subscribed: return true
            case .unknown, .notSubscribed, .noAppleMusic: return false
            }
        }
    }

    // MARK: - Initialization

    override init() {
        // Try to get credentials from Secrets.swift
        if !Secrets.appleMusicTeamId.isEmpty &&
           !Secrets.appleMusicKeyId.isEmpty &&
           !Secrets.appleMusicPrivateKey.isEmpty {
            self.teamId = Secrets.appleMusicTeamId
            self.keyId = Secrets.appleMusicKeyId
            self.privateKey = Secrets.appleMusicPrivateKey
            self.isConfigured = true
        } else {
            self.teamId = ""
            self.keyId = ""
            self.privateKey = ""
            self.isConfigured = false
        }

        super.init()

        if self.isConfigured {
            generateDeveloperToken()
        }

        setupAudioSession()
        loadUserPreferences()
        checkUserAuthenticationStatus()
    }

    deinit {
        removeTimeObserver()
        stopPlayback()
    }

    // MARK: - Token Management

    private func generateDeveloperToken() {
        guard isConfigured else { return }

        let generator = MusicJWTGenerator(
            teamId: teamId,
            keyId: keyId,
            privateKey: privateKey
        )

        developerToken = generator.generateDeveloperToken()

        if developerToken != nil {
            hasDeveloperToken = true
            // Configure MusicKit with developer token
            Task {
                await configureMusicKit()
            }
        }
    }

    private func configureMusicKit() async {
        guard let token = developerToken else { return }

        do {
            // Configure MusicKit with developer token for catalog operations
            try await MusicDataProperties.current.developerToken = token
            print("MusicKit configured successfully")
        } catch {
            print("Failed to configure MusicKit: \(error)")
        }
    }

    // MARK: - User Authentication

    func checkUserAuthenticationStatus() {
        // Check if we have a stored user token
        if let userToken = keychainManager.loadUserToken() {
            isUserAuthenticated = true
            Task {
                await fetchSubscriptionStatus()
            }
        } else {
            isUserAuthenticated = false
            subscriptionStatus = .noAppleMusic
        }
    }

    func requestUserAuthorization() async throws {
        guard hasDeveloperToken else {
            throw MusicAuthError.notConfigured
        }

        await MainActor.run {
            isAuthenticating = true
        }

        do {
            // Request MusicKit user authorization with required scopes
            // Note: MusicKit's native requestAuthorization doesn't allow custom scope specification
            // The scopes are determined by the MusicKit capability and user's consent
            let status = await MusicAuthorizationKit.Request.userAuthorization.access capabilities: []

            await MainActor.run {
                isAuthenticating = false

                switch status {
                case .authorized:
                    isUserAuthenticated = true

                    // Get and store user token
                    Task {
                        await storeUserToken()
                        await fetchSubscriptionStatus()
                    }

                case .denied:
                    isUserAuthenticated = false
                    errorMessage = "Apple Music access was denied. Please enable in Settings."

                case .notDetermined:
                    isUserAuthenticated = false
                    errorMessage = "Authorization could not be determined."

                case .restricted:
                    isUserAuthenticated = false
                    errorMessage = "Apple Music is restricted on this device."

                @unknown default:
                    isUserAuthenticated = false
                    errorMessage = "Unknown authorization status."
                }
            }
        } catch {
            await MainActor.run {
                isAuthenticating = false
                isUserAuthenticated = false
                errorMessage = "Authorization failed: \(error.localizedDescription)"
                throw error
            }
        }
    }

    private func storeUserToken() async {
        do {
            // Get the current MusicUserToken
            let userToken = try await MusicUserToken.developerToken

            // Store it in keychain
            _ = keychainManager.saveUserToken(userToken)
            print("User token stored successfully")
        } catch {
            print("Failed to store user token: \(error)")
        }
    }

    func logoutUser() {
        // Remove user token from keychain
        _ = keychainManager.deleteUserToken()

        // Reset state
        isUserAuthenticated = false
        subscriptionStatus = .noAppleMusic
        countryCode = nil

        // Stop any playback
        stopPlayback()

        print("User logged out successfully")
    }

    private func fetchSubscriptionStatus() async {
        guard isUserAuthenticated else {
            subscriptionStatus = .noAppleMusic
            return
        }

        do {
            // Fetch catalog subscription status
            let catalogSubscription = try await MusicCatalogSubscriptionRequest().response()

            await MainActor.run {
                self.countryCode = catalogSubscription.storefrontID

                if catalogSubscription.canPlayCatalogContent {
                    subscriptionStatus = .subscribed
                } else {
                    subscriptionStatus = .notSubscribed
                }
            }
        } catch {
            print("Failed to fetch subscription status: \(error)")
            await MainActor.run {
                // If we can't fetch, assume not subscribed but allow catalog search
                subscriptionStatus = .notSubscribed
            }
        }
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    // MARK: - User Preferences

    private func loadUserPreferences() {
        if let savedStorefront = UserDefaults.standard.string(forKey: "appleMusicStorefront") {
            preferredStorefront = savedStorefront
        }
    }

    func setStorefront(_ storefront: String) {
        preferredStorefront = storefront
        UserDefaults.standard.set(storefront, forKey: "appleMusicStorefront")
    }

    // MARK: - Search (Works with developer token - no user auth required)

    func searchJapaneseSongs(query: String) async {
        guard hasDeveloperToken, let token = developerToken else {
            await MainActor.run {
                self.errorMessage = "Apple Music not configured. Please add your Music Kit credentials in Secrets.swift"
            }
            return
        }

        await MainActor.run {
            self.isSearching = true
            self.searchResults = []
            self.errorMessage = nil
        }

        // Try MusicKit catalog search first (requires developer token)
        if isUserAuthenticated {
            await searchWithMusicKit(query: query)
        } else {
            // Fall back to REST API search
            await searchWithRestAPI(query: query)
        }
    }

    private func searchWithMusicKit(query: String) async {
        do {
            // Use MusicKit's catalog search
            var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
            request.limit = 20

            let searchResult = try await request.response()

            var tracks: [AppleMusicTrack] = []

            for song in searchResult.songs {
                // Get artwork URL
                var artworkURL: String?
                if let artwork = song.artwork {
                    artworkURL = artwork.url(width: 300, height: 300).absoluteString
                }

                let track = AppleMusicTrack(
                    id: song.id.rawValue,
                    catalogId: song.id.rawValue,
                    name: song.title,
                    artist: song.artistName,
                    albumName: song.albumTitle,
                    artworkURL: artworkURL,
                    duration: song.duration,
                    previewURL: song.previewURL?.absoluteString,
                    appleMusicURL: song.url.absoluteString,
                    storefront: preferredStorefront
                )

                tracks.append(track)
            }

            await MainActor.run {
                self.searchResults = tracks
                self.isSearching = false

                if tracks.isEmpty {
                    self.errorMessage = "No songs found. Try searching for Japanese artists."
                }
            }
        } catch {
            print("MusicKit search failed: \(error)")
            // Fall back to REST API
            await searchWithRestAPI(query: query)
        }
    }

    private func searchWithRestAPI(query: String) async {
        // Search in both Japanese and US stores for better coverage
        let storefronts = [preferredStorefront, usStorefront]

        var allTracks: [AppleMusicTrack] = []
        var seenIds = Set<String>()

        for storefront in storefronts {
            let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            let urlString = "\(apiBaseURL)/catalog/\(storefront)/search?term=\(encodedQuery)&types=songs&limit=20"

            guard let url = URL(string: urlString) else { continue }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(developerToken ?? "")", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 15

            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {
                    let tracks = parseSearchResults(data: data, storefront: storefront)

                    // Deduplicate tracks by ID
                    for track in tracks {
                        if !seenIds.contains(track.id) {
                            seenIds.insert(track.id)
                            allTracks.append(track)
                        }
                    }
                }
            } catch {
                print("Search error for store \(storefront): \(error)")
            }
        }

        await MainActor.run {
            self.searchResults = allTracks
            self.isSearching = false

            if allTracks.isEmpty {
                self.errorMessage = "No songs found. Try searching for Japanese artists."
            }
        }
    }

    private func parseSearchResults(data: Data, storefront: String) -> [AppleMusicTrack] {
        var tracks: [AppleMusicTrack] = []

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [String: Any],
               let songs = results["songs"] as? [String: Any],
               let dataArray = songs["data"] as? [[String: Any]] {

                for item in dataArray {
                    guard let attributes = item["attributes"] as? [String: Any],
                          let id = item["id"] as? String,
                          let name = attributes["name"] as? String,
                          let artistName = attributes["artistName"] as? String else {
                        continue
                    }

                    let albumName = attributes["albumName"] as? String ?? ""
                    let playParams = attributes["playParams"] as? [String: Any]
                    let catalogId = playParams?["catalogId"] as? String ?? id

                    let artwork = attributes["artwork"] as? [String: Any]
                    let imageURL = getArtworkURL(from: artwork)

                    let durationInMillis = attributes["durationInMillis"] as? Int ?? 0
                    let duration = durationInMillis > 0 ? Double(durationInMillis) / 1000.0 : nil

                    let previewURL = attributes["previewURL"] as? String
                    let url = attributes["url"] as? String

                    let track = AppleMusicTrack(
                        id: id,
                        catalogId: catalogId,
                        name: name,
                        artist: artistName,
                        albumName: albumName,
                        artworkURL: imageURL,
                        duration: duration,
                        previewURL: previewURL,
                        appleMusicURL: url,
                        storefront: storefront
                    )

                    tracks.append(track)
                }
            }
        } catch {
            print("Parse error: \(error)")
        }

        return tracks
    }

    private func getArtworkURL(from artwork: [String: Any]?) -> String? {
        guard let artwork = artwork,
              let width = artwork["width"] as? Int,
              let height = artwork["height"] as? Int,
              let urlTemplate = artwork["url"] as? String else {
            return nil
        }

        // Apple Music uses URL templates with {w} and {h} placeholders
        // Replace with standard size
        return urlTemplate
            .replacingOccurrences(of: "{w}", with: "\(width)")
            .replacingOccurrences(of: "{h}", with: "\(height)")
    }

    // MARK: - Playback

    func playTrack(_ track: AppleMusicTrack) {
        // If user is subscribed and authenticated, use MusicKit for full playback
        if isUserAuthenticated && subscriptionStatus.canPlayFullTracks {
            Task {
                await playFullTrackWithMusicKit(track)
            }
        } else {
            // Otherwise, use preview playback
            playPreview(track)
        }
    }

    private func playFullTrackWithMusicKit(_ track: AppleMusicTrack) async {
        guard isUserAuthenticated else {
            await MainActor.run {
                errorMessage = "Please connect to Apple Music first"
            }
            return
        }

        do {
            // Create MusicKit track from catalog ID
            let trackID = MusicItemID(track.catalogId)
            let song = try await MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: trackID).response().items.first

            guard let song = song else {
                await MainActor.run {
                    errorMessage = "Track not found in catalog"
                    playPreview(track)
                }
                return
            }

            // Initialize application music player if needed
            if applicationMusicPlayer == nil {
                applicationMusicPlayer = ApplicationMusicPlayer.shared
            }

            // Play the track using MusicKit
            let playbackQueue = ApplicationMusicPlayer.Queue(items: [song])
            applicationMusicPlayer?.queue = playbackQueue
            try await applicationMusicPlayer?.play()

            await MainActor.run {
                currentTrack = track
                isPlaying = true
                errorMessage = nil
            }

            // Fetch lyrics
            await fetchLyrics(for: track)
        } catch {
            print("MusicKit playback failed: \(error)")
            await MainActor.run {
                // Fall back to preview
                errorMessage = "Full playback unavailable. Playing preview."
                playPreview(track)
            }
        }
    }

    private func playPreview(_ track: AppleMusicTrack) {
        stopPlayback()

        guard let previewURLString = track.previewURL,
              let url = URL(string: previewURLString) else {
            errorMessage = "Preview not available. Open in Apple Music to listen."
            return
        }

        let playerItem = AVPlayerItem(url: url)
        self.playerItem = playerItem
        audioPlayer = AVPlayer(playerItem: playerItem)
        audioPlayer?.play()

        currentTrack = track
        isPlaying = true
        errorMessage = nil

        // Setup time observer for end of playback
        setupTimeObserver()

        // Fetch lyrics
        Task {
            await fetchLyrics(for: track)
        }
    }

    func stopPlayback() {
        // Stop MusicKit player
        Task {
            try? await applicationMusicPlayer?.stop()
        }

        // Stop preview player
        audioPlayer?.pause()
        audioPlayer = nil
        playerItem = nil
        currentTrack = nil
        isPlaying = false
        removeTimeObserver()
    }

    func togglePlayback(_ track: AppleMusicTrack) {
        if currentTrack?.id == track.id && isPlaying {
            pausePlayback()
        } else if currentTrack?.id == track.id && !isPlaying {
            resumePlayback()
        } else {
            playTrack(track)
        }
    }

    func pausePlayback() {
        if subscriptionStatus.canPlayFullTracks && isUserAuthenticated {
            Task {
                try? await applicationMusicPlayer?.pause()
            }
        } else {
            audioPlayer?.pause()
        }
        isPlaying = false
    }

    func resumePlayback() {
        if subscriptionStatus.canPlayFullTracks && isUserAuthenticated {
            Task {
                try? await applicationMusicPlayer?.play()
            }
        } else {
            audioPlayer?.play()
        }
        isPlaying = true
    }

    private func setupTimeObserver() {
        guard let player = audioPlayer, let playerItem = playerItem else { return }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC)),
            queue: .main
        ) { [weak self] _ in
            // Check if playback ended
            if playerItem.currentTime() >= playerItem.duration {
                self?.isPlaying = false
            }
        }
    }

    private func removeTimeObserver() {
        if let observer = timeObserver, let player = audioPlayer {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    // MARK: - Add to Library

    func addToLibrary(_ track: AppleMusicTrack) async {
        guard isUserAuthenticated else {
            await MainActor.run {
                errorMessage = "Please connect to Apple Music first"
            }
            return
        }

        guard subscriptionStatus.canPlayFullTracks else {
            await MainActor.run {
                errorMessage = "Apple Music subscription required to save songs"
            }
            return
        }

        do {
            let trackID = MusicItemID(track.catalogId)

            // Add to library using MusicKit
            let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: trackID)
            let song = try await request.response().items.first

            guard let song = song else {
                await MainActor.run {
                    errorMessage = "Track not found in catalog"
                }
                return
            }

            try await MCNLibrary.shared.add(song)

            await MainActor.run {
                errorMessage = "Added to Library"
            }
        } catch {
            print("Failed to add to library: \(error)")
            await MainActor.run {
                errorMessage = "Failed to add to Library: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Lyrics

    func fetchLyrics(for track: AppleMusicTrack) async {
        guard hasDeveloperToken, let token = developerToken else {
            return
        }

        let urlString = "\(apiBaseURL)/catalog/\(track.storefront)/songs/\(track.catalogId)/lyrics"

        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 {
                let lyrics = parseLyrics(data: data)
                await MainActor.run {
                    self.currentLyrics = lyrics
                }
            }
        } catch {
            print("Failed to fetch lyrics: \(error)")
            await MainActor.run {
                self.currentLyrics = []
            }
        }
    }

    private func parseLyrics(data: Data) -> [AppleMusicLyric] {
        var lyrics: [AppleMusicLyric] = []

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataArray = json["data"] as? [[String: Any]],
               let attributes = dataArray.first?["attributes"] as? [String: Any] {

                let ttml = attributes["ttml"] as? String ?? ""

                // Parse TTML format to extract synchronized lyrics
                lyrics = parseTTML(ttml)
            }
        } catch {
            print("Lyrics parse error: \(error)")
        }

        return lyrics
    }

    private func parseTTML(_ ttml: String) -> [AppleMusicLyric] {
        var lyrics: [AppleMusicLyric] = []

        // Simple TTML parser - extracts text and timing
        let pattern = #"<p begin="([^"]+)" end="([^"]+)">([^<]+)</p>"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return lyrics
        }

        let range = NSRange(ttml.startIndex..., in: ttml)
        let matches = regex.matches(in: ttml, range: range)

        for match in matches {
            guard match.numberOfRanges == 4 else { continue }

            let startTimeRange = Range(match.range(at: 1), in: ttml)
            let endTimeRange = Range(match.range(at: 2), in: ttml)
            let textRange = Range(match.range(at: 3), in: ttml)

            if let startTimeRange = startTimeRange,
               let endTimeRange = endTimeRange,
               let textRange = textRange {

                let startTime = parseTTMLTime(String(ttml[startTimeRange]))
                let endTime = parseTTMLTime(String(ttml[endTimeRange]))
                let text = String(ttml[textRange])
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !text.isEmpty {
                    let lyric = AppleMusicLyric(
                        id: UUID(),
                        content: text,
                        startTime: startTime,
                        endTime: endTime
                    )
                    lyrics.append(lyric)
                }
            }
        }

        return lyrics
    }

    private func parseTTMLTime(_ timeString: String) -> Double {
        // Parse TTML time format like "00:01:23.456" or "45.123"
        let components = timeString.split(separator: ":")
            .map { Double($0.trimmingCharacters(in: .whitespaces)) ?? 0.0 }

        switch components.count {
        case 1:
            return components[0]
        case 2:
            return components[0] * 60 + components[1]
        case 3:
            return components[0] * 3600 + components[1] * 60 + components[2]
        default:
            return 0.0
        }
    }

    // MARK: - Open in Apple Music

    func openInAppleMusic(_ track: AppleMusicTrack) {
        // Try to open in Apple Music app
        if let url = track.appleMusicURL {
            UIApplication.shared.open(URL(string: url)!)
        } else {
            // Fallback to search in Apple Music
            let searchQuery = "\(track.artist) \(track.name)"
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let searchURL = URL(string: "https://music.apple.com/search?term=\(searchQuery)") {
                UIApplication.shared.open(searchURL)
            }
        }
    }
}

// MARK: - Music Auth Error

enum MusicAuthError: LocalizedError {
    case notConfigured
    case authorizationFailed
    case tokenExpired

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Apple Music not configured. Please add your Music Kit credentials."
        case .authorizationFailed:
            return "Apple Music authorization failed."
        case .tokenExpired:
            return "Music token has expired. Please try again."
        }
    }
}
