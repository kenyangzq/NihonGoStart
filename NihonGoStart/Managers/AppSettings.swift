import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private static let devModeKey = "devModeEnabled"

    @Published var devModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(devModeEnabled, forKey: Self.devModeKey)
        }
    }

    var visibleTabs: [MainTab] {
        if devModeEnabled {
            return MainTab.allCases
        } else {
            return [.learn]
        }
    }

    private init() {
        self.devModeEnabled = UserDefaults.standard.bool(forKey: Self.devModeKey)
    }
}
