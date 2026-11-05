import SwiftUI
import TextCorrectCore

struct ActionsView: View {
    @Environment(AppState.self) private var appState
    @State private var editing: Action?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if appState.actions.actions.isEmpty {
                ContentUnavailableView(
                    tr("Нет сценариев"),
                    systemImage: "bolt",
                    description: Text(tr("Создайте сценарий для обработки текста."))
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
                            Button(tr("Изменить")) { editing = action }
                            Button(tr("Дублировать")) {
                                do { try appState.actions.duplicate(id: action.id) }
                                catch { errorMessage = error.localizedDescription }
                            }
                            Button(tr("Удалить"), role: .destructive) {
                                do { try appState.actions.remove(id: action.id) }
                                catch { errorMessage = error.localizedDescription }
                            }
                        }
                    }
                }
            }
        }
        .alert(tr("Не удалось сохранить сценарии"), isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .toolbar {
            ToolbarItem {
                Button { editing = Action(name: tr("Новый сценарий")) } label: {
                    Label(tr("Добавить"), systemImage: "plus")
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

    private let original: Action

    @State private var name: String
    @State private var description: String
    @State private var mode: Action.Mode
    @State private var systemPrompt: String
    @State private var providerID: UUID?
    @State private var modelID: String
    @State private var requiresSelection: Bool
    @State private var shortcut: KeyCombination?
    @State private var errorMessage: String?

    /// Copies the saved scenario into an editable form.
    init(action: Action) {
        self.original = action
        _description = State(initialValue: action.description ?? "")
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
                TextField(tr("Название"), text: $name)
                TextField(tr("Описание"), text: $description)
                Picker(tr("Режим"), selection: $mode) {
                    Text("Transform").tag(Action.Mode.transform)
                    Text("Chat").tag(Action.Mode.chat)
                }
                Picker(tr("Провайдер"), selection: $providerID) {
                    Text("—").tag(UUID?.none)
                    ForEach(appState.providers.providers) { provider in
                        Text(provider.name).tag(UUID?.some(provider.id))
                    }
                }
                if let provider = appState.providers.providers.first(where: { $0.id == providerID }) {
                    Picker(tr("Модель"), selection: $modelID) {
                        Text(tr("Ввести вручную")).tag("")
                        ForEach(Array(Set(provider.models + (modelID.isEmpty ? [] : [modelID]))).sorted(), id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }
                TextField("Model ID", text: $modelID)
                Toggle(tr("Требует выделенный текст"), isOn: $requiresSelection)
                Section(tr("Системный промпт")) {
                    TextEditor(text: $systemPrompt)
                        .frame(minHeight: 110)
                }
                HotkeyRecorderView(label: tr("Хоткей"), shortcut: $shortcut)
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
                Button(tr("Отмена")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(tr("Сохранить")) { save() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 540, height: 480)
    }

    /// Saves the scenario while preserving its identity and creation date.
    private func save() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = tr("Введите название сценария.")
            return
        }
        var action = original
        action.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        action.description = description.isEmpty ? nil : description
        action.mode = mode
        action.systemPrompt = systemPrompt
        action.providerID = providerID
        action.modelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        action.requiresSelection = requiresSelection
        action.shortcut = shortcut
        action.updatedAt = Date()
        do {
            try appState.upsertAction(action)
            dismiss()
        } catch {
            errorMessage = (error as? HotkeyError)?.message ?? error.localizedDescription
        }
    }
}
