import SwiftUI

@main
struct TokenGaugeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @ObservedObject private var localization = LocalizationManager.shared

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(localization.text("about.title")) { appDelegate.showAbout() }
            }
            CommandGroup(replacing: .appSettings) {
                Button(localization.text("settings.title")) { appDelegate.showSettings() }
                    .keyboardShortcut(",")
            }
        }
    }
}
