import SwiftUI
import UIKit

enum AppTab: Int, CaseIterable, Identifiable {
    case kana = 0
    case kanaPractice
    case vocabulary
    case phrases
    case sentences
    case grammar
    case songs
    case comic

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
        case .comic: return "Comic"
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
        case .comic: return "doc.text.magnifyingglass"
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
                case .comic:
                    ComicTranslationView()
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
                            selectedTab: $selectedTab
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
    @Binding var selectedTab: AppTab

    private var isSelected: Bool {
        selectedTab == tab
    }

    var body: some View {
        Button(action: {
            selectedTab = tab
        }) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.red.opacity(0.15) : Color.clear)
                        .frame(width: 36, height: 36)
                    Image(systemName: tab.icon)
                        .font(.system(size: 20))
                }
                .frame(height: 28)

                Text(tab.title)
                    .font(.caption2)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .foregroundColor(isSelected ? .red : .gray)
            .frame(width: 70, height: 49)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
