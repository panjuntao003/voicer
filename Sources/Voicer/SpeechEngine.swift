import Speech
import AVFoundation

final class SpeechEngine {
    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var lastTranscription: String = ""

    var locale: Locale = Locale(identifier: "zh-CN") {
        didSet { recognizer = SFSpeechRecognizer(locale: locale) }
    }

    init() {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    func requestAuthorizationAndStart(format: AVAudioFormat) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else { return }
            DispatchQueue.main.async { self?.beginSession(format: format) }
        }
    }

    private func beginSession(format: AVAudioFormat) {
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest,
              let recognizer = recognizer, recognizer.isAvailable else { return }
        request.shouldReportPartialResults = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                self.lastTranscription = text
                if result.isFinal {
                    self.onFinalResult?(text)
                } else {
                    self.onPartialResult?(text)
                }
            }
            if let error, (error as NSError).code != 301 {
                self.onError?(error)
            }
        }
    }

    func append(buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    func stop() -> String {
        recognitionRequest?.endAudio()
        let text = lastTranscription
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        lastTranscription = ""
        return text
    }
}
