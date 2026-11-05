import SwiftUI
import TextCorrectCore

struct VoiceInputView: View {
    @Environment(AppState.self) private var appState
    @Environment(VoiceInputCoordinator.self) private var voice
    @State private var testText = ""
    @State private var testResult = ""
    @State private var errorMessage: String?
    @State private var testTask: Task<Void, Never>?
    @State private var cloudConsent = false

    var body: some View {
        @Bindable var store = appState.settings
        Form {
            Section(tr("Диктовка")) {
                Text(tr("Скачайте модель в Speech Models. Записи хранятся временно и удаляются после распознавания."))
                    .foregroundStyle(.secondary)
                Text(voice.statusText).font(.caption)
                Button(voice.phase == .recording ? tr("Завершить запись") : tr("Проверить диктовку")) {
                    if voice.phase == .recording { voice.finishRecording() }
                    else { voice.startPalette { testText = $0 } }
                }
                .disabled(voice.isBusy && voice.phase != .recording)
                if voice.isBusy { Button(tr("Отмена")) { voice.cancel() } }
            }
            Section(tr("LLM-постобработка Push-to-Talk")) {
                Toggle(tr("Включить постобработку"), isOn: $store.settings.voicePostProcessingEnabled)
                Picker(tr("Провайдер"), selection: $store.settings.voicePostProcessProviderID) {
                    Text(tr("Не выбран")).tag(UUID?.none)
                    ForEach(appState.providers.providers) { provider in
                        Text(provider.name).tag(UUID?.some(provider.id))
                    }
                }
                if let provider = selectedProvider {
                    Picker(tr("Модель"), selection: $store.settings.voicePostProcessModelID) {
                        Text(tr("Ввести вручную")).tag("")
                        ForEach(Array(Set(provider.models + [store.settings.voicePostProcessModelID])).filter { !$0.isEmpty }.sorted(), id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    if !provider.isLocal && !store.settings.hasShownCloudConsent {
                        Button(tr("Разрешить передачу расшифровки в облако…")) { cloudConsent = true }
                    }
                }
                TextField("Model ID", text: $store.settings.voicePostProcessModelID)
                TextEditor(text: $store.settings.voicePostProcessPrompt).frame(minHeight: 90)
            }
            Section(tr("Тест постобработки")) {
                TextEditor(text: $testText).frame(minHeight: 60)
                HStack {
                    Button(tr("Проверить")) { test() }.disabled(testTask != nil || testText.isEmpty)
                    if testTask != nil { Button(tr("Отмена")) { testTask?.cancel() } }
                }
                if !testResult.isEmpty { Text(testResult).textSelection(.enabled) }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .onChange(of: store.settings) {
            do { try store.save() } catch { errorMessage = error.localizedDescription }
        }
        .onDisappear { testTask?.cancel() }
        .alert(tr("Облачная постобработка"), isPresented: $cloudConsent) {
            Button(tr("Разрешить")) { store.settings.hasShownCloudConsent = true }
            Button(tr("Отмена"), role: .cancel) {}
        } message: { Text(tr("Распознанная речь будет отправляться выбранному облачному LLM-провайдеру, когда включена постобработка.")) }
    }

    private var selectedProvider: Provider? {
        appState.settings.settings.voicePostProcessProviderID.flatMap { appState.providers.provider(byID: $0) }
    }

    /// Runs a manual postprocessing check without inserting its output into another application.
    private func test() {
        let settings = appState.settings.settings
        let provider = selectedProvider
        let text = testText
        errorMessage = nil
        testTask = Task {
            defer { testTask = nil }
            do {
                let processor = VoicePostprocessor(client: LLMClient(timeout: TimeInterval(settings.llmTimeoutSeconds)))
                let result = try await processor.process(text, settings: settings, provider: provider,
                    apiKey: provider.flatMap { appState.providers.apiKey(for: $0.id) })
                if !Task.isCancelled { testResult = result }
            } catch is CancellationError {} catch {
                errorMessage = (error as? LLMError)?.message ?? error.localizedDescription
            }
        }
    }
}
