import SwiftUI

enum AppTab: Int, CaseIterable, Identifiable {
    case kana = 0
    case kanaPractice
    case vocabulary
    case phrases
    case sentences
    case grammar
    case songs

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .kana: return "Kana"
        case .kanaPractice: return "Practice"
        case .vocabulary: return "Vocab"
        case .phrases: return "Phrases"
        case .sentences: return "Sentences"
        case .grammar: return "Grammar"
        case .songs: return "Songs"
        }
    }

    var icon: String {
        switch self {
        case .kana: return "character.ja"
        case .kanaPractice: return "rectangle.on.rectangle.angled"
        case .vocabulary: return "rectangle.stack"
        case .phrases: return "text.bubble"
        case .sentences: return "text.quote"
        case .grammar: return "book"
        case .songs: return "music.note.list"
        }
    }
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .kana

    var body: some View {
        VStack(spacing: 0) {
            // Content area
            Group {
                switch selectedTab {
                case .kana:
                    KanaView()
                case .kanaPractice:
                    KanaFlashcardView()
                case .vocabulary:
                    FlashcardView()
                case .phrases:
                    PhrasesView()
                case .sentences:
                    SentencesView()
                case .grammar:
                    GrammarView()
                case .songs:
                    SongsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom scrollable tab bar
            ScrollableTabBar(selectedTab: $selectedTab)
        }
        .edgesIgnoringSafeArea(.bottom)
    }
}

struct ScrollableTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(AppTab.allCases) { tab in
                        TabBarButton(
                            tab: tab,
                            isSelected: selectedTab == tab,
                            action: { selectedTab = tab }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 49)
            .background(Color(UIColor.secondarySystemBackground))
            .padding(.bottom, getSafeAreaBottom())
            .background(Color(UIColor.secondarySystemBackground))
        }
    }

    func getSafeAreaBottom() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        let window = windowScene?.windows.first
        return window?.safeAreaInsets.bottom ?? 0
    }
}

struct TabBarButton: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20))
                Text(tab.title)
                    .font(.caption2)
            }
            .foregroundColor(isSelected ? .red : .gray)
            .frame(width: 70, height: 49)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
