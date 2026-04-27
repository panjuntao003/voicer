import Foundation
import AVFoundation

final class RecordingCoordinator {
    var onLevel: ((Float) -> Void)?
    var onTranscription: ((String) -> Void)?
    var onRecordingStarted: (() -> Void)?
    var onRecordingStopped: ((String) -> Void)?
    var onProcessingState: ((String) -> Void)?

    private let fnMonitor = FnKeyMonitor()
    private let audioEngine = AudioEngine()
    private let speechEngine = SpeechEngine()
    private let speechAPIClient = SpeechAPIClient()
    private var isRecording = false
    private var lastTranscription = ""
    private var apiTask: Task<Void, Never>?

    init() {
        fnMonitor.onPress = { [weak self] in self?.startRecording() }
        fnMonitor.onRelease = { [weak self] in self?.stopRecording() }

        audioEngine.onBuffer = { [weak self] buffer in
            guard let self else { return }
            let level = AudioEngine.rms(buffer: buffer)
            DispatchQueue.main.async {
                self.onLevel?(level)
                self.speechEngine.append(buffer: buffer)
            }
        }

        speechEngine.onPartialResult = { [weak self] text in
            self?.lastTranscription = text
            self?.onTranscription?(text)
        }
        speechEngine.onFinalResult = { [weak self] text in
            self?.lastTranscription = text
            self?.onTranscription?(text)
        }
    }

    func start() {
        fnMonitor.start()
    }

    func updateLanguage(_ identifier: String) {
        speechEngine.locale = Locale(identifier: identifier)
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        lastTranscription = ""
        apiTask?.cancel()
        onRecordingStarted?()

        do {
            try audioEngine.start()
            speechEngine.requestAuthorizationAndStart(format: audioEngine.inputFormat)
        } catch {
            print("[RecordingCoordinator] Audio engine error: \(error)")
            isRecording = false
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        let localText = speechEngine.stop()
        audioEngine.stop()

        let finalLocalText = localText.isEmpty ? lastTranscription : localText
        let settings = AppSettings.shared

        // If API speech is enabled and configured, try API transcription
        if settings.speechAPIEnabled && !settings.llmAPIKey.isEmpty,
           let fileURL = audioEngine.recordedFileURL {
            onProcessingState?("正在识别…")

            apiTask = Task { [weak self] in
                guard let self else { return }
                let provider = LLMProvider.provider(named: settings.llmProviderName)
                let baseURL = provider.name == "Custom" ? settings.llmBaseURL : provider.baseURL
                let config = SpeechAPIClient.Config(
                    baseURL: baseURL,
                    apiKey: settings.llmAPIKey,
                    model: settings.speechModel
                )

                let apiText: String
                do {
                    apiText = try await self.speechAPIClient.transcribe(audioFileURL: fileURL, config: config)
                } catch {
                    print("[RecordingCoordinator] Speech API error: \(error)")
                    apiText = finalLocalText
                }

                guard !Task.isCancelled else {
                    self.audioEngine.cleanupRecordedFile()
                    return
                }

                await MainActor.run {
                    self.audioEngine.cleanupRecordedFile()
                    self.onRecordingStopped?(apiText)
                }
            }
        } else {
            audioEngine.cleanupRecordedFile()
            onRecordingStopped?(finalLocalText)
        }
    }
}
