import SwiftUI

struct SpeechModelsView: View {
    var body: some View {
        ContentUnavailableView(
            "Модели речи",
            systemImage: "waveform",
            description: Text("Каталог локальных STT-моделей появится на этапе 8.")
        )
    }
}

struct VoiceInputView: View {
    var body: some View {
        ContentUnavailableView(
            "Голосовой ввод",
            systemImage: "mic",
            description: Text("Диктовка и Push-to-Talk появятся на этапах 5–7.")
        )
    }
}
