import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuBar = MenuBarManager()
    private let coordinator = RecordingCoordinator()
    private let panel = FloatingPanelController()
    private let injector = TextInjector()

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
            panel.hide()
            injector.inject(rawText)
        }

        coordinator.start()
    }
}