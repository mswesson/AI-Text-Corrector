import AppKit
import SwiftUI
import Observation
import TextCorrectCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var appState = AppState()
    private lazy var voice = VoiceInputCoordinator(appState: appState)
    private lazy var pushToTalk = PushToTalkController(voice: voice)
    private lazy var voiceOverlay = VoiceOverlayController(voice: voice)
    private lazy var llmClient = LLMClient()
    private lazy var coordinator = InteractionCoordinator(client: llmClient)
    private lazy var palette = AIPaletteController(appState: appState, coordinator: coordinator, voice: voice)
    private var menuBar: MenuBarController?
    private var hotkeys: HotkeyManager?
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        menuBar = MenuBarController { [weak self] action in
            self?.handle(action)
        }
        hotkeys = HotkeyManager()
        appState.shortcutAvailability = { [weak self] combo in
            self?.hotkeys?.isAvailable(combo) ?? false
        }
        registerHotkeys()
        observeShortcuts()
        observeVoice()
        if appState.settings.settings.hasCompletedOnboarding != true { showMainWindow() }
    }

    /// Stops native capture and unregisters shortcuts before application shutdown.
    func applicationWillTerminate(_ notification: Notification) {
        voice.cancel()
        pushToTalk.cancel()
        hotkeys?.unregisterAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func handle(_ action: MenuBarController.Action) {
        switch action {
        case .openMain: showMainWindow()
        case .openPalette: palette.toggle()
        case .captureScreen: palette.captureScreen()
        case .captureRegion: palette.captureScreen(region: true)
        case .quit: NSApp.terminate(nil)
        }
    }

    /// Re-registers the universal shortcut and every scenario after configuration changes.
    private func registerHotkeys() {
        llmClient.timeout = TimeInterval(appState.settings.settings.llmTimeoutSeconds)
        guard let hotkeys else { return }
        hotkeys.unregisterAll()
        var failures: [String] = []
        if let universal = appState.settings.settings.universalShortcut {
            if !hotkeys.register(universal, action: { [weak self] in self?.palette.toggle() }) {
                failures.append(tr("AI-панель"))
            }
        }
        if let capture = appState.settings.settings.captureScreenShortcut {
            if !hotkeys.register(capture, action: { [weak self] in self?.palette.captureScreen() }) {
                failures.append(tr("Захват экрана"))
            }
        }
        if let held = appState.settings.settings.pushToTalkShortcut {
            if !pushToTalk.register(held, using: hotkeys) { failures.append("Push-to-Talk") }
        } else { pushToTalk.cancel() }
        for action in appState.actions.actions {
            guard let combo = action.shortcut else { continue }
            if !hotkeys.register(combo, action: { [weak self] in self?.palette.show(action: action) }) {
                failures.append(action.name)
            }
        }
        appState.hotkeyRegistrationError = failures.isEmpty ? nil : tr("Не удалось зарегистрировать хоткей: ") + failures.joined(separator: ", ")
    }

    /// Tracks persisted shortcut settings and scenario edits without polling.
    private func observeShortcuts() {
        withObservationTracking {
            _ = appState.settings.settings
            _ = appState.actions.actions
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.registerHotkeys()
                self?.observeShortcuts()
            }
        }
    }

    /// Updates the global voice indicator after each phase change.
    private func observeVoice() {
        withObservationTracking {
            _ = voice.phase
            _ = voice.isPushToTalk
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.voiceOverlay.update(voice: self.voice)
                self.observeVoice()
            }
        }
    }

    var settingsView: some View { MainWindowView().environment(appState).environment(voice) }

    /// Reopens the settings UI when the user launches an already-running menu bar app.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }

    /// Reuses a visible settings scene or creates the application's main settings window.
    func showMainWindow() {
        if let window = mainWindow ?? NSApp.windows.first(where: { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }) {
            mainWindow = window
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
        window.contentView = NSHostingView(rootView: settingsView)
        window.isReleasedWhenClosed = false
        mainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
