import SwiftUI

struct SettingsView: View {
    @ObservedObject var appSettings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Dev Mode", isOn: $appSettings.devModeEnabled)
                } header: {
                    Text("Developer Options")
                } footer: {
                    Text("Enables Songs and Comic tabs for testing features in development.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
