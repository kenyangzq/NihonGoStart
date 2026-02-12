import Foundation
import AVFoundation
import UIKit

class SpotifyManager: ObservableObject {
    static let shared = SpotifyManager()

    // IMPORTANT: Replace these with your own Spotify API credentials
    // Get them from https://developer.spotify.com/dashboard
    private let clientId = "9c85d94e28244e0cb680a3ecda8c888f"
    private let clientSecret = "210934ed4df34a1e8ae8985513aba973"

    @Published var accessToken: String?
    @Published var isAuthenticated = false
    @Published var searchResults: [SpotifyTrack] = []
    @Published var isSearching = false
    @Published var isAuthenticating = false
    @Published var errorMessage: String?
    @Published var needsConfiguration = false

    private var audioPlayer: AVPlayer?
    @Published var isPlaying = false
    @Published var currentTrack: SpotifyTrack?

    private init() {
        // Check if credentials are configured
        if clientId == "YOUR_CLIENT_ID" || clientSecret == "YOUR_CLIENT_SECRET" {
            needsConfiguration = true
        }
    }

    // MARK: - Authentication

    func authenticate() async {
        // Check if already authenticating or if credentials not set
        if needsConfiguration {
            await MainActor.run {
                self.errorMessage = "Spotify API credentials not configured. Please add your Client ID and Secret in SpotifyManager.swift"
            }
            return
        }

        await MainActor.run {
            self.isAuthenticating = true
            self.errorMessage = nil
        }

        let tokenURL = "https://accounts.spotify.com/api/token"
        let credentials = "\(clientId):\(clientSecret)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            await MainActor.run {
                self.isAuthenticating = false
            }
            return
        }
        let base64Credentials = credentialsData.base64EncodedString()

        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=client_credentials".data(using: .utf8)
        request.timeoutInterval = 10 // 10 second timeout

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = json["access_token"] as? String {
                await MainActor.run {
                    self.accessToken = token
                    self.isAuthenticated = true
                    self.isAuthenticating = false
                    self.errorMessage = nil
                }
            } else if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let error = json["error"] as? String {
                await MainActor.run {
                    self.isAuthenticating = false
                    self.errorMessage = "Spotify error: \(error)"
                }
            }
        } catch {
            await MainActor.run {
                self.isAuthenticating = false
                self.errorMessage = "Connection failed. Check your internet connection."
            }
        }
    }

    // MARK: - Search

    func searchJapaneseSongs(query: String) async {
        if accessToken == nil {
            await authenticate()
        }

        guard accessToken != nil else { return }

        await MainActor.run {
            self.isSearching = true
            self.searchResults = []
        }

        // Add Japanese market and filter for Japanese content
        let searchQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://api.spotify.com/v1/search?q=\(searchQuery)&type=track&market=JP&limit=20"

        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken ?? "")", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let tracks = parseSearchResults(data: data)
            await MainActor.run {
                self.searchResults = tracks
                self.isSearching = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Search failed: \(error.localizedDescription)"
                self.isSearching = false
            }
        }
    }

    private func parseSearchResults(data: Data) -> [SpotifyTrack] {
        var tracks: [SpotifyTrack] = []

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tracksData = json["tracks"] as? [String: Any],
               let items = tracksData["items"] as? [[String: Any]] {

                for item in items {
                    guard let id = item["id"] as? String,
                          let name = item["name"] as? String,
                          let uri = item["uri"] as? String else { continue }

                    let artists = item["artists"] as? [[String: Any]] ?? []
                    let artistName = artists.first?["name"] as? String ?? "Unknown Artist"

                    let album = item["album"] as? [String: Any] ?? [:]
                    let albumName = album["name"] as? String ?? "Unknown Album"
                    let images = album["images"] as? [[String: Any]] ?? []
                    let imageURL = images.first?["url"] as? String

                    let previewURL = item["preview_url"] as? String

                    let track = SpotifyTrack(
                        id: id,
                        name: name,
                        artist: artistName,
                        albumName: albumName,
                        albumImageURL: imageURL,
                        previewURL: previewURL,
                        spotifyURI: uri
                    )
                    tracks.append(track)
                }
            }
        } catch {
            print("Parse error: \(error)")
        }

        return tracks
    }

    // MARK: - Playback (Preview only with Client Credentials)

    func playPreview(track: SpotifyTrack) {
        guard let previewURLString = track.previewURL,
              let url = URL(string: previewURLString) else {
            errorMessage = "No preview available for this track. Open in Spotify to listen."
            return
        }

        stopPlayback()

        let playerItem = AVPlayerItem(url: url)
        audioPlayer = AVPlayer(playerItem: playerItem)
        audioPlayer?.play()

        currentTrack = track
        isPlaying = true

        // Listen for when playback ends
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            self?.isPlaying = false
        }
    }

    func stopPlayback() {
        audioPlayer?.pause()
        audioPlayer = nil
        isPlaying = false
    }

    func togglePlayback(track: SpotifyTrack) {
        if currentTrack?.id == track.id && isPlaying {
            stopPlayback()
        } else {
            playPreview(track: track)
        }
    }

    func openInSpotify(track: SpotifyTrack) {
        // Try to open in Spotify app first, fall back to web
        if let spotifyURL = URL(string: track.spotifyURI),
           UIApplication.shared.canOpenURL(spotifyURL) {
            UIApplication.shared.open(spotifyURL)
        } else if let webURL = URL(string: "https://open.spotify.com/track/\(track.id)") {
            UIApplication.shared.open(webURL)
        }
    }
}
