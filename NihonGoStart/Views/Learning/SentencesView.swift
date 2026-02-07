import SwiftUI
import AVFoundation

struct SentencesView: View {
    @State private var allSentences = SeedData.sentences
    @State private var selectedTopic: String = "All"
    private let speechManager = SpeechManager.shared

    var topics: [String] {
        var topicList = Array(Set(allSentences.map { $0.topic })).sorted()
        topicList.insert("All", at: 0)
        return topicList
    }

    var filteredSentences: [Sentence] {
        if selectedTopic == "All" {
            return allSentences
        }
        return allSentences.filter { $0.topic == selectedTopic }
    }

    var topicIcon: [String: String] {
        [
            "All": "globe",
            "Travel": "airplane",
            "Restaurant": "fork.knife",
            "Work": "briefcase",
            "Shopping": "bag",
            "Social": "person.2",
            "Health": "heart",
            "Daily Life": "house"
        ]
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Topic Filter
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(topics, id: \.self) { topic in
                            TopicChip(
                                title: topic,
                                icon: topicIcon[topic] ?? "text.bubble",
                                isSelected: selectedTopic == topic,
                                action: { selectedTopic = topic }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                }
                .background(Color(UIColor.secondarySystemBackground))

                List(filteredSentences) { sentence in
                    SentenceRow(sentence: sentence, speechManager: speechManager, onTopicTap: { topic in
                        withAnimation {
                            selectedTopic = topic
                        }
                    })
                }
                .listStyle(.plain)
            }
            .navigationTitle("Common Sentences")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct TopicChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .bold : .regular)
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
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

struct SentenceRow: View {
    let sentence: Sentence
    let speechManager: SpeechManager
    let onTopicTap: (String) -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Topic badge
            HStack {
                Button(action: {
                    onTopicTap(sentence.topic)
                }) {
                    HStack(spacing: 4) {
                        Text(sentence.topic.uppercased())
                            .font(.caption2)
                            .fontWeight(.bold)
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.caption2)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(topicColor(sentence.topic))
                    )
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()

                Button(action: {
                    speechManager.speak(sentence.japanese)
                }) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.body)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Circle().fill(Color.red))
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Japanese sentence
            Text(sentence.japanese)
                .font(.title3)
                .fontWeight(.medium)
                .lineLimit(isExpanded ? nil : 2)

            // Romaji
            Text(sentence.romaji)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .italic()
                .lineLimit(isExpanded ? nil : 2)

            // English translation
            Text(sentence.english)
                .font(.body)
                .foregroundColor(.blue)
                .lineLimit(isExpanded ? nil : 2)

            // Expand/Collapse button for long sentences
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                Text(isExpanded ? "Show less" : "Show more")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 10)
    }

    func topicColor(_ topic: String) -> Color {
        switch topic {
        case "Travel": return .blue
        case "Restaurant": return .orange
        case "Work": return .purple
        case "Shopping": return .green
        case "Social": return .pink
        case "Health": return .red
        case "Daily Life": return .teal
        default: return .gray
        }
    }

}
