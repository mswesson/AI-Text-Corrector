import SwiftUI
import TextCorrectCore

@main
struct TextCorrectApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { appDelegate.settingsView }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button(tr("Настройки…")) { appDelegate.showMainWindow() }
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}
