import SwiftUI
import AVFoundation

struct GrammarView: View {
    let allGrammar = SeedData.grammar
    @State private var selectedCategory: GrammarCategory = .particles
    let synthesizer = AVSpeechSynthesizer()

    var filteredGrammar: [GrammarPoint] {
        allGrammar.filter { $0.category == selectedCategory }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Category Filter - Horizontal Scroll
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(GrammarCategory.allCases) { category in
                            GrammarCategoryChip(
                                category: category,
                                isSelected: selectedCategory == category,
                                count: allGrammar.filter { $0.category == category }.count,
                                action: { selectedCategory = category }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .background(Color(UIColor.secondarySystemBackground))

                List(filteredGrammar) { point in
                    GrammarRowView(point: point, synthesizer: synthesizer)
                }
                .listStyle(.plain)
            }
            .navigationTitle("Grammar Guide")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct GrammarCategoryChip: View {
    let category: GrammarCategory
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.caption)
                Text(category.displayName)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .bold : .regular)
                Text("\(count)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(isSelected ? .purple : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.3) : Color.gray.opacity(0.2))
                    )
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.purple : Color(UIColor.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.purple.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct GrammarRowView: View {
    let point: GrammarPoint
    let synthesizer: AVSpeechSynthesizer

    var levelColor: Color {
        switch point.level {
        case .n5: return .green
        case .n4: return .blue
        case .n3: return .orange
        case .n2: return .red
        case .n1: return .purple
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(point.title)
                    .font(.headline)
                    .foregroundColor(.purple)
                Spacer()
                Text(point.level.label)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(levelColor)
                    )
            }

            Text(point.description)
                .font(.body)
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("EXAMPLE")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.gray)
                    Spacer()
                    Button(action: {
                        speakJapanese(point.exampleJp)
                    }) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Circle().fill(Color.purple))
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Text(point.exampleJp)
                    .font(.system(.body, design: .serif))
                    .padding(.top, 2)

                Text(point.exampleEn)
                    .font(.caption)
                    .italic()
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(8)
        }
        .padding(.vertical, 8)
    }

    func speakJapanese(_ text: String) {
        // Extract just the Japanese part (before the romaji in parentheses)
        let japanesePart = text.components(separatedBy: " (").first ?? text
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: japanesePart)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.8
        synthesizer.speak(utterance)
    }
}
