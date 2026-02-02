import SwiftUI
import AVFoundation
import UIKit

struct SongsView: View {
    @StateObject private var spotifyManager = SpotifyManager.shared
    @State private var searchText = ""
    @State private var selectedTrack: SpotifyTrack?
    @State private var showLyricsView = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                SearchBar(text: $searchText, onSearch: {
                    Task {
                        await spotifyManager.searchJapaneseSongs(query: searchText)
                    }
                })
                .padding()

                if spotifyManager.needsConfiguration {
                    // Spotify not configured
                    VStack(spacing: 20) {
                        Image(systemName: "gearshape.2")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)

                        Text("Setup Required")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("To use the Songs feature, you need to:\n\n1. Go to developer.spotify.com/dashboard\n2. Create an app to get credentials\n3. Add your Client ID and Secret\n   in SpotifyManager.swift")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                            .padding(.horizontal)
                    }
                    .frame(maxHeight: .infinity)
                } else if spotifyManager.isAuthenticating {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Connecting to Spotify...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else if !spotifyManager.isAuthenticated && spotifyManager.accessToken == nil {
                    // Not authenticated yet
                    VStack(spacing: 20) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 60))
                            .foregroundColor(.green)

                        Text("Japanese Songs")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Search and listen to Japanese songs\nwith lyrics to learn the language")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)

                        Button(action: {
                            Task {
                                await spotifyManager.authenticate()
                            }
                        }) {
                            HStack {
                                Image(systemName: "link")
                                Text("Connect to Spotify")
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.green)
                            .cornerRadius(25)
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else if spotifyManager.isSearching {
                    ProgressView("Searching...")
                        .frame(maxHeight: .infinity)
                } else if spotifyManager.searchResults.isEmpty && !searchText.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No songs found")
                            .foregroundColor(.secondary)
                        Text("Try searching for Japanese artists like\nYOASOBI, Ado, or Official髭男dism")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxHeight: .infinity)
                } else if spotifyManager.searchResults.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "music.quarternote.3")
                            .font(.system(size: 50))
                            .foregroundColor(.green.opacity(0.7))

                        Text("Search for Japanese Songs")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Popular artists to try:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            ForEach(["YOASOBI", "Ado", "Official髭男dism", "King Gnu", "米津玄師"], id: \.self) { artist in
                                Button(action: {
                                    searchText = artist
                                    Task {
                                        await spotifyManager.searchJapaneseSongs(query: artist)
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "magnifyingglass")
                                            .font(.caption)
                                        Text(artist)
                                    }
                                    .foregroundColor(.green)
                                }
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    // Search Results
                    List(spotifyManager.searchResults) { track in
                        SongRowView(
                            track: track,
                            isPlaying: spotifyManager.currentTrack?.id == track.id && spotifyManager.isPlaying,
                            onPlay: {
                                spotifyManager.togglePlayback(track: track)
                            },
                            onLyrics: {
                                selectedTrack = track
                                showLyricsView = true
                            },
                            onOpenSpotify: {
                                spotifyManager.openInSpotify(track: track)
                            }
                        )
                    }
                    .listStyle(.plain)
                }

                // Now Playing Bar
                if let currentTrack = spotifyManager.currentTrack, spotifyManager.isPlaying {
                    NowPlayingBar(
                        track: currentTrack,
                        onStop: { spotifyManager.stopPlayback() },
                        onLyrics: {
                            selectedTrack = currentTrack
                            showLyricsView = true
                        }
                    )
                }

                // Error Message
                if let error = spotifyManager.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                }
            }
            .navigationTitle("Songs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            .sheet(isPresented: $showLyricsView) {
                if let track = selectedTrack {
                    LyricsView(track: track)
                }
            }
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    let onSearch: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search Japanese songs...", text: $text)
                .textFieldStyle(PlainTextFieldStyle())
                .onSubmit {
                    onSearch()
                }

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }

            Button(action: onSearch) {
                Text("Search")
                    .foregroundColor(.green)
                    .fontWeight(.medium)
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
    }
}

struct SongRowView: View {
    let track: SpotifyTrack
    let isPlaying: Bool
    let onPlay: () -> Void
    let onLyrics: () -> Void
    let onOpenSpotify: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Album Art
            AsyncImage(url: URL(string: track.albumImageURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.gray)
                    )
            }
            .frame(width: 56, height: 56)
            .cornerRadius(8)

            // Song Info
            VStack(alignment: .leading, spacing: 4) {
                Text(track.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(track.artist)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Action Buttons
            HStack(spacing: 8) {
                // Play/Preview Button
                Button(action: onPlay) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(track.previewURL != nil ? .green : .gray)
                }
                .disabled(track.previewURL == nil)

                // Lyrics Button
                Button(action: onLyrics) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 18))
                        .foregroundColor(.purple)
                        .frame(width: 36, height: 36)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(8)
                }

                // Open in Spotify
                Button(action: onOpenSpotify) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct NowPlayingBar: View {
    let track: SpotifyTrack
    let onStop: () -> Void
    let onLyrics: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: track.albumImageURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
            .frame(width: 40, height: 40)
            .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Playing animation
            HStack(spacing: 2) {
                ForEach(0..<3) { i in
                    SoundBar(delay: Double(i) * 0.1)
                }
            }

            Button(action: onLyrics) {
                Image(systemName: "text.alignleft")
                    .foregroundColor(.purple)
            }

            Button(action: onStop) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemBackground))
    }
}

struct SoundBar: View {
    let delay: Double
    @State private var height: CGFloat = 4

    var body: some View {
        Rectangle()
            .fill(Color.green)
            .frame(width: 3, height: height)
            .cornerRadius(1.5)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.4)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    height = 16
                }
            }
    }
}

struct LyricsView: View {
    let track: SpotifyTrack
    @StateObject private var spotifyManager = SpotifyManager.shared
    @State private var lyrics: [LyricLine] = []
    @State private var isLoadingLyrics = true
    @State private var lyricsInput = ""
    @State private var showLyricsInput = false
    @State private var expandedLineId: UUID?
    @Environment(\.dismiss) private var dismiss
    private let speechManager = SpeechManager.shared

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Track Header
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: track.albumImageURL ?? "")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.name)
                            .font(.headline)
                            .lineLimit(2)
                        Text(track.artist)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Play Button
                    Button(action: {
                        spotifyManager.togglePlayback(track: track)
                    }) {
                        Image(systemName: spotifyManager.currentTrack?.id == track.id && spotifyManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(track.previewURL != nil ? .green : .gray)
                    }
                    .disabled(track.previewURL == nil)
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))

                if isLoadingLyrics && lyrics.isEmpty {
                    VStack(spacing: 16) {
                        if showLyricsInput {
                            // Lyrics input area
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Paste Lyrics")
                                    .font(.headline)

                                Text("Copy lyrics from a lyrics website and paste them below. Each line will be displayed separately.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                TextEditor(text: $lyricsInput)
                                    .frame(height: 200)
                                    .padding(8)
                                    .background(Color(UIColor.tertiarySystemBackground))
                                    .cornerRadius(8)

                                Button(action: {
                                    parseLyrics()
                                }) {
                                    HStack {
                                        Image(systemName: "checkmark.circle.fill")
                                        Text("Load Lyrics")
                                    }
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.purple)
                                    .cornerRadius(10)
                                }
                            }
                            .padding()
                        } else {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 50))
                                .foregroundColor(.purple.opacity(0.5))

                            Text("No Lyrics Available")
                                .font(.headline)

                            Text("Lyrics are not automatically available.\nYou can paste lyrics manually.")
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                                .font(.caption)

                            Button(action: { showLyricsInput = true }) {
                                HStack {
                                    Image(systemName: "doc.on.clipboard")
                                    Text("Paste Lyrics")
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.purple)
                                .cornerRadius(20)
                            }

                            Text("Tip: Search for \"\(track.name) lyrics\" online")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.top, 8)
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    // Lyrics Display
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(lyrics) { line in
                                LyricLineView(
                                    line: line,
                                    isExpanded: expandedLineId == line.id,
                                    onTap: {
                                        withAnimation {
                                            if expandedLineId == line.id {
                                                expandedLineId = nil
                                            } else {
                                                expandedLineId = line.id
                                            }
                                        }
                                    },
                                    onSpeak: {
                                        speechManager.speak(line.japanese, rate: 0.7)
                                    }
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if !lyrics.isEmpty {
                        Button(action: { showLyricsInput = true }) {
                            Image(systemName: "square.and.pencil")
                        }
                    }
                }
            }
            .onAppear {
                // Simulate loading - in a real app, you'd fetch from a lyrics API
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isLoadingLyrics = false
                }
            }
        }
    }

    func parseLyrics() {
        let lines = lyricsInput.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        lyrics = lines.map { line in
            LyricLine(
                japanese: line,
                romaji: nil,
                translation: nil,
                timestamp: nil
            )
        }

        showLyricsInput = false
        isLoadingLyrics = false
    }

}

struct LyricLineView: View {
    let line: LyricLine
    let isExpanded: Bool
    let onTap: () -> Void
    let onSpeak: () -> Void
    @State private var generatedRomaji: String?
    @State private var generatedTranslation: String?
    @State private var isGenerating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(line.japanese)
                    .font(.system(size: 18, design: .serif))

                Spacer()

                // Speak button
                Button(action: onSpeak) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Circle().fill(Color.purple))
                }
                .buttonStyle(PlainButtonStyle())

                // Expand/collapse indicator
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let romaji = line.romaji ?? generatedRomaji {
                        HStack {
                            Text("Romaji:")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.purple)
                            Text(romaji)
                                .font(.caption)
                                .italic()
                        }
                    }

                    if let translation = line.translation ?? generatedTranslation {
                        HStack {
                            Text("English:")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.blue)
                            Text(translation)
                                .font(.caption)
                        }
                    }

                    if (line.romaji == nil && generatedRomaji == nil) ||
                       (line.translation == nil && generatedTranslation == nil) {

                        Text("Tap buttons below to get pronunciation & translation")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)

                        HStack(spacing: 12) {
                            if line.romaji == nil && generatedRomaji == nil {
                                Button(action: {
                                    // Generate basic romaji (simplified - would use a proper API in production)
                                    generatedRomaji = generateBasicRomaji(line.japanese)
                                }) {
                                    HStack {
                                        Image(systemName: "textformat")
                                        Text("Romaji")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.purple)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.purple.opacity(0.1))
                                    .cornerRadius(15)
                                }
                            }

                            if line.translation == nil && generatedTranslation == nil {
                                Button(action: {
                                    // Placeholder - would use translation API in production
                                    generatedTranslation = "[Translation would appear here with a translation API]"
                                }) {
                                    HStack {
                                        Image(systemName: "globe")
                                        Text("Translate")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(15)
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(8)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }

        Divider()
    }

    // Basic romaji generation (simplified - for demo purposes)
    func generateBasicRomaji(_ japanese: String) -> String {
        // This is a very simplified conversion
        // In a real app, you'd use a proper Japanese text processing library or API
        let hiraganaToRomaji: [Character: String] = [
            "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
            "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
            "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so",
            "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
            "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
            "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
            "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
            "や": "ya", "ゆ": "yu", "よ": "yo",
            "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
            "わ": "wa", "を": "wo", "ん": "n",
            "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
            "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
            "だ": "da", "ぢ": "di", "づ": "du", "で": "de", "ど": "do",
            "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
            "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
            "っ": "", "ー": "-",
            " ": " ", "、": ", ", "。": ". "
        ]

        var result = ""
        for char in japanese {
            if let romaji = hiraganaToRomaji[char] {
                result += romaji
            } else {
                // Keep kanji and katakana as-is (would need proper conversion)
                result += String(char)
            }
        }
        return result.isEmpty ? "[Romaji generation requires kanji dictionary]" : result
    }
}
