import TextCorrectCore
import AppKit
import SwiftUI

/// Shows global dictation state without opening the AI palette or stealing its target.
@MainActor
final class VoiceOverlayController {
    private let panel: NSPanel

    /// Creates a nonactivating overlay bound to the current voice operation.
    init(voice: VoiceInputCoordinator) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 180),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.contentView = NSHostingView(rootView: VoiceOverlayView(voice: voice, onClose: { [weak panel] in panel?.orderOut(nil) }))
    }

    /// Displays an indicator only for Push-to-Talk operations.
    func update(voice: VoiceInputCoordinator) {
        guard voice.isPushToTalk, voice.phase != .idle else { panel.orderOut(nil); return }
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 24))
        }
        panel.orderFrontRegardless()
    }
}

private struct VoiceOverlayView: View {
    let voice: VoiceInputCoordinator
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: voice.phase == .recording ? "mic.fill" : "waveform")
                Text(voice.statusText).font(.headline)
                Spacer()
                if voice.isBusy { Button(tr("Отмена")) { voice.cancel() } }
                else { Button(tr("Закрыть"), action: onClose) }
            }
            if !voice.result.isEmpty {
                ScrollView { Text(voice.result).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                HStack {
                    Button(tr("Копировать")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(voice.result, forType: .string)
                    }
                    if case .error = voice.phase {
                        Button(tr("Вставить исходную расшифровку")) { voice.insertRawTranscript() }
                            .disabled(voice.rawTranscript.isEmpty || voice.isBusy)
                    }
                }
                .font(.caption)
            }
        }
        .padding(14)
        .frame(width: 360, height: 180)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

extension VoiceInputCoordinator {
    var statusText: String {
        switch phase {
        case .idle: return tr("Диктовка")
        case .preparing: return tr("Подготовка микрофона…")
        case .recording: return tr("Запись…")
        case .transcribing: return tr("Распознавание…")
        case .postprocessing: return tr("Постобработка…")
        case .inserting: return tr("Вставка…")
        case .completed: return tr("Готово")
        case .error(let message): return message
        }
    }
}
