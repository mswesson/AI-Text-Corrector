import SwiftUI

struct MainWindowView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general = "General"
        case actions = "Actions"
        case providers = "AI Providers"
        case speech = "Speech Models"
        case voice = "Voice Input"
        case shortcuts = "Shortcuts"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .actions: return "bolt"
            case .providers: return "server.rack"
            case .speech: return "waveform"
            case .voice: return "mic"
            case .shortcuts: return "keyboard"
            }
        }
    }

    @State private var selection: Section = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(Section.allCases) { section in
                    Label(section.rawValue, systemImage: section.icon).tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 200)
        } detail: {
            switch selection {
            case .general: GeneralView()
            case .actions: ActionsView()
            case .providers: ProvidersView()
            case .speech: SpeechModelsView()
            case .voice: VoiceInputView()
            case .shortcuts: ShortcutsView()
            }
        }
        .frame(minWidth: 720, minHeight: 460)
    }
}
