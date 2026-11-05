import SwiftUI
import TextCorrectCore

struct ProvidersView: View {
    @Environment(AppState.self) private var appState
    @State private var editing: Provider?

    var body: some View {
        VStack(spacing: 0) {
            if appState.providers.providers.isEmpty {
                ContentUnavailableView(
                    tr("Нет провайдеров"),
                    systemImage: "server.rack",
                    description: Text(tr("Подключите OpenAI-совместимый API."))
                )
            } else {
                List {
                    ForEach(appState.providers.providers) { provider in
                        VStack(alignment: .leading) {
                            Text(provider.name)
                            Text(provider.baseURL)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { editing = provider }
                        .contextMenu {
                            Button(tr("Изменить")) { editing = provider }
                            Button(tr("Удалить"), role: .destructive) {
                                try? appState.providers.remove(id: provider.id)
                            }
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button { editing = Provider(name: "", baseURL: "") } label: {
                    Label(tr("Добавить"), systemImage: "plus")
                }
            }
        }
        .sheet(item: $editing) { provider in
            ProviderEditorView(provider: provider)
        }
    }
}

private struct ProviderEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private let providerID: UUID

    @State private var name: String
    @State private var baseURL: String
    @State private var apiKey: String
    @State private var models: [String]
    @State private var visionModelIDs: Set<String>
    @State private var newModel = ""
    @State private var status: String?
    @State private var statusIsError = false
    @State private var isBusy = false

    init(provider: Provider) {
        self.providerID = provider.id
        _name = State(initialValue: provider.name)
        _baseURL = State(initialValue: provider.baseURL)
        _apiKey = State(initialValue: "")
        _models = State(initialValue: provider.models)
        _visionModelIDs = State(initialValue: Set(provider.visionModelIDs ?? (provider.supportsVision ? provider.models : [])))
    }

    var body: some View {
        VStack {
            Form {
                TextField(tr("Название"), text: $name)
                TextField("Base URL", text: $baseURL)
                SecureField(tr("API Key (необязательно)"), text: $apiKey)
                Section(tr("Модели")) {
                    ForEach(models, id: \.self) { model in
                        Toggle(model + tr(" · Изображения"), isOn: Binding(
                            get: { visionModelIDs.contains(model) },
                            set: { enabled in
                                if enabled { visionModelIDs.insert(model) }
                                else { visionModelIDs.remove(model) }
                            }
                        ))
                    }
                    HStack {
                        TextField("Model ID", text: $newModel)
                        Button(tr("Добавить")) { addModel() }
                    }
                    Button(tr("Получить модели с сервера")) { Task { await fetchModels() } }
                        .disabled(isBusy)
                }
            }
            .formStyle(.grouped)

            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(statusIsError ? Color.red : Color.secondary)
                    .padding(.horizontal)
            }

            HStack {
                Button(tr("Проверить подключение")) { Task { await test() } }
                    .disabled(isBusy)
                Spacer()
                Button(tr("Отмена")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(tr("Сохранить")) { save() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 560, height: 500)
    }

    private func draftProvider() -> Provider {
        Provider(id: providerID, name: name, baseURL: baseURL, models: models, supportsVision: !visionModelIDs.isEmpty, visionModelIDs: visionModelIDs.sorted())
    }

    private func currentAPIKey() -> String? {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appState.providers.apiKey(for: providerID) : trimmed
    }

    private func addModel() {
        let model = newModel.trimmingCharacters(in: .whitespaces)
        if !model.isEmpty, !models.contains(model) {
            models.append(model)
        }
        newModel = ""
    }

    private func test() async {
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await LLMClient().listModels(draftProvider(), apiKey: currentAPIKey())
            setStatus(tr("Подключение успешно."), error: false)
        } catch {
            setStatus(message(for: error), error: true)
        }
    }

    private func fetchModels() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let list = try await LLMClient().listModels(draftProvider(), apiKey: currentAPIKey())
            models = list
            setStatus(String(format: tr("Получено моделей: %ld."), list.count), error: false)
        } catch {
            setStatus(message(for: error), error: true)
        }
    }

    private func save() {
        do {
            try appState.providers.upsert(draftProvider())
            if let key = currentAPIKey() {
                try appState.providers.setAPIKey(key, for: providerID)
            }
            dismiss()
        } catch {
            setStatus(error.localizedDescription, error: true)
        }
    }

    private func setStatus(_ text: String, error: Bool) {
        status = text
        statusIsError = error
    }

    private func message(for error: Error) -> String {
        (error as? LLMError)?.message ?? error.localizedDescription
    }
}
