import AppKit
import SwiftUI
import TextCorrectCore

/// Captures a key combination when clicked.
struct HotkeyRecorderView: View {
    let label: String
    @Binding var shortcut: KeyCombination?

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Button(recording ? "Нажмите клавиши…" : (shortcut?.displayName ?? "Не назначено")) {
                recording.toggle()
                if recording { startMonitoring() } else { stopMonitoring() }
            }
            .buttonStyle(.bordered)
            if shortcut != nil {
                Button("Сбросить") { shortcut = nil }.buttonStyle(.link)
            }
        }
        .onDisappear { stopMonitoring() }
    }

    private func startMonitoring() {
        stopMonitoring()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if let combo = KeyCombination(event: event) {
                self.shortcut = combo
            }
            self.recording = false
            self.stopMonitoring()
            return nil
        }
    }

    private func stopMonitoring() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
