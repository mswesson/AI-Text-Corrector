import AppKit
import SwiftUI
import TextCorrectCore

/// Floating AI panel: input, action list, result editor.
@MainActor
final class AIPaletteController {
    private let appState: AppState
    private let voice: VoiceInputCoordinator
    private let coordinator: InteractionCoordinator
    private let selection = SelectionService()
    private let replacement = TextReplacementService()
    private let screenCapture = ScreenCaptureService()
    private var captureTask: Task<Void, Never>?
    private var session = ChatSession()
    private var panel: NSPanel?
    private var captured: SelectionService.Captured?

    /// Connects the floating panel to shared settings and request execution.
    init(appState: AppState, coordinator: InteractionCoordinator, voice: VoiceInputCoordinator) {
        self.appState = appState
        self.voice = voice
        self.coordinator = coordinator
    }

    /// Hides or reopens the current session.
    func toggle() {
        guard captureTask == nil else { return }
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    /// Opens a scenario or captures a selection for an empty session.
    func show(action: Action? = nil) {
        guard captureTask == nil else { return }
        let incoming = selection.capture()
        if action != nil, session.hasManualEdits {
            let alert = NSAlert()
            alert.messageText = tr("Начать новый сценарий?")
            alert.informativeText = tr("Ручные правки текущего результата будут удалены.")
            alert.addButton(withTitle: tr("Начать"))
            alert.addButton(withTitle: tr("Отмена"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let panel = self.panel ?? makePanel()
        if action != nil || (session.history.isEmpty && session.attachedText == nil && session.attachedImages.isEmpty) {
            coordinator.cancel()
            session.clear()
            captured = incoming
            session.attachedText = captured?.context.originalText
            setContent(panel, action: action)
        }
        self.panel = panel
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) {
            let visible = screen.visibleFrame
            let size = NSSize(width: min(panel.frame.width, visible.width), height: min(panel.frame.height, visible.height))
            panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                                 width: size.width, height: size.height), display: true)
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Adds a screenshot to the current session and returns to the panel without sending it.
    func captureScreen(region: Bool = false) {
        guard captureTask == nil, !coordinator.isBusy else { return }
        if panel == nil { show() }
        panel?.orderOut(nil)
        captureTask = Task {
            defer { captureTask = nil }
            if let image = await screenCapture.capture(region: region) {
                session.attachedImages.append(image)
            }
            panel?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Rebuilds the view for a new in-memory session.
    private func setContent(_ panel: NSPanel, action: Action? = nil) {
        panel.contentView = NSHostingView(rootView: AIPaletteView(
            appState: appState, coordinator: coordinator, session: session,
            initialAction: action, canReplace: captured != nil,
            screenCapture: screenCapture, voice: voice,
            onCapture: { [weak self] region in self?.captureScreen(region: region) },
            onClose: { [weak self] in self?.panel?.orderOut(nil) },
            onNewSession: { [weak self] in
                guard let self, let panel = self.panel else { return }
                self.coordinator.cancel()
                self.session.clear()
                self.captured = nil
                self.setContent(panel)
            },
            onReplace: { [weak self] text in self?.replaceOriginal(text) }
        ))
    }

    /// Creates a floating panel without activating the source application.
    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        return panel
    }

    /// Attempts a validated replacement and keeps failures available for copying.
    private func replaceOriginal(_ text: String) -> String? {
        guard let captured else {
            return tr("Исходный контекст недоступен. Скопируйте результат.")
        }
        let result = replacement.replace(captured, with: text)
        switch result {
        case .replaced:
            panel?.orderOut(nil)
            return nil
        case .failed(let check):
            return "\(check.message) Скопируйте результат вместо замены."
        }
    }
}
