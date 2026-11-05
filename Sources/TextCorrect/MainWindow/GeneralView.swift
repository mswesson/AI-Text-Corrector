import AppKit
import SwiftUI
import TextCorrectCore

struct GeneralView: View {
    @Environment(AppState.self) private var appState
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var store = appState.settings
        Form {
            Section("LLM") {
                Stepper(String(format: tr("Таймаут: %ld с"), store.settings.llmTimeoutSeconds), value: $store.settings.llmTimeoutSeconds, in: 30...300, step: 10)
            }
            Section(tr("Разрешения")) {
                ForEach(PermissionManager.Permission.allCases, id: \.self) { permission in
                    PermissionRow(permission: permission)
                }
            }
            Section(tr("О приложении")) {
                LabeledContent(tr("Версия"), value: "0.1.0")
                LabeledContent(tr("Платформа"), value: "macOS 14+, Apple Silicon")
            }
        }
        .formStyle(.grouped)
        .onChange(of: store.settings.llmTimeoutSeconds) {
            do { try store.save() } catch { errorMessage = error.localizedDescription }
        }
        .overlay(alignment: .bottom) {
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).padding() }
        }
    }
}

private struct PermissionRow: View {
    let permission: PermissionManager.Permission
    private let manager = PermissionManager()

    @State private var granted: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            permissionControls
            if permission == .accessibility, granted == false {
                Text(tr("Разрешение должно быть выдано этой копии приложения:"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(Bundle.main.bundleURL.path)
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .task {
            while !Task.isCancelled {
                granted = manager.isGranted(permission)
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            granted = manager.isGranted(permission)
        }
    }

    private var permissionControls: some View {
        HStack {
            Text(permission.title)
            Spacer()
            if let granted {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(granted ? Color.green : Color.orange)
                Text(granted ? tr("Разрешено") : tr("Не разрешено"))
                    .foregroundStyle(.secondary)
            }
            Button(tr("Разрешить")) { Task { granted = await manager.request(permission) } }
            Button(tr("Настройки…")) { manager.openSystemSettings(permission) }
                .buttonStyle(.link)
        }
    }
}
