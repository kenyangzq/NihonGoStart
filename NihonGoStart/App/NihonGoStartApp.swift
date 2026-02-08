import SwiftUI
import WidgetKit

@main
struct NihonGoStartApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Sync flashcard data to widget on app launch
                    WidgetDataProvider.shared.syncDataFromApp()
                    WidgetCenter.shared.reloadAllTimelines()
                }
        }
    }
}
