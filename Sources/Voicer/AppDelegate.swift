import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuBar = MenuBarManager()
    private let coordinator = RecordingCoordinator()
    private let panel = FloatingPanelController()
    private let injector = TextInjector()
    private let llmClient = LLMClient()
    private var refinementTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        menuBar.setup()

        coordinator.onRecordingStarted = { [weak self] in
            self?.panel.showRecording()
        }

        coordinator.onLevel = { [weak self] level in
            self?.panel.updateLevel(level)
        }

        coordinator.onTranscription = { [weak self] text in
            self?.panel.updateTranscription(text)
        }

        coordinator.onProcessingState = { [weak self] message in
            self?.panel.showProcessing(message: message)
        }

        coordinator.onRecordingStopped = { [weak self] rawText in
            guard let self else { return }
            let settings = AppSettings.shared
            let textToInject = rawText.isEmpty ? rawText : rawText

            // Always inject raw text immediately so user sees something
            panel.hide()
            injector.inject(textToInject)

            // If LLM is enabled, refine in background and replace clipboard
            if settings.llmEnabled && !settings.llmAPIKey.isEmpty && !rawText.isEmpty && rawText.count > 5 {
                let provider = LLMProvider.provider(named: settings.llmProviderName)
                let baseURL = provider.name == "Custom" ? settings.llmBaseURL : provider.baseURL
                let config = LLMClient.Config(
                    baseURL: baseURL,
                    apiKey: settings.llmAPIKey,
                    model: settings.llmModel
                )
                refinementTask?.cancel()
                refinementTask = Task {
                    let refined = (try? await self.llmClient.refine(text: rawText, config: config)) ?? rawText
                    guard !Task.isCancelled else { return }
                    // Save refined text to clipboard history and system clipboard
                    ClipboardHistory.shared.add(refined)
                    ClipboardHistory.shared.copyToClipboard(refined)
                }
            }
        }

        coordinator.start()
    }
}