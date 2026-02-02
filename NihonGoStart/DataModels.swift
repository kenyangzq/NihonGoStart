import Foundation

enum DifficultyLevel: Int, CaseIterable, Identifiable, Comparable, Codable {
    case n5 = 1 // Beginner
    case n4 = 2 // Elementary
    case n3 = 3 // Intermediate
    case n2 = 4 // Advanced
    case n1 = 5 // Expert
    
    var id: Int { self.rawValue }
    
    var label: String {
        switch self {
        case .n5: return "Beginner (N5)"
        case .n4: return "Elementary (N4)"
        case .n3: return "Intermediate (N3)"
        case .n2: return "Advanced (N2)"
        case .n1: return "Expert (N1)"
        }
    }
    
    static func < (lhs: DifficultyLevel, rhs: DifficultyLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

struct VocabularyWord: Identifiable, Codable {
    var id: UUID = UUID()
    let kanji: String
    let kana: String
    let romaji: String
    let english: String
    let category: String
    let level: DifficultyLevel
    
    private enum CodingKeys: String, CodingKey {
        case kanji, kana, romaji, english, category, level
    }
}

enum GrammarCategory: String, CaseIterable, Identifiable, Codable {
    case particles = "Particles"
    case verbForms = "Verb Forms"
    case adjectives = "Adjectives"
    case tense = "Tense & Aspect"
    case conditionals = "Conditionals"
    case giving = "Giving & Receiving"
    case expressions = "Expressions"
    case honorifics = "Honorifics"
    case comparison = "Comparison"
    case advanced = "Advanced Patterns"

    var id: String { self.rawValue }

    var displayName: String { self.rawValue }

    var icon: String {
        switch self {
        case .particles: return "circle.grid.3x3"
        case .verbForms: return "arrow.triangle.2.circlepath"
        case .adjectives: return "paintbrush"
        case .tense: return "clock"
        case .conditionals: return "arrow.branch"
        case .giving: return "gift"
        case .expressions: return "text.bubble"
        case .honorifics: return "crown"
        case .comparison: return "scale.3d"
        case .advanced: return "star"
        }
    }
}

struct GrammarPoint: Identifiable, Codable {
    var id: UUID = UUID()
    let title: String
    let description: String
    let exampleJp: String
    let exampleEn: String
    let level: DifficultyLevel
    let category: GrammarCategory

    private enum CodingKeys: String, CodingKey {
        case title, description, exampleJp, exampleEn, level, category
    }
}

// MARK: - Kana (Hiragana & Katakana)

enum KanaType: String, CaseIterable, Identifiable, Codable {
    case hiragana
    case katakana

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .hiragana: return "Hiragana"
        case .katakana: return "Katakana"
        }
    }
}

enum KanaGroup: String, CaseIterable, Identifiable, Codable {
    case basic
    case dakuon
    case handakuon
    case combo

    var id: String { self.rawValue }

    var displayName: String {
        switch self {
        case .basic: return "Basic"
        case .dakuon: return "Dakuon (濁音)"
        case .handakuon: return "Handakuon (半濁音)"
        case .combo: return "Combo (拗音)"
        }
    }
}

struct KanaCharacter: Identifiable, Codable {
    var id: UUID = UUID()
    let character: String
    let romaji: String
    let type: KanaType
    let row: String // vowel row (a, ka, sa, ta, na, etc.)
    let group: KanaGroup

    private enum CodingKeys: String, CodingKey {
        case character, romaji, type, row, group
    }
}

// MARK: - Common Phrases

struct Phrase: Identifiable, Codable {
    var id: UUID = UUID()
    let japanese: String
    let romaji: String
    let english: String
    let category: String // Greeting, Polite, Shopping, etc.

    private enum CodingKeys: String, CodingKey {
        case japanese, romaji, english, category
    }
}

// MARK: - Common Sentences

struct Sentence: Identifiable, Codable {
    var id: UUID = UUID()
    let japanese: String
    let romaji: String
    let english: String
    let topic: String // Travel, Restaurant, Work, etc.

    private enum CodingKeys: String, CodingKey {
        case japanese, romaji, english, topic
    }
}

// MARK: - Songs & Lyrics

struct SpotifyTrack: Identifiable {
    let id: String
    let name: String
    let artist: String
    let albumName: String
    let albumImageURL: String?
    let previewURL: String?
    let spotifyURI: String
}

struct LyricLine: Identifiable {
    let id = UUID()
    let japanese: String
    var romaji: String?
    var translation: String?
    let timestamp: Double? // Optional timestamp in seconds
}

struct SavedSong: Identifiable, Codable {
    var id: UUID = UUID()
    let spotifyId: String
    let name: String
    let artist: String
    let albumImageURL: String?
    let lyrics: [SavedLyricLine]

    private enum CodingKeys: String, CodingKey {
        case spotifyId, name, artist, albumImageURL, lyrics
    }
}

struct SavedLyricLine: Identifiable, Codable {
    var id: UUID = UUID()
    let japanese: String
    let romaji: String?
    let translation: String?

    private enum CodingKeys: String, CodingKey {
        case japanese, romaji, translation
    }
}

// MARK: - Comic Translation

struct ExtractedText: Identifiable {
    let id = UUID()
    let japanese: String
    var translation: String
    let boundingBox: CGRect  // For future overlay feature
}
