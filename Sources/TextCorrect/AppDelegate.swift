import AppKit
import SwiftUI
import TextCorrectCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var appState = AppState()
    private var menuBar: MenuBarController?
    private var hotkeys: HotkeyManager?
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBar = MenuBarController { [weak self] action in
            self?.handle(action)
        }
        hotkeys = HotkeyManager()
        registerHotkeys()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func handle(_ action: MenuBarController.Action) {
        switch action {
        case .openMain: showMainWindow()
        case .openPalette: break // Этап 2
        case .captureScreen: break // Этап 4
        case .quit: NSApp.terminate(nil)
        }
    }

    private func registerHotkeys() {
        guard let hotkeys else { return }
        if let universal = appState.settings.settings.universalShortcut {
            hotkeys.register(universal) { /* Этап 2: открыть AI-панель */ }
        }
    }

    private func showMainWindow() {
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TextCorrect"
        window.center()
        window.contentView = NSHostingView(rootView: MainWindowView().environment(appState))
        window.isReleasedWhenClosed = false
        mainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
