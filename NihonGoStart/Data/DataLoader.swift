import Foundation

class DataLoader {
    static func loadVocabulary() -> [VocabularyWord] {
        guard let url = Bundle.main.url(forResource: "vocabulary", withExtension: "json") else {
            print("❌ Error: vocabulary.json not found in bundle.")
            return []
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let words = try decoder.decode([VocabularyWord].self, from: data)
            print("✅ Successfully loaded \(words.count) words from JSON.")
            return words
        } catch {
            print("❌ Error decoding vocabulary JSON: \(error)")
            return []
        }
    }
    
    static func loadGrammar() -> [GrammarPoint] {
        guard let url = Bundle.main.url(forResource: "grammar", withExtension: "json") else {
            print("❌ Error: grammar.json not found in bundle.")
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let grammar = try decoder.decode([GrammarPoint].self, from: data)
            print("✅ Successfully loaded \(grammar.count) grammar points from JSON.")
            return grammar
        } catch {
            print("❌ Error decoding grammar JSON: \(error)")
            return []
        }
    }

    static func loadKana() -> [KanaCharacter] {
        guard let url = Bundle.main.url(forResource: "kana", withExtension: "json") else {
            print("❌ Error: kana.json not found in bundle.")
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let kana = try decoder.decode([KanaCharacter].self, from: data)
            print("✅ Successfully loaded \(kana.count) kana characters from JSON.")
            return kana
        } catch {
            print("❌ Error decoding kana JSON: \(error)")
            return []
        }
    }

    static func loadPhrases() -> [Phrase] {
        guard let url = Bundle.main.url(forResource: "phrases", withExtension: "json") else {
            print("❌ Error: phrases.json not found in bundle.")
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let phrases = try decoder.decode([Phrase].self, from: data)
            print("✅ Successfully loaded \(phrases.count) phrases from JSON.")
            return phrases
        } catch {
            print("❌ Error decoding phrases JSON: \(error)")
            return []
        }
    }

    static func loadSentences() -> [Sentence] {
        guard let url = Bundle.main.url(forResource: "sentences", withExtension: "json") else {
            print("❌ Error: sentences.json not found in bundle.")
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let sentences = try decoder.decode([Sentence].self, from: data)
            print("✅ Successfully loaded \(sentences.count) sentences from JSON.")
            return sentences
        } catch {
            print("❌ Error decoding sentences JSON: \(error)")
            return []
        }
    }
}
