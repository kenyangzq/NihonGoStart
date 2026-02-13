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
                .onOpenURL { url in
                    // Handle Spotify OAuth callback
                    handleIncomingURL(url)
                }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        // Check if this is a Spotify callback
        if url.scheme == "nihongostart" {
            // Extract authorization code from URL
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                // Exchange code for token
                Task {
                    await SpotifyManager.shared.exchangeCodeForToken(code: code)
                }
            }
        }
    }
}
