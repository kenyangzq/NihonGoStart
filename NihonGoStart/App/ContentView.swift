import SwiftUI
import UIKit

// MARK: - App Settings (Dev Mode)

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let devModeKey = "devModeEnabled"

    @Published var isDevModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isDevModeEnabled, forKey: devModeKey)
            // Update visible tabs when dev mode changes
            updateVisibleTabs()
        }
    }

    @Published var showDevModeToast = false
    @Published var visibleTabs: [MainTab] = [.learn]

    private init() {
        isDevModeEnabled = UserDefaults.standard.bool(forKey: devModeKey)
        updateVisibleTabs()
    }

    private func updateVisibleTabs() {
        if isDevModeEnabled {
            visibleTabs = MainTab.allCases
        } else {
            visibleTabs = [.learn]
        }
        print("Dev mode: \(isDevModeEnabled), Visible tabs: \(visibleTabs.map { $0.title })")
    }

    func toggleDevMode() {
        isDevModeEnabled.toggle()

        // Show toast notification
        showDevModeToast = true

        // Hide toast after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.showDevModeToast = false
        }

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }
}

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
    @StateObject private var appSettings = AppSettings.shared

    var body: some View {
        ZStack(alignment: .top) {
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
                    LearnSubTabBar(selectedSubTab: $selectedLearnSubTab)
                }

                // Main tab bar
                MainTabBar(selectedTab: $selectedMainTab)
            }
            .edgesIgnoringSafeArea(.bottom)
            .onChange(of: appSettings.isDevModeEnabled) { _, newValue in
                // Switch to Learn tab if dev mode is disabled and current tab is not visible
                if !newValue && !appSettings.visibleTabs.contains(selectedMainTab) {
                    selectedMainTab = .learn
                }
            }

            // Toast notification (shown when toggling dev mode)
            if appSettings.showDevModeToast {
                ToastNotification(
                    message: appSettings.isDevModeEnabled ? "Dev Mode Enabled" : "Normal Mode",
                    icon: appSettings.isDevModeEnabled ? "hammer.fill" : "eye.slash.fill"
                )
                .padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Dev mode indicator (shown at top when in dev mode)
            if appSettings.isDevModeEnabled {
                DevModeIndicator()
                    .padding(.top, 10)
            }
        }
    }
}

// MARK: - Learn Sub Tab Bar

struct LearnSubTabBar: View {
    @Binding var selectedSubTab: LearnSubTab

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
        .background(Color(UIColor.secondarySystemBackground))
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
    @StateObject private var appSettings = AppSettings.shared

    var isSingleTabMode: Bool {
        appSettings.visibleTabs.count == 1
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 0) {
                ForEach(appSettings.visibleTabs) { tab in
                    MainTabBarButton(
                        tab: tab,
                        selectedTab: $selectedTab,
                        isSingleTabMode: isSingleTabMode
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
    let isSingleTabMode: Bool

    private var isSelected: Bool {
        selectedTab == tab
    }

    @State private var isPressing = false
    @StateObject private var appSettings = AppSettings.shared

    var body: some View {
        ZStack {
            // Progress indicator for long press (only on Learn tab)
            if tab == .learn && isPressing {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.opacity(0.2))
                    .frame(height: 49)
            }

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
                            .scaleEffect(isPressing && tab == .learn ? 1.15 : 1.0)
                    }
                    .frame(height: 28)

                    if !isSingleTabMode {
                        Text(tab.title)
                            .font(.caption2)
                            .fontWeight(isSelected ? .semibold : .regular)
                    }
                }
                .foregroundColor(isSelected ? .red : .gray)
                .frame(maxWidth: .infinity)
                .frame(height: 49)
            }
            .buttonStyle(PlainButtonStyle())
            .onLongPressGesture(minimumDuration: 1.5, pressing: { pressing in
                if tab == .learn {
                    withAnimation(.linear(duration: 0.1)) {
                        isPressing = pressing
                    }
                }
            }, perform: {
                if tab == .learn {
                    isPressing = false
                    appSettings.toggleDevMode()
                }
            })
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressing)
    }
}

// MARK: - Dev Mode Indicator

struct DevModeIndicator: View {
    @StateObject private var appSettings = AppSettings.shared

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hammer.fill")
                .foregroundColor(.white)
            Text("Dev Mode")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Spacer()

            Button(action: {
                withAnimation {
                    appSettings.toggleDevMode()
                }
            }) {
                HStack(spacing: 4) {
                    Text("Exit")
                        .font(.caption)
                        .fontWeight(.medium)
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                }
                .foregroundColor(.white.opacity(0.9))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.9))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Toast Notification

struct ToastNotification: View {
    let message: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.white)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.85))
        )
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 20)
    }
}
