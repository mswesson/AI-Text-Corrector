import SwiftUI
import TextCorrectCore

/// Guides first launch while allowing AI and speech configuration to be skipped.
struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TextCorrect").font(.largeTitle)
            Text("\(step + 1) / 7").foregroundStyle(.secondary)
            Group {
                switch step {
                case 0:
                    VStack(alignment: .leading, spacing: 12) {
                        Text(tr("AI и диктовка из любого приложения")).font(.title2)
                        Text(tr("Задавайте вопросы, обрабатывайте выделенный текст и снимки экрана. Для локальной диктовки скачайте модель речи; LLM можно подключить позже."))
                    }
                case 1: ShortcutsView()
                case 2: GeneralView()
                case 3: ProvidersView()
                case 4: modelSelection
                case 5: SpeechModelsView()
                default: VoiceInputView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            HStack {
                if step > 0 { Button(tr("Назад")) { step -= 1 } }
                Spacer()
                Button(tr("Настроить позже")) { finish() }
                Button(step == 6 ? tr("Готово") : tr("Далее")) {
                    if step == 6 { finish() } else { step += 1 }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 700, height: 580)
    }

    private var modelSelection: some View {
        @Bindable var store = appState.settings
        return Form {
            Picker(tr("Провайдер по умолчанию"), selection: $store.settings.preferredProviderID) {
                Text(tr("Выбрать позже")).tag(UUID?.none)
                ForEach(appState.providers.providers) { provider in Text(provider.name).tag(UUID?.some(provider.id)) }
            }
            if let provider = appState.providers.providers.first(where: { $0.id == store.settings.preferredProviderID }) {
                Picker(tr("Модель"), selection: $store.settings.preferredModelID) {
                    Text(tr("Первая доступная")).tag(String?.none)
                    ForEach(provider.models, id: \.self) { Text($0).tag(String?.some($0)) }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: store.settings.preferredProviderID) { store.settings.preferredModelID = nil }
    }

    /// Persists completion without requiring a provider, model or permission.
    private func finish() {
        appState.settings.settings.hasCompletedOnboarding = true
        do { try appState.settings.save(); dismiss() }
        catch { errorMessage = error.localizedDescription }
    }
}
