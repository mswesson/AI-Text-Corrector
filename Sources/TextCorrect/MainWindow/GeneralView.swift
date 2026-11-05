import SwiftUI

struct GeneralView: View {
    var body: some View {
        Form {
            Section("Разрешения") {
                ForEach(PermissionManager.Permission.allCases, id: \.self) { permission in
                    PermissionRow(permission: permission)
                }
            }
            Section("О приложении") {
                LabeledContent("Версия", value: "0.1.0")
                LabeledContent("Платформа", value: "macOS 14+, Apple Silicon")
            }
        }
        .formStyle(.grouped)
    }
}

private struct PermissionRow: View {
    let permission: PermissionManager.Permission
    private let manager = PermissionManager()

    @State private var granted: Bool?

    var body: some View {
        HStack {
            Text(permission.title)
            Spacer()
            if let granted {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(granted ? Color.green : Color.orange)
                Text(granted ? "Разрешено" : "Не разрешено")
                    .foregroundStyle(.secondary)
            }
            Button("Настройки…") { manager.openSystemSettings(permission) }
                .buttonStyle(.link)
        }
        .task { granted = manager.isGranted(permission) }
    }
}
