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

            if settings.llmEnabled && !settings.llmAPIKey.isEmpty && !rawText.isEmpty {
                panel.showProcessing(message: "正在润色…")
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
                    await MainActor.run {
                        self.panel.hide()
                        self.injector.inject(refined)
                    }
                }
            } else {
                panel.hide()
                injector.inject(rawText)
            }
        }

        coordinator.start()
    }
}
