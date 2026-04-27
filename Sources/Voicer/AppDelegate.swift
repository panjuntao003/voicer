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
        menuBar.onLanguageChange = { [weak self] id in
            self?.coordinator.updateLanguage(id)
        }

        coordinator.updateLanguage(AppSettings.shared.language)

        coordinator.onRecordingStarted = { [weak self] in
            self?.panel.showRecording()
        }

        coordinator.onLevel = { [weak self] level in
            self?.panel.updateLevel(level)
        }

        coordinator.onTranscription = { [weak self] text in
            self?.panel.updateTranscription(text)
        }

        coordinator.onRecordingStopped = { [weak self] rawText in
            guard let self else { return }
            let settings = AppSettings.shared

            if settings.llmEnabled && !settings.llmAPIKey.isEmpty && !rawText.isEmpty {
                panel.showRefining()
                let config = LLMClient.Config(
                    baseURL: settings.llmBaseURL,
                    apiKey: settings.llmAPIKey,
                    model: settings.llmModel
                )
                refinementTask?.cancel()
                refinementTask = Task {
                    let refined = (try? await self.llmClient.refine(text: rawText, config: config)) ?? rawText
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        self.panel.updateTranscription(refined)
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
