import AppKit
import AVFoundation
import ApplicationServices
import TextCorrectCore

/// Tracks one held chord and recovers from missed release events and sleep.
@MainActor
final class PushToTalkController {
    private let voice: VoiceInputCoordinator
    private var shortcut: KeyCombination?
    private var held = false
    private var started = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    /// Connects held-key events to voice recording and system interruption handling.
    init(voice: VoiceInputCoordinator) {
        self.voice = voice
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.cancel() }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.started, self.voice.phase == .recording else { return }
                self.cancel()
            }
        })
    }

    /// Registers the held shortcut with separate press and release callbacks.
    func register(_ shortcut: KeyCombination, using manager: HotkeyManager) -> Bool {
        if self.shortcut != shortcut { cancel() }
        self.shortcut = shortcut
        return manager.register(shortcut, action: { [weak self] in
            Task { @MainActor in self?.press() }
        }, onRelease: { [weak self] in
            Task { @MainActor in self?.checkRelease() }
        })
    }

    /// Prevents repeat keyDown from creating another recording.
    private func press() {
        guard !held, let shortcut else { return }
        held = true
        started = !voice.isBusy
        if started { voice.startPushToTalk() }
        timer?.invalidate()
        timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkRelease() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        if !CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(shortcut.keyCode)) { checkRelease() }
    }

    /// Ends recording only when the primary key is released, even if modifiers changed first.
    private func checkRelease() {
        guard held, let shortcut else { return }
        if voice.isBusy && (!AXIsProcessTrusted() ||
            (voice.phase == .recording && AVCaptureDevice.authorizationStatus(for: .audio) != .authorized)) {
            cancel()
            return
        }
        guard !CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(shortcut.keyCode)) else { return }
        held = false
        timer?.invalidate()
        timer = nil
        if started { voice.finishRecording() }
        started = false
    }

    /// Stops held-key tracking and cancels work interrupted by sleep or permission changes.
    func cancel() {
        timer?.invalidate()
        timer = nil
        held = false
        if started { voice.cancel() }
        started = false
    }
}
