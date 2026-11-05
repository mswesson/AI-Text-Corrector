import SwiftUI
import TextCorrectCore

struct ShortcutsView: View {
    @Environment(AppState.self) private var appState
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var settings = appState.settings
        Form {
            Section(tr("Глобальные сочетания")) {
                HotkeyRecorderView(label: tr("Универсальная AI-панель"), shortcut: universalBinding)
                HotkeyRecorderView(label: tr("Захват экрана"), shortcut: captureBinding)
                HotkeyRecorderView(label: "Push-to-Talk", shortcut: pushToTalkBinding)
            }
            if let registrationError = appState.hotkeyRegistrationError {
                Text(registrationError).foregroundStyle(.red).font(.caption)
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var universalBinding: Binding<KeyCombination?> {
        Binding(
            get: { appState.settings.settings.universalShortcut },
            set: { apply($0, using: appState.setUniversalShortcut) }
        )
    }

    private var captureBinding: Binding<KeyCombination?> {
        Binding(
            get: { appState.settings.settings.captureScreenShortcut },
            set: { apply($0, using: appState.setCaptureShortcut) }
        )
    }

    private var pushToTalkBinding: Binding<KeyCombination?> {
        Binding(
            get: { appState.settings.settings.pushToTalkShortcut },
            set: { apply($0, using: appState.setPushToTalkShortcut) }
        )
    }

    private func apply(_ combo: KeyCombination?, using setter: (KeyCombination?) throws -> Void) {
        do {
            try setter(combo)
            errorMessage = nil
        } catch {
            errorMessage = (error as? HotkeyError)?.message ?? error.localizedDescription
        }
    }
}
