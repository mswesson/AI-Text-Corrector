import SwiftUI
import TextCorrectCore

struct SpeechModelsView: View {
    @Environment(AppState.self) private var appState
    @State private var search = ""
    @State private var language = ""
    @State private var onlyInstalled = false
    @State private var order = "small"
    @State private var errorMessage: String?

    private var models: [SpeechModel] {
        let manager = appState.speechModels
        return manager.catalog.filter {
            (language.isEmpty || $0.languages.contains(language)) &&
            (!onlyInstalled || manager.installed.contains($0.id)) &&
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
        }.sorted {
            if order == "name" { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return order == "large" ? $0.downloadBytes > $1.downloadBytes : $0.downloadBytes < $1.downloadBytes
        }
    }

    var body: some View {
        VStack {
            HStack {
                TextField(tr("Поиск модели…"), text: $search)
                Picker(tr("Язык"), selection: $language) {
                    Text(tr("Все языки")).tag("")
                    ForEach(Array(Set(appState.speechModels.catalog.flatMap(\.languages))).sorted(), id: \.self) { code in
                        Text(Locale.current.localizedString(forLanguageCode: code) ?? code).tag(code)
                    }
                }
                Picker(tr("Порядок"), selection: $order) {
                    Text(tr("Сначала лёгкие")).tag("small")
                    Text(tr("Сначала тяжёлые")).tag("large")
                    Text(tr("По названию")).tag("name")
                }
            }
            Toggle(tr("Только установленные"), isOn: $onlyInstalled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let message = appState.speechModels.errorMessage { Text(message).foregroundStyle(.red) }
            List(models) { model in modelRow(model) }
            if models.isEmpty { Text(tr("Модели не найдены.")).foregroundStyle(.secondary) }
        }
        .padding()
        .alert(tr("Модель речи"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    /// Shows verified catalog metadata and installation controls for one model.
    private func modelRow(_ model: SpeechModel) -> some View {
        let manager = appState.speechModels
        let installed = manager.installed.contains(model.id)
        let active = installed && appState.settings.settings.activeSpeechModelID == model.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(model.name).font(.headline)
                if active { Text(tr("Активна")).foregroundStyle(.tint) }
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: model.downloadBytes, countStyle: .file))
            }
            Text(tr(model.description)).font(.caption).foregroundStyle(.secondary)
            Text("\(model.engine.rawValue) · \(model.license) · \(model.languages.joined(separator: ", "))")
                .font(.caption).foregroundStyle(.secondary)
            let metric = model.benchmarks.first { $0.language == language }
            Text(tr("Точность (WER): ") + (metric?.wer.map { String(format: "%.1f%%", $0) } ?? tr("Нет данных")))
                .font(.caption)
            Text(tr("Скорость (RTFx): ") + (metric?.rtfx.map { String(format: "%.1fx", $0) } ?? tr("Нет данных")))
                .font(.caption)
            HStack {
                if let state = manager.states[model.id] {
                    switch state {
                    case .downloading(let bytes, let total):
                        ProgressView(value: Double(bytes), total: Double(max(total, 1)))
                        Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)).font(.caption)
                        Button(tr("Отмена")) { manager.cancel(model) }
                    case .verifying, .installing:
                        ProgressView().controlSize(.small)
                        Text(state == .verifying ? tr("Проверка SHA-256…") : tr("Установка…"))
                        Button(tr("Отмена")) { manager.cancel(model) }
                    case .failed(let message):
                        Text(message).foregroundStyle(.red).font(.caption)
                        Button(tr("Повторить")) { manager.download(model) }
                    }
                } else if installed {
                    Button(active ? tr("Выбрана") : tr("Выбрать")) {
                        do { try manager.select(model) } catch { errorMessage = error.localizedDescription }
                    }
                    .disabled(active || !manager.inUse.isEmpty)
                    Button(tr("Удалить"), role: .destructive) {
                        do { try manager.remove(model) } catch { errorMessage = error.localizedDescription }
                    }
                    .disabled(active || manager.inUse.contains(model.id))
                } else {
                    Button(tr("Скачать")) { manager.download(model) }
                }
                Spacer()
                Link(tr("Источник"), destination: model.source).font(.caption)
            }
        }
        .padding(.vertical, 6)
    }
}
