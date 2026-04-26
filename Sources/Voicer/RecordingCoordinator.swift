import Foundation
import AVFoundation

final class RecordingCoordinator {
    var onLevel: ((Float) -> Void)?
    var onTranscription: ((String) -> Void)?
    var onRecordingStarted: (() -> Void)?
    var onRecordingStopped: ((String) -> Void)?

    private let fnMonitor = FnKeyMonitor()
    private let audioEngine = AudioEngine()
    private let speechEngine = SpeechEngine()
    private var isRecording = false
    private var lastTranscription = ""

    init() {
        fnMonitor.onPress = { [weak self] in self?.startRecording() }
        fnMonitor.onRelease = { [weak self] in self?.stopRecording() }

        audioEngine.onBuffer = { [weak self] buffer in
            guard let self else { return }
            let level = AudioEngine.rms(buffer: buffer)
            DispatchQueue.main.async { self.onLevel?(level) }
            self.speechEngine.append(buffer: buffer)
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

        let text = speechEngine.stop()
        audioEngine.stop()

        let final = text.isEmpty ? lastTranscription : text
        onRecordingStopped?(final)
    }
}
