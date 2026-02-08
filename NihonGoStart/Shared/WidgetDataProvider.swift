import Foundation

// MARK: - Widget Card Type

enum WidgetCardType: String, CaseIterable, Codable {
    case kana = "kana"
    case word = "word"
    case phrase = "phrase"

    var displayName: String {
        switch self {
        case .kana: return "Kana"
        case .word: return "Vocabulary"
        case .phrase: return "Phrase"
        }
    }
}

// MARK: - Widget Flashcard Data

struct WidgetFlashcard: Codable {
    let front: String        // Main display (character, kanji, japanese)
    let subtitle: String     // Secondary info (romaji, kana)
    let back: String         // Meaning (romaji/english)
    let category: String     // Group/level/category info
    let cardType: WidgetCardType

    var displayCategory: String {
        switch cardType {
        case .kana: return category       // e.g. "Hiragana - Basic"
        case .word: return category        // e.g. "N5 - Noun"
        case .phrase: return category      // e.g. "Greeting"
        }
    }
}

// MARK: - Widget Data Provider

class WidgetDataProvider {
    static let shared = WidgetDataProvider()
    static let appGroupID = "group.ziqiyang.NihonGoStart"
    static let suiteName = appGroupID

    private let cardTypeKey = "widget_card_type"
    private let currentCardKey = "widget_current_card"
    private let lastUpdateKey = "widget_last_update"
    private let allCardsKey = "widget_all_cards"
    private let showMeaningKey = "widget_show_meaning"

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: WidgetDataProvider.suiteName)
    }

    private init() {}

    /// Force UserDefaults to flush pending writes to disk.
    /// Call before reloadTimelines to ensure the timeline provider reads fresh data.
    func synchronize() {
        sharedDefaults?.synchronize()
    }

    // MARK: - Card Type Selection

    var selectedCardType: WidgetCardType {
        get {
            guard let raw = sharedDefaults?.string(forKey: cardTypeKey),
                  let type = WidgetCardType(rawValue: raw) else {
                return .kana
            }
            return type
        }
        set {
            sharedDefaults?.set(newValue.rawValue, forKey: cardTypeKey)
            // Regenerate cards for the new type and pick a new card
            regenerateCards(for: newValue)
        }
    }

    /// Only updates the card type and regenerates cards when the type actually changes.
    /// Avoids regenerating (and picking a new random card) on every timeline reload.
    func updateCardTypeIfNeeded(_ type: WidgetCardType) {
        let stored = sharedDefaults?.string(forKey: cardTypeKey)
        if stored == nil {
            // First time: persist the type without regenerating a new card
            sharedDefaults?.set(type.rawValue, forKey: cardTypeKey)
            return
        }
        guard type.rawValue != stored else { return }
        // Type has changed: update UserDefaults and regenerate cards
        // Don't use selectedCardType setter to avoid double-regeneration
        sharedDefaults?.set(type.rawValue, forKey: cardTypeKey)
        regenerateCards(for: type)
    }

    // MARK: - Show Meaning State

    var showMeaning: Bool {
        get {
            sharedDefaults?.bool(forKey: showMeaningKey) ?? false
        }
        set {
            sharedDefaults?.set(newValue, forKey: showMeaningKey)
        }
    }

    func toggleShowMeaning() -> Bool {
        let newValue = !showMeaning
        showMeaning = newValue
        return newValue
    }

    // MARK: - Current Card

    func getCurrentCard() -> WidgetFlashcard {
        if let data = sharedDefaults?.data(forKey: currentCardKey),
           let card = try? JSONDecoder().decode(WidgetFlashcard.self, from: data) {
            return card
        }
        // Generate a default card
        let card = generateRandomCard(for: selectedCardType)
        saveCurrentCard(card)
        return card
    }

    func saveCurrentCard(_ card: WidgetFlashcard) {
        if let data = try? JSONEncoder().encode(card) {
            sharedDefaults?.set(data, forKey: currentCardKey)
            sharedDefaults?.set(Date().timeIntervalSince1970, forKey: lastUpdateKey)
        }
    }

    // MARK: - Swap to Next Card

    func swapToNextCard() -> WidgetFlashcard {
        let cards = loadCards(for: selectedCardType)
        guard !cards.isEmpty else {
            return generateRandomCard(for: selectedCardType)
        }

        let currentCard = getCurrentCard()
        // Pick a different random card
        var newCard: WidgetFlashcard
        if cards.count > 1 {
            repeat {
                newCard = cards.randomElement()!
            } while newCard.front == currentCard.front && newCard.back == currentCard.back
        } else {
            newCard = cards[0]
        }

        saveCurrentCard(newCard)
        return newCard
    }

    // MARK: - Data Generation

    func regenerateCards(for type: WidgetCardType) {
        let cards = generateAllCards(for: type)
        if let data = try? JSONEncoder().encode(cards) {
            sharedDefaults?.set(data, forKey: allCardsKey + "_" + type.rawValue)
        }
        // Pick a random card from the new set
        if let card = cards.randomElement() {
            saveCurrentCard(card)
        }
    }

    private func loadCards(for type: WidgetCardType) -> [WidgetFlashcard] {
        let key = allCardsKey + "_" + type.rawValue
        if let data = sharedDefaults?.data(forKey: key),
           let cards = try? JSONDecoder().decode([WidgetFlashcard].self, from: data) {
            return cards
        }
        // Generate and cache
        let cards = generateAllCards(for: type)
        if let data = try? JSONEncoder().encode(cards) {
            sharedDefaults?.set(data, forKey: key)
        }
        return cards
    }

    private func generateRandomCard(for type: WidgetCardType) -> WidgetFlashcard {
        let cards = loadCards(for: type)
        return cards.randomElement() ?? WidgetFlashcard(
            front: "あ",
            subtitle: "",
            back: "a",
            category: "Hiragana - Basic",
            cardType: .kana
        )
    }

    private func generateAllCards(for type: WidgetCardType) -> [WidgetFlashcard] {
        switch type {
        case .kana:
            return generateKanaCards()
        case .word:
            return generateVocabularyCards()
        case .phrase:
            return generatePhraseCards()
        }
    }

    // MARK: - Card Generators

    private func generateKanaCards() -> [WidgetFlashcard] {
        let kana = loadKanaFromBundle()
        return kana.map { k in
            let typeLabel = k.type == "hiragana" ? "Hiragana" : "Katakana"
            let groupLabel = k.group.capitalized
            return WidgetFlashcard(
                front: k.character,
                subtitle: "",
                back: k.romaji,
                category: "\(typeLabel) - \(groupLabel)",
                cardType: .kana
            )
        }
    }

    private func generateVocabularyCards() -> [WidgetFlashcard] {
        let vocab = loadVocabularyFromBundle()
        return vocab.map { v in
            let levelLabel: String
            switch v.level {
            case 1: levelLabel = "N5"
            case 2: levelLabel = "N4"
            case 3: levelLabel = "N3"
            case 4: levelLabel = "N2"
            case 5: levelLabel = "N1"
            default: levelLabel = "N5"
            }
            return WidgetFlashcard(
                front: v.kanji,
                subtitle: v.kana,
                back: v.english,
                category: "\(levelLabel) - \(v.category)",
                cardType: .word
            )
        }
    }

    private func generatePhraseCards() -> [WidgetFlashcard] {
        let phrases = loadPhrasesFromBundle()
        return phrases.map { p in
            WidgetFlashcard(
                front: p.japanese,
                subtitle: p.romaji,
                back: p.english,
                category: p.category,
                cardType: .phrase
            )
        }
    }

    // MARK: - Bundle JSON Loaders (Lightweight Codable structs for widget)

    private struct SimpleKana: Codable {
        let character: String
        let romaji: String
        let type: String
        let row: String
        let group: String
    }

    private struct SimpleVocab: Codable {
        let kanji: String
        let kana: String
        let romaji: String
        let english: String
        let category: String
        let level: Int
    }

    private struct SimplePhrase: Codable {
        let japanese: String
        let romaji: String
        let english: String
        let category: String
    }

    private func loadKanaFromBundle() -> [SimpleKana] {
        guard let url = Bundle.main.url(forResource: "kana", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([SimpleKana].self, from: data) else {
            return []
        }
        return items
    }

    private func loadVocabularyFromBundle() -> [SimpleVocab] {
        guard let url = Bundle.main.url(forResource: "vocabulary", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([SimpleVocab].self, from: data) else {
            return []
        }
        return items
    }

    private func loadPhrasesFromBundle() -> [SimplePhrase] {
        guard let url = Bundle.main.url(forResource: "phrases", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([SimplePhrase].self, from: data) else {
            return []
        }
        return items
    }

    // MARK: - Sync from App

    /// Called from the main app to populate widget data with fresh content
    func syncDataFromApp() {
        let type = selectedCardType
        regenerateCards(for: type)
    }
}
