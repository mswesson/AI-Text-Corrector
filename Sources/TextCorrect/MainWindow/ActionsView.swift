import SwiftUI
import TextCorrectCore

struct ActionsView: View {
    @Environment(AppState.self) private var appState
    @State private var editing: Action?

    var body: some View {
        VStack(spacing: 0) {
            if appState.actions.actions.isEmpty {
                ContentUnavailableView(
                    "Нет сценариев",
                    systemImage: "bolt",
                    description: Text("Создайте сценарий для обработки текста.")
                )
            } else {
                List {
                    ForEach(appState.actions.actions) { action in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(action.name)
                                Text(action.mode == .transform ? "Transform" : "Chat")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let shortcut = action.shortcut {
                                Text(shortcut.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { editing = action }
                        .contextMenu {
                            Button("Изменить") { editing = action }
                            Button("Дублировать") { try? appState.actions.duplicate(id: action.id) }
                            Button("Удалить", role: .destructive) {
                                try? appState.actions.remove(id: action.id)
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button { editing = Action(name: "Новый сценарий") } label: {
                    Label("Добавить", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editing) { action in
            ActionEditorView(action: action)
        }
    }
}

private struct ActionEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private let actionID: UUID

    @State private var name: String
    @State private var mode: Action.Mode
    @State private var systemPrompt: String
    @State private var providerID: UUID?
    @State private var modelID: String
    @State private var requiresSelection: Bool
    @State private var shortcut: KeyCombination?
    @State private var errorMessage: String?

    init(action: Action) {
        self.actionID = action.id
        _name = State(initialValue: action.name)
        _mode = State(initialValue: action.mode)
        _systemPrompt = State(initialValue: action.systemPrompt)
        _providerID = State(initialValue: action.providerID)
        _modelID = State(initialValue: action.modelID)
        _requiresSelection = State(initialValue: action.requiresSelection)
        _shortcut = State(initialValue: action.shortcut)
    }

    var body: some View {
        VStack {
            Form {
                TextField("Название", text: $name)
                Picker("Режим", selection: $mode) {
                    Text("Transform").tag(Action.Mode.transform)
                    Text("Chat").tag(Action.Mode.chat)
                }
                Picker("Провайдер", selection: $providerID) {
                    Text("—").tag(UUID?.none)
                    ForEach(appState.providers.providers) { provider in
                        Text(provider.name).tag(UUID?.some(provider.id))
                    }
                }
                TextField("Model ID", text: $modelID)
                Toggle("Требует выделенный текст", isOn: $requiresSelection)
                Section("Системный промпт") {
                    TextEditor(text: $systemPrompt)
                        .frame(minHeight: 110)
                }
                HotkeyRecorderView(label: "Хоткей", shortcut: $shortcut)
            }
            .formStyle(.grouped)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            HStack {
                Spacer()
                Button("Отмена") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Сохранить") { save() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 540, height: 480)
    }

    private func save() {
        var action = Action(
            id: actionID,
            name: name,
            mode: mode,
            systemPrompt: systemPrompt,
            providerID: providerID,
            modelID: modelID,
            requiresSelection: requiresSelection
        )
        action.shortcut = shortcut
        do {
            try appState.upsertAction(action)
            dismiss()
        } catch {
            errorMessage = (error as? HotkeyError)?.message ?? error.localizedDescription
        }
    }
}
