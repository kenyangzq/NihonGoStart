import SwiftUI
import UIKit

// Main tabs: Learn, Songs, Comic
enum MainTab: Int, CaseIterable, Identifiable {
    case learn = 0
    case songs
    case comic

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .learn: return "Learn"
        case .songs: return "Songs"
        case .comic: return "Comic"
        }
    }

    var icon: String {
        switch self {
        case .learn: return "book.fill"
        case .songs: return "music.note.list"
        case .comic: return "doc.text.magnifyingglass"
        }
    }
}

// Sub-tabs within Learn
enum LearnSubTab: Int, CaseIterable, Identifiable {
    case kana = 0
    case kanaPractice
    case vocabulary
    case phrases
    case sentences
    case grammar

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .kana: return "Kana"
        case .kanaPractice: return "Practice"
        case .vocabulary: return "Vocab"
        case .phrases: return "Phrases"
        case .sentences: return "Sentences"
        case .grammar: return "Grammar"
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
        }
    }
}

struct ContentView: View {
    @State private var selectedMainTab: MainTab = .learn
    @State private var selectedLearnSubTab: LearnSubTab = .kana
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                // Content area
                Group {
                    switch selectedMainTab {
                    case .learn:
                        // Learn content
                        Group {
                            switch selectedLearnSubTab {
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
                            }
                        }
                    case .songs:
                        SongsView()
                    case .comic:
                        ComicTranslationView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Secondary tab bar for Learn (above main tab bar)
                if selectedMainTab == .learn {
                    LearnSubTabBar(selectedSubTab: $selectedLearnSubTab, showBottomSafeArea: !appSettings.devModeEnabled)
                }

                // Main tab bar (hidden in user mode since only Learn tab exists)
                if appSettings.devModeEnabled {
                    MainTabBar(selectedTab: $selectedMainTab, tabs: appSettings.visibleTabs)
                }
            }

            // Settings gear button
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.gray)
                    .padding(12)
            }
        }
        .edgesIgnoringSafeArea(.bottom)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onChange(of: appSettings.devModeEnabled) {
            if !appSettings.devModeEnabled && selectedMainTab != .learn {
                selectedMainTab = .learn
            }
        }
    }
}

// MARK: - Learn Sub Tab Bar

struct LearnSubTabBar: View {
    @Binding var selectedSubTab: LearnSubTab
    var showBottomSafeArea: Bool = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LearnSubTab.allCases) { tab in
                    LearnSubTabButton(
                        tab: tab,
                        isSelected: selectedSubTab == tab,
                        action: { selectedSubTab = tab }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .padding(.bottom, showBottomSafeArea ? getSafeAreaBottom() : 0)
        .background(Color(UIColor.secondarySystemBackground))
    }

    private func getSafeAreaBottom() -> CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        let window = windowScene?.windows.first
        return window?.safeAreaInsets.bottom ?? 0
    }
}

struct LearnSubTabButton: View {
    let tab: LearnSubTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                Text(tab.title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
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
                    .stroke(isSelected ? Color.clear : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Main Tab Bar

struct MainTabBar: View {
    @Binding var selectedTab: MainTab
    var tabs: [MainTab] = MainTab.allCases

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 0) {
                ForEach(tabs) { tab in
                    MainTabBarButton(
                        tab: tab,
                        selectedTab: $selectedTab
                    )
                }
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

struct MainTabBarButton: View {
    let tab: MainTab
    @Binding var selectedTab: MainTab

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
            .frame(maxWidth: .infinity)
            .frame(height: 49)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
