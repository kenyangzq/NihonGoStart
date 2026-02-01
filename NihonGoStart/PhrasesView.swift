import SwiftUI
import AVFoundation

struct PhrasesView: View {
    @State private var allPhrases = SeedData.phrases
    @State private var selectedCategory: String = "All"
    let synthesizer = AVSpeechSynthesizer()

    var categories: [String] {
        var cats = Array(Set(allPhrases.map { $0.category })).sorted()
        cats.insert("All", at: 0)
        return cats
    }

    var filteredPhrases: [Phrase] {
        if selectedCategory == "All" {
            return allPhrases
        }
        return allPhrases.filter { $0.category == selectedCategory }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Category Filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(categories, id: \.self) { category in
                            CategoryChip(
                                title: category,
                                isSelected: selectedCategory == category,
                                action: { selectedCategory = category }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .background(Color(UIColor.secondarySystemBackground))

                List(filteredPhrases) { phrase in
                    PhraseRow(phrase: phrase, synthesizer: synthesizer)
                }
                .listStyle(.plain)
            }
            .navigationTitle("Common Phrases")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.red : Color(UIColor.systemBackground))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.red.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct PhraseRow: View {
    let phrase: Phrase
    let synthesizer: AVSpeechSynthesizer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(phrase.japanese)
                    .font(.title2)
                    .fontWeight(.medium)

                Spacer()

                Button(action: {
                    speakJapanese(phrase.japanese)
                }) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.body)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.red))
                }
                .buttonStyle(PlainButtonStyle())
            }

            Text(phrase.romaji)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .italic()

            Text(phrase.english)
                .font(.body)
                .foregroundColor(.blue)

            Text(phrase.category.uppercased())
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.red.opacity(0.8))
                )
        }
        .padding(.vertical, 8)
    }

    func speakJapanese(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.8
        synthesizer.speak(utterance)
    }
}
