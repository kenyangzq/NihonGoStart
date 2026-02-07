import Foundation

struct SeedData {
    static var vocabulary: [VocabularyWord] {
        return DataLoader.loadVocabulary()
    }

    static var grammar: [GrammarPoint] {
        return DataLoader.loadGrammar()
    }

    static var kana: [KanaCharacter] {
        return DataLoader.loadKana()
    }

    static var phrases: [Phrase] {
        return DataLoader.loadPhrases()
    }

    static var sentences: [Sentence] {
        return DataLoader.loadSentences()
    }
}
