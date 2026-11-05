import SwiftUI
import TextCorrectCore

struct AIPaletteView: View {
    let appState: AppState
    let coordinator: InteractionCoordinator
    @Bindable var session: ChatSession
    var initialAction: Action?
    var canReplace = false
    let screenCapture: ScreenCaptureService
    let voice: VoiceInputCoordinator
    var onCapture: (Bool) -> Void
    var onClose: () -> Void
    var onNewSession: () -> Void
    var onReplace: (String) -> String?

    @State private var input = ""
    @State private var result = ""
    @State private var selectedActionID: UUID?
    @State private var selectedProviderID: UUID?
    @State private var selectedModelID: String?
    @State private var replaceError: String?
    @State private var searchText = ""
    @State private var highlightedIndex = 0
    @State private var showCloudConsent = false
    @State private var pendingAction: Action?
    @State private var confirmReset = false

    private var filteredActions: [Action] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return appState.actions.actions }
        return appState.actions.actions.filter { $0.name.lowercased().contains(query) }
    }

    private var firstAvailableIndex: Int {
        filteredActions.firstIndex { !$0.requiresSelection || session.attachedText != nil } ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let attached = session.attachedText, !attached.isEmpty {
                attachedBlock(attached)
            }
            if !session.attachedImages.isEmpty { imageAttachments }
            statusArea
            if !voice.isPushToTalk, voice.phase != .idle {
                HStack {
                    Text(voice.statusText).font(.caption).foregroundStyle(.secondary)
                    if voice.isBusy { Button(tr("Отмена диктовки")) { voice.cancel() } }
                }
            }
            if !result.isEmpty {
                resultEditor
            }
            inputBar
            if result.isEmpty {
                actionList
            }
        }
        .padding(14)
        .frame(minWidth: 520, minHeight: 300)
        .onExitCommand(perform: onClose)
        .task { if let initialAction { run(initialAction) } }
        .onChange(of: result) {
            session.editedResponse = result
            if session.mode == .transform { session.draft = result }
        }
        .alert(tr("Отправка в облачный AI"), isPresented: $showCloudConsent) {
            Button(tr("Разрешить")) {
                appState.settings.settings.hasShownCloudConsent = true
                try? appState.settings.save()
                if let action = pendingAction { run(action) } else { send() }
                pendingAction = nil
            }
            Button(tr("Отмена"), role: .cancel) { pendingAction = nil }
        } message: {
            Text(tr("Запрос, прикреплённый текст и изображения будут отправлены выбранному облачному провайдеру."))
        }
        .alert(tr("Завершить сессию?"), isPresented: $confirmReset) {
            Button(tr("Завершить"), role: .destructive, action: onNewSession)
            Button(tr("Отмена"), role: .cancel) {}
        } message: {
            Text(tr("Ручные правки будут удалены. При необходимости скопируйте результат."))
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "sparkles").foregroundStyle(.tint)
            Text("TextCorrect").font(.headline)
            Spacer()
            Button(tr("Новая сессия")) {
                if session.hasManualEdits { confirmReset = true } else { onNewSession() }
            }
            .disabled(coordinator.isBusy)
            if let provider = currentProvider {
                Menu {
                    ForEach(appState.providers.providers) { item in
                        Section(item.name) {
                            ForEach(item.models, id: \.self) { model in
                                Button(model) {
                                    selectedProviderID = item.id
                                    selectedModelID = model
                                }
                            }
                        }
                    }
                } label: {
                    Text("\(provider.name) · \(currentModelID)").font(.caption)
                }
                .fixedSize()
                .disabled(coordinator.isBusy)
            } else {
                Text(tr("LLM не подключена")).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    /// Displays the selection attached to the next request.
    private func attachedBlock(_ text: String) -> some View {
        HStack(alignment: .top) {
            Image(systemName: "text.quote").foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .lineLimit(3)
                .truncationMode(.middle)
            Spacer()
            Button {
                session.attachedText = nil
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(coordinator.isBusy)
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var statusArea: some View {
        if coordinator.isBusy {
            HStack {
                ProgressView().controlSize(.small)
                Text(tr("Генерация…")).foregroundStyle(.secondary)
                Spacer()
                Button(tr("Отмена")) { coordinator.cancel() }
            }
        } else if case .error(let message) = coordinator.phase {
            Text(message).font(.caption).foregroundStyle(.red)
        } else if let captureError = screenCapture.errorMessage {
            Text(captureError).font(.caption).foregroundStyle(.orange)
        } else if let replaceError {
            Text(replaceError).font(.caption).foregroundStyle(.orange)
        }
    }

    private var resultEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $result)
                .disabled(coordinator.isBusy)
                .font(.body)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button(tr("Копировать")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result, forType: .string)
                }
                if canReplace {
                    Button(tr("Заменить исходное")) {
                        replaceError = onReplace(result)
                    }
                    .disabled(coordinator.isBusy)
                }
                Spacer()
                Button(tr("Скрыть")) { onClose() }
            }
            .font(.caption)
        }
    }

    private var imageAttachments: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(Array(session.attachedImages.enumerated()), id: \.offset) { index, data in
                    if let image = NSImage(data: data) {
                        VStack {
                            Image(nsImage: image)
                                .resizable().scaledToFit()
                                .frame(width: 130, height: 80)
                            Button(tr("Удалить снимок")) { session.attachedImages.remove(at: index) }
                                .font(.caption)
                                .disabled(coordinator.isBusy)
                        }
                    }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom) {
            Menu {
                Button(tr("Снимок экрана")) { onCapture(false) }
                Button(tr("Выбрать область…")) { onCapture(true) }
            } label: {
                Image(systemName: "camera")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(coordinator.isBusy || screenCapture.isCapturing)
            Button {
                if voice.phase == .recording, !voice.isPushToTalk { voice.finishRecording() }
                else { voice.startPalette { text in input += (input.isEmpty ? "" : " ") + text } }
            } label: {
                Image(systemName: voice.phase == .recording && !voice.isPushToTalk ? "stop.circle.fill" : "mic")
            }
            .buttonStyle(.plain)
            .disabled(coordinator.isBusy || (voice.isBusy && (voice.phase != .recording || voice.isPushToTalk)))
            TextField(tr("Запрос или инструкция…"), text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit { send() }
                .disabled(coordinator.isBusy)
            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .disabled((input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && session.attachedImages.isEmpty) || coordinator.isBusy)
        }
    }

    private var actionList: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !appState.actions.actions.isEmpty {
                TextField(tr("Поиск сценария…"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: searchText) { highlightedIndex = firstAvailableIndex }
                    .onSubmit {
                        if filteredActions.indices.contains(highlightedIndex) {
                            run(filteredActions[highlightedIndex])
                        }
                    }
            }
            if appState.actions.actions.isEmpty {
                Text(tr("Сценариев нет — создайте их в настройках."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if filteredActions.isEmpty {
                Text(tr("Ничего не найдено.")).font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(filteredActions.enumerated()), id: \.element.id) { index, action in
                            actionRow(action, isHighlighted: index == highlightedIndex)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
        }
        .onAppear { highlightedIndex = firstAvailableIndex }
        .onChange(of: session.attachedText) { highlightedIndex = firstAvailableIndex }
        .disabled(coordinator.isBusy)
        .onKeyPress(.downArrow) {
            moveHighlight(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveHighlight(by: -1)
            return .handled
        }
    }

    /// Moves keyboard selection to the next scenario that can run with the current context.
    private func moveHighlight(by step: Int) {
        var index = highlightedIndex + step
        while filteredActions.indices.contains(index) {
            if !filteredActions[index].requiresSelection || session.attachedText != nil {
                highlightedIndex = index
                return
            }
            index += step
        }
    }

    /// Displays a searchable scenario and its shortcut.
    private func actionRow(_ action: Action, isHighlighted: Bool) -> some View {
        HStack {
            Image(systemName: action.mode == .transform ? "arrow.2.squarepath" : "bubble.left")
                .foregroundStyle(.secondary)
            Text(action.name)
            Spacer()
            if let shortcut = action.shortcut {
                Text(shortcut.displayName).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(
            isHighlighted ? Color.accentColor.opacity(0.15) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        .opacity(action.requiresSelection && session.attachedText == nil ? 0.5 : 1)
        .onTapGesture { run(action) }
    }

    // MARK: - Logic

    private var currentProvider: Provider? {
        if let selectedProviderID { return appState.providers.provider(byID: selectedProviderID) }
        if let id = selectedActionID,
           let action = appState.actions.action(byID: id),
           let providerID = action.providerID {
            return appState.providers.provider(byID: providerID)
        }
        if let id = appState.settings.settings.preferredProviderID {
            return appState.providers.provider(byID: id)
        }
        return appState.providers.providers.first
    }

    private var currentModelID: String {
        if let selectedModelID { return selectedModelID }
        if let id = selectedActionID,
           let action = appState.actions.action(byID: id),
           !action.modelID.isEmpty {
            return action.modelID
        }
        if selectedActionID != nil { return currentProvider?.models.first ?? "" }
        return appState.settings.settings.preferredModelID ?? currentProvider?.models.first ?? ""
    }

    /// Starts a scenario with the captured selection or entered text.
    private func run(_ action: Action) {
        guard !coordinator.isBusy else { return }
        guard !action.requiresSelection || session.attachedText != nil else {
            replaceError = tr("Для этого сценария выделите текст в исходном приложении.")
            return
        }
        selectedActionID = action.id
        selectedProviderID = nil
        selectedModelID = nil
        session.configure(systemPrompt: action.systemPrompt, mode: action.mode == .transform ? .transform : .chat)
        session.draft = nil
        send(action: action)
    }

    /// Sends the current draft and instruction while preserving input on failure.
    private func send(action: Action? = nil) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !coordinator.isBusy else { return }
        guard !text.isEmpty || !session.attachedImages.isEmpty || (selectedActionID != nil && session.attachedText != nil) else {
            replaceError = tr("Введите запрос или выделите текст.")
            return
        }
        guard let provider = currentProvider, !currentModelID.isEmpty else {
            replaceError = tr("Подключите LLM-провайдера и выберите модель в настройках.")
            return
        }
        guard provider.isLocal || appState.settings.settings.hasShownCloudConsent else {
            pendingAction = action
            showCloudConsent = true
            return
        }
        if action == nil, session.mode == .transform, !result.isEmpty { session.draft = result }
        let model = currentModelID
        replaceError = nil
        Task {
            if let response = await coordinator.send(
                session: session,
                userInput: text,
                provider: provider,
                model: model,
                apiKey: appState.providers.apiKey(for: provider.id)
            ) {
                result = response
                input = ""
            }
        }
    }
}
