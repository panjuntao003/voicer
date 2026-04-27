import AVFoundation

final class AudioEngine {
    let engine = AVAudioEngine()
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    private var isRunning = false
    private var audioFile: AVAudioFile?
    private(set) var recordedFileURL: URL?

    var inputFormat: AVAudioFormat {
        engine.inputNode.outputFormat(forBus: 0)
    }

    func start() throws {
        guard !isRunning else { return }

        // Create temporary file for API transcription
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "voicer_recording_\(UUID().uuidString).m4a"
        let fileURL = tempDir.appendingPathComponent(fileName)
        recordedFileURL = fileURL

        let format = inputFormat
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        audioFile = try AVAudioFile(forWriting: fileURL, settings: settings)

        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.onBuffer?(buffer)
            self?.writeBuffer(buffer)
        }

        try engine.start()
        isRunning = true
    }

    private func writeBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let audioFile else { return }
        do {
            try audioFile.write(from: buffer)
        } catch {
            print("[AudioEngine] Failed to write buffer: \(error)")
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false

        audioFile = nil
        // Note: we keep recordedFileURL so coordinator can use it
    }

    func cleanupRecordedFile() {
        if let url = recordedFileURL {
            try? FileManager.default.removeItem(at: url)
            recordedFileURL = nil
        }
    }

    static func rms(buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        let count = Int(buffer.frameLength)
        for i in 0..<count { sum += data[i] * data[i] }
        return min(sqrt(sum / Float(count)) * 5.0, 1.0)
    }
}
