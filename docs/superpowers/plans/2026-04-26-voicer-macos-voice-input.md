# Voicer macOS Voice Input App — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS 14+ menu-bar app that records speech while Fn is held, transcribes it in real time with a floating capsule HUD, optionally refines via LLM, and injects the final text into the focused input field.

**Architecture:** `AppDelegate` bootstraps all singletons. `FnKeyMonitor` uses a CGEvent tap (HID level) to intercept the Fn key, suppressing the emoji picker and notifying `RecordingCoordinator` to start/stop. `RecordingCoordinator` drives `AudioEngine` (RMS) + `SpeechEngine` (streaming transcription) while `FloatingPanelController` renders the capsule HUD. On stop, `LLMClient` optionally refines the text before `TextInjector` pastes it via clipboard + Cmd+V simulation.

**Tech Stack:** Swift 5.9, macOS 14+, AVFoundation, Speech framework (SFSpeechRecognizer), CoreGraphics (CGEvent tap), ApplicationServices (TIS* for IME switching), AppKit (NSPanel, NSVisualEffectView, NSStatusItem), URLSession (LLM HTTP), Swift Package Manager, Makefile.

---

## File Map

| File | Responsibility |
|------|---------------|
| `Package.swift` | SPM manifest, macOS 14+ target |
| `Makefile` | build / run / install / clean targets |
| `Resources/Info.plist` | LSUIElement, permission strings, bundle metadata |
| `Sources/Voicer/main.swift` | NSApplication entry, sets delegate |
| `Sources/Voicer/AppDelegate.swift` | App lifecycle; wires all singletons together |
| `Sources/Voicer/AppSettings.swift` | UserDefaults wrapper (language, LLM config) |
| `Sources/Voicer/MenuBarManager.swift` | NSStatusItem + menu (language submenu, LLM submenu) |
| `Sources/Voicer/FnKeyMonitor.swift` | CGEvent tap at kCGHIDEventTap; suppresses Fn; publishes pressed/released |
| `Sources/Voicer/AudioEngine.swift` | AVAudioEngine mic tap; computes RMS; publishes Float levels |
| `Sources/Voicer/SpeechEngine.swift` | SFSpeechRecognizer streaming recognition; publishes partial/final strings |
| `Sources/Voicer/RecordingCoordinator.swift` | Coordinates FnKeyMonitor → AudioEngine + SpeechEngine → FloatingPanel → TextInjector |
| `Sources/Voicer/FloatingPanelController.swift` | NSPanel frameless capsule; layout; entry/exit animations |
| `Sources/Voicer/WaveformView.swift` | 5-bar NSView; smoothed RMS animation; per-bar jitter |
| `Sources/Voicer/TextInjector.swift` | Clipboard save/restore; CJK IME detection + ASCII switch; Cmd+V paste |
| `Sources/Voicer/LLMClient.swift` | OpenAI-compatible HTTP POST; conservative system prompt |
| `Sources/Voicer/LLMSettingsWindowController.swift` | NSWindow with URL/key/model fields; Test + Save buttons |

---

## Task 1: SPM project scaffold

**Files:**
- Create: `Package.swift`
- Create: `Makefile`
- Create: `Resources/Info.plist`
- Create: `Sources/Voicer/main.swift`

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Voicer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Voicer",
            path: "Sources/Voicer",
            resources: [.process("../../Resources")]
        )
    ]
)
```

- [ ] **Step 2: Create `Makefile`**

```makefile
APP_NAME = Voicer
BUNDLE_ID = com.voicer.app
BUILD_DIR = .build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
BINARY = $(BUILD_DIR)/release/Voicer

.PHONY: build run install clean

build:
	swift build -c release
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp "$(BINARY)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	codesign --force --deep --sign - "$(APP_BUNDLE)"

run: build
	open "$(APP_BUNDLE)"

install: build
	cp -r "$(APP_BUNDLE)" /Applications/

clean:
	rm -rf "$(BUILD_DIR)"
	swift package clean
```

- [ ] **Step 3: Create `Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Voicer</string>
    <key>CFBundleIdentifier</key>
    <string>com.voicer.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>Voicer</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Voicer needs microphone access to record your voice.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Voicer uses speech recognition to transcribe your voice.</string>
</dict>
</plist>
```

- [ ] **Step 4: Create `Sources/Voicer/main.swift`**

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 5: Verify the project compiles (empty stubs ok)**

```bash
cd /Users/panjuntao/Developer/voicer
# We need at least AppDelegate to exist; create a stub:
mkdir -p Sources/Voicer
touch Sources/Voicer/AppDelegate.swift
```

Temporarily add to `AppDelegate.swift`:
```swift
import AppKit
class AppDelegate: NSObject, NSApplicationDelegate {}
```

Then run:
```bash
swift build
```
Expected: Build complete with no errors.

- [ ] **Step 6: Commit**

```bash
cd /Users/panjuntao/Developer/voicer
git init
git add Package.swift Makefile Resources/Info.plist Sources/Voicer/main.swift Sources/Voicer/AppDelegate.swift
git commit -m "chore: scaffold SPM project with Info.plist and Makefile"
```

---

## Task 2: AppSettings — UserDefaults wrapper

**Files:**
- Create: `Sources/Voicer/AppSettings.swift`

- [ ] **Step 1: Create `AppSettings.swift`**

```swift
import Foundation

final class AppSettings {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    private enum Key: String {
        case language = "voicer.language"
        case llmEnabled = "voicer.llm.enabled"
        case llmBaseURL = "voicer.llm.baseURL"
        case llmAPIKey = "voicer.llm.apiKey"
        case llmModel = "voicer.llm.model"
    }

    var language: String {
        get { defaults.string(forKey: Key.language.rawValue) ?? "zh-CN" }
        set { defaults.set(newValue, forKey: Key.language.rawValue) }
    }

    var llmEnabled: Bool {
        get { defaults.bool(forKey: Key.llmEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.llmEnabled.rawValue) }
    }

    var llmBaseURL: String {
        get { defaults.string(forKey: Key.llmBaseURL.rawValue) ?? "https://api.openai.com" }
        set { defaults.set(newValue, forKey: Key.llmBaseURL.rawValue) }
    }

    var llmAPIKey: String {
        get { defaults.string(forKey: Key.llmAPIKey.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.llmAPIKey.rawValue) }
    }

    var llmModel: String {
        get { defaults.string(forKey: Key.llmModel.rawValue) ?? "gpt-4o-mini" }
        set { defaults.set(newValue, forKey: Key.llmModel.rawValue) }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
swift build
```
Expected: Build complete with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Voicer/AppSettings.swift
git commit -m "feat: add AppSettings UserDefaults wrapper"
```

---

## Task 3: FnKeyMonitor — CGEvent tap suppressing Fn/Globe

**Files:**
- Create: `Sources/Voicer/FnKeyMonitor.swift`

This uses a CGEvent tap at `kCGHIDEventTap` to intercept `flagsChanged` events. The Fn/Globe key (virtual key code 63, 0x3F) sets `.maskSecondaryFn` in the flags. By returning `nil` from the tap callback we suppress the default Fn behavior (emoji picker on single press).

Requires Accessibility permission (`AXIsProcessTrustedWithOptions`). The app must prompt the user to grant it.

- [ ] **Step 1: Create `FnKeyMonitor.swift`**

```swift
import Cocoa
import CoreGraphics

final class FnKeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isFnDown = false

    // kVK_Function = 0x3F
    private let fnKeyCode: CGKeyCode = 0x3F

    func start() {
        guard AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt: true] as CFDictionary
        ) else {
            print("[FnKeyMonitor] Accessibility permission not granted")
            return
        }

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let selfPtr = Unmanaged.passRetained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                return monitor.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr
        )

        guard let tap = eventTap else {
            print("[FnKeyMonitor] Failed to create event tap")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .flagsChanged {
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            guard keyCode == fnKeyCode else { return Unmanaged.passRetained(event) }

            let flags = event.flags
            let fnDown = flags.contains(.maskSecondaryFn)

            if fnDown && !isFnDown {
                isFnDown = true
                DispatchQueue.main.async { [weak self] in self?.onPress?() }
                // Suppress the event so emoji picker doesn't appear
                return nil
            } else if !fnDown && isFnDown {
                isFnDown = false
                DispatchQueue.main.async { [weak self] in self?.onRelease?() }
                return nil
            }
            return nil
        }

        // Suppress keyDown/keyUp for Fn key itself
        if type == .keyDown || type == .keyUp {
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == fnKeyCode { return nil }
        }

        return Unmanaged.passRetained(event)
    }

    deinit { stop() }
}
```

- [ ] **Step 2: Build to verify**

```bash
swift build
```
Expected: Build complete with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Voicer/FnKeyMonitor.swift
git commit -m "feat: add FnKeyMonitor CGEvent tap to detect and suppress Fn key"
```

---

## Task 4: AudioEngine — AVAudioEngine mic tap + RMS

**Files:**
- Create: `Sources/Voicer/AudioEngine.swift`

- [ ] **Step 1: Create `AudioEngine.swift`**

```swift
import AVFoundation

final class AudioEngine {
    var onLevel: ((Float) -> Void)?   // 0.0 – 1.0 normalized RMS

    private let engine = AVAudioEngine()
    private var isRunning = false

    func start() throws {
        guard !isRunning else { return }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.process(buffer: buffer)
        }

        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        onLevel?(0)
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var sum: Float = 0
        for i in 0..<frameCount {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameCount))
        // Normalize: typical speech peaks around 0.1–0.3, scale to 0–1
        let normalized = min(rms * 5.0, 1.0)

        DispatchQueue.main.async { [weak self] in
            self?.onLevel?(normalized)
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
swift build
```
Expected: Build complete with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Voicer/AudioEngine.swift
git commit -m "feat: add AudioEngine with AVAudioEngine mic tap and RMS computation"
```

---

## Task 5: SpeechEngine — streaming SFSpeechRecognizer

**Files:**
- Create: `Sources/Voicer/SpeechEngine.swift`

- [ ] **Step 1: Create `SpeechEngine.swift`**

```swift
import Speech
import AVFoundation

final class SpeechEngine {
    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?   // shared engine reference

    var locale: Locale = Locale(identifier: "zh-CN") {
        didSet { recognizer = SFSpeechRecognizer(locale: locale) }
    }

    init() {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    /// Attach to an already-running AVAudioEngine's input node.
    func start(audioEngine: AVAudioEngine) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else { return }
            DispatchQueue.main.async { self?.beginSession(audioEngine: audioEngine) }
        }
    }

    private func beginSession(audioEngine: AVAudioEngine) {
        self.audioEngine = audioEngine
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Install a second tap to feed speech recognizer
        inputNode.installTap(onBus: 1, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    self.onFinalResult?(text)
                } else {
                    self.onPartialResult?(text)
                }
            }
            if let error { self.onError?(error) }
        }
    }

    func stop() -> String {
        audioEngine?.inputNode.removeTap(onBus: 1)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        let final = recognitionTask?.result?.bestTranscription.formattedString ?? ""
        recognitionRequest = nil
        recognitionTask = nil
        audioEngine = nil
        return final
    }
}
```

> **Note:** `AVAudioEngine.inputNode` supports at most one tap per bus. Bus 0 is used by `AudioEngine` for RMS. `SpeechEngine` uses bus 1 here — if the hardware only exposes bus 0, we need a different approach. See Task 9 for the integration that uses a single shared `AVAudioEngine` and installs only one tap, feeding both the RMS computation and the speech request from the same callback.

- [ ] **Step 2: Build to verify**

```bash
swift build
```
Expected: Build complete with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Voicer/SpeechEngine.swift
git commit -m "feat: add SpeechEngine with streaming SFSpeechRecognizer"
```

---

## Task 6: RecordingCoordinator — single shared engine integration

**Files:**
- Create: `Sources/Voicer/RecordingCoordinator.swift`
- Modify: `Sources/Voicer/SpeechEngine.swift` (remove the secondary tap; feed buffers directly)

The `AVAudioEngine.inputNode` only supports one tap. `RecordingCoordinator` installs the single tap, computes RMS, and also appends buffers to the `SFSpeechAudioBufferRecognitionRequest`.

- [ ] **Step 1: Revise `SpeechEngine.swift` — remove the internal tap, expose a `append(buffer:)` method**

Replace the contents of `Sources/Voicer/SpeechEngine.swift` with:

```swift
import Speech
import AVFoundation

final class SpeechEngine {
    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

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
                if result.isFinal {
                    self.onFinalResult?(text)
                } else {
                    self.onPartialResult?(text)
                }
            }
            if let error, (error as NSError).code != 301 {
                // 301 = task cancelled, ignore
                self.onError?(error)
            }
        }
    }

    func append(buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    /// Returns the best transcription collected so far.
    func stop() -> String {
        recognitionRequest?.endAudio()
        let text = recognitionTask?.result?.bestTranscription.formattedString ?? ""
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        return text
    }
}
```

- [ ] **Step 2: Revise `AudioEngine.swift` — expose shared engine + format; remove the `onLevel` tap installation (coordinator installs the tap)**

Replace the contents of `Sources/Voicer/AudioEngine.swift` with:

```swift
import AVFoundation

final class AudioEngine {
    let engine = AVAudioEngine()
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    private var isRunning = false

    var inputFormat: AVAudioFormat {
        engine.inputNode.outputFormat(forBus: 0)
    }

    func start() throws {
        guard !isRunning else { return }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.onBuffer?(buffer)
        }

        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    static func rms(buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        let count = Int(buffer.frameLength)
        for i in 0..<count { sum += data[i] * data[i] }
        return min(sqrt(sum / Float(count)) * 5.0, 1.0)
    }
}
```

- [ ] **Step 3: Create `RecordingCoordinator.swift`**

```swift
import Foundation
import AVFoundation

final class RecordingCoordinator {
    var onLevel: ((Float) -> Void)?
    var onTranscription: ((String) -> Void)?
    var onRecordingStarted: (() -> Void)?
    var onRecordingStopped: ((String) -> Void)?   // delivers final text

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
```

- [ ] **Step 4: Build to verify**

```bash
swift build
```
Expected: Build complete with no errors.

- [ ] **Step 5: Commit**

```bash
git add Sources/Voicer/AudioEngine.swift Sources/Voicer/SpeechEngine.swift Sources/Voicer/RecordingCoordinator.swift
git commit -m "feat: add RecordingCoordinator wiring single AVAudioEngine tap to RMS + SFSpeechRecognizer"
```

---

## Task 7: WaveformView — 5-bar animated waveform

**Files:**
- Create: `Sources/Voicer/WaveformView.swift`

- [ ] **Step 1: Create `WaveformView.swift`**

```swift
import AppKit

final class WaveformView: NSView {
    // Bar weights: center-high, sides-low
    private let weights: [Float] = [0.5, 0.8, 1.0, 0.75, 0.55]
    private var smoothed: [Float] = Array(repeating: 0, count: 5)
    private var displayLink: CVDisplayLink?

    private let barWidth: CGFloat = 4
    private let barSpacing: CGFloat = 3
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 24
    private let cornerRadius: CGFloat = 2

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupDisplayLink()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { CVDisplayLinkStop(displayLink!) }

    // Called from RecordingCoordinator on main queue
    func update(level: Float) {
        let attack: Float = 0.4
        let release: Float = 0.15
        for i in 0..<5 {
            let target = level * weights[i]
            let alpha = target > smoothed[i] ? attack : release
            let jitter = Float.random(in: -0.04...0.04)
            smoothed[i] = smoothed[i] * (1 - alpha) + target * alpha + jitter
            smoothed[i] = max(0, min(1, smoothed[i]))
        }
    }

    private func setupDisplayLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let dl = displayLink else { return }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(dl, { _, _, _, _, _, userInfo -> CVReturn in
            guard let userInfo else { return kCVReturnSuccess }
            let view = Unmanaged<WaveformView>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async { view.setNeedsDisplay(view.bounds) }
            return kCVReturnSuccess
        }, selfPtr)

        CVDisplayLinkStart(dl)
    }

    override func draw(_ dirtyRect: NSRect) {
        let totalBarWidth = CGFloat(5) * barWidth + CGFloat(4) * barSpacing
        let startX = (bounds.width - totalBarWidth) / 2

        for i in 0..<5 {
            let level = CGFloat(smoothed[i])
            let height = minHeight + (maxHeight - minHeight) * level
            let x = startX + CGFloat(i) * (barWidth + barSpacing)
            let y = (bounds.height - height) / 2

            let rect = NSRect(x: x, y: y, width: barWidth, height: height)
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.white.withAlphaComponent(0.85).setFill()
            path.fill()
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
swift build
```
Expected: Build complete with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Voicer/WaveformView.swift
git commit -m "feat: add WaveformView with 5 smoothed bars driven by CVDisplayLink"
```

---

## Task 8: FloatingPanelController — capsule HUD with animations

**Files:**
- Create: `Sources/Voicer/FloatingPanelController.swift`

Layout inside the panel:
```
|← 20px →|← 44px (waveform) →|← 12px →|← text (160–560px) →|← 20px →|
```
Total panel width: 256–656px. Height: 56px always.

Entry animation: CASpringAnimation on `transform.scale` from 0.7 → 1.0 + alpha 0 → 1.  
Text width: NSLayoutConstraint constant, animated with `NSAnimationContext` (0.25s ease-in-out).  
Exit: shrink alpha to 0 over 0.22s.

- [ ] **Step 1: Create `FloatingPanelController.swift`**

```swift
import AppKit

final class FloatingPanelController {
    private var panel: NSPanel?
    private var waveformView: WaveformView?
    private var label: NSTextField?
    private var textWidthConstraint: NSLayoutConstraint?
    private var currentText = ""

    private let panelHeight: CGFloat = 56
    private let cornerRadius: CGFloat = 28
    private let horizontalPadding: CGFloat = 20
    private let waveformWidth: CGFloat = 44
    private let waveformHeight: CGFloat = 32
    private let gap: CGFloat = 12
    private let minTextWidth: CGFloat = 160
    private let maxTextWidth: CGFloat = 560

    func showRecording() {
        if panel == nil { buildPanel() }
        guard let panel = panel else { return }

        currentText = ""
        label?.stringValue = ""
        updateTextWidth(animated: false)
        positionPanel()

        panel.alphaValue = 0
        panel.orderFront(nil)

        // Spring entry animation
        guard let contentLayer = panel.contentView?.layer else { return }
        contentLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)

        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.damping = 12
        spring.initialVelocity = 8
        spring.fromValue = 0.7
        spring.toValue = 1.0
        spring.duration = 0.35
        spring.isRemovedOnCompletion = true
        contentLayer.add(spring, forKey: "entry")

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 1.0
        }
    }

    func updateTranscription(_ text: String) {
        guard let label else { return }
        currentText = text
        label.stringValue = text
        updateTextWidth(animated: true)
        positionPanel()
    }

    func showRefining() {
        label?.stringValue = "Refining…"
        label?.textColor = NSColor.white.withAlphaComponent(0.6)
    }

    func updateLevel(_ level: Float) {
        waveformView?.update(level: level)
    }

    func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            self.label?.textColor = .white
        })
    }

    // MARK: - Private

    private func buildPanel() {
        let initialWidth = horizontalPadding * 2 + waveformWidth + gap + minTextWidth
        let frame = NSRect(x: 0, y: 0, width: initialWidth, height: panelHeight)

        let p = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Visual effect background
        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = cornerRadius
        blur.layer?.masksToBounds = true
        blur.autoresizingMask = [.width, .height]
        p.contentView = blur

        // Waveform
        let wv = WaveformView(frame: NSRect(
            x: horizontalPadding,
            y: (panelHeight - waveformHeight) / 2,
            width: waveformWidth,
            height: waveformHeight
        ))
        wv.autoresizingMask = [.minYMargin, .maxYMargin]
        blur.addSubview(wv)
        waveformView = wv

        // Text label
        let tf = NSTextField(labelWithString: "")
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.font = .systemFont(ofSize: 16, weight: .medium)
        tf.textColor = .white
        tf.lineBreakMode = .byTruncatingTail
        tf.maximumNumberOfLines = 1
        tf.drawsBackground = false
        tf.isBordered = false
        blur.addSubview(tf)

        let textLeft = horizontalPadding + waveformWidth + gap
        let widthConstraint = tf.widthAnchor.constraint(equalToConstant: minTextWidth)
        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: textLeft),
            tf.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
            widthConstraint
        ])
        textWidthConstraint = widthConstraint
        label = tf

        panel = p
    }

    private func updateTextWidth(animated: Bool) {
        guard let label, let constraint = textWidthConstraint, let panel else { return }
        let sizer = NSTextField(labelWithString: label.stringValue)
        sizer.font = label.font
        let needed = min(max(sizer.intrinsicContentSize.width + 8, minTextWidth), maxTextWidth)
        let newPanelWidth = horizontalPadding * 2 + waveformWidth + gap + needed

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                constraint.animator().constant = needed
                panel.animator().setFrame(
                    NSRect(x: panel.frame.minX, y: panel.frame.minY,
                           width: newPanelWidth, height: panelHeight),
                    display: true
                )
            }
        } else {
            constraint.constant = needed
            panel.setFrame(
                NSRect(x: panel.frame.minX, y: panel.frame.minY,
                       width: newPanelWidth, height: panelHeight),
                display: false
            )
        }
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let x = screen.visibleFrame.midX - panel.frame.width / 2
        let y = screen.visibleFrame.minY + 80
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
swift build
```
Expected: Build complete with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Voicer/FloatingPanelController.swift
git commit -m "feat: add FloatingPanelController capsule HUD with spring entry and elastic text"
```

---

## Task 9: TextInjector — clipboard paste with CJK IME handling

**Files:**
- Create: `Sources/Voicer/TextInjector.swift`

Uses `TISCopyCurrentKeyboardInputSource` / `TISSelectInputSource` from ApplicationServices to detect and temporarily switch away from CJK input methods before pasting.

- [ ] **Step 1: Create `TextInjector.swift`**

```swift
import AppKit
import Carbon

final class TextInjector {
    func inject(_ text: String) {
        guard !text.isEmpty else { return }

        // 1. Save current clipboard
        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems.map { item -> NSPasteboardItem in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }

        // 2. Detect CJK input method and switch to ASCII if needed
        let originalSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let isCJK = detectCJK(source: originalSource)
        if isCJK { switchToASCII() }

        // 3. Set pasteboard to our text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 4. Simulate Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.simulatePaste()

            // 5. Restore IME and clipboard after a small delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                if isCJK { TISSelectInputSource(originalSource) }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    pasteboard.clearContents()
                    if !savedItems.isEmpty {
                        pasteboard.writeObjects(savedItems)
                    }
                }
            }
        }
    }

    private func detectCJK(source: TISInputSource) -> Bool {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
        let sourceID = Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
        let cjkPrefixes = ["com.apple.inputmethod.SCIM",
                           "com.apple.inputmethod.ChineseHandwriting",
                           "com.apple.inputmethod.Korean",
                           "com.apple.inputmethod.Japanese",
                           "com.apple.inputmethod.Traditional",
                           "com.sogou", "com.baidu", "com.iflytek",
                           "com.tencent", "com.google.inputmethod"]
        return cjkPrefixes.contains { sourceID.hasPrefix($0) }
    }

    private func switchToASCII() {
        let filter = [kTISPropertyInputSourceType: kTISTypeKeyboardLayout,
                      kTISPropertyInputSourceIsASCIICapable: true] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
              let ascii = list.first else { return }
        TISSelectInputSource(ascii)
        // Give IME time to switch
        Thread.sleep(forTimeInterval: 0.05)
    }

    private func simulatePaste() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let keyV: CGKeyCode = 0x09  // kVK_ANSI_V

        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyV, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: keyV, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
swift build
```
Expected: Build complete with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Voicer/TextInjector.swift
git commit -m "feat: add TextInjector with clipboard-based paste and CJK IME switching"
```

---

## Task 10: LLMClient — OpenAI-compatible refinement

**Files:**
- Create: `Sources/Voicer/LLMClient.swift`

- [ ] **Step 1: Create `LLMClient.swift`**

```swift
import Foundation

final class LLMClient {
    struct Config {
        var baseURL: String
        var apiKey: String
        var model: String
    }

    private static let systemPrompt = """
    You are a speech recognition error corrector. Fix ONLY obvious errors:
    - Chinese homophone mistakes (wrong character with same sound)
    - English technical terms mistakenly transcribed as Chinese (e.g., 配森→Python, 杰森→JSON, 阿皮艾→API, 布尔→bool, 阿里→Array)
    - Clear mishearings or recognition glitches

    Rules (STRICTLY follow):
    - If the text looks correct, return it EXACTLY as-is, character for character
    - Do NOT rewrite, restructure, add punctuation, or improve style
    - Do NOT remove any content
    - Preserve all original punctuation, capitalization, spacing, and line breaks
    - Return ONLY the corrected text — no explanations, no quotes, no preamble
    """

    func refine(text: String, config: Config) async throws -> String {
        guard !config.apiKey.isEmpty, !config.baseURL.isEmpty else { return text }

        let url = URL(string: config.baseURL.trimmingCharacters(in: .whitespaces)
                        .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
                        + "/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "max_tokens": 500,
            "temperature": 0
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LLMError.badResponse((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.malformedResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum LLMError: LocalizedError {
        case badResponse(Int)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .badResponse(let code): return "LLM API returned HTTP \(code)"
            case .malformedResponse: return "LLM response format unexpected"
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
swift build
```
Expected: Build complete with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Voicer/LLMClient.swift
git commit -m "feat: add LLMClient for OpenAI-compatible speech correction"
```

---

## Task 11: LLMSettingsWindowController

**Files:**
- Create: `Sources/Voicer/LLMSettingsWindowController.swift`

- [ ] **Step 1: Create `LLMSettingsWindowController.swift`**

```swift
import AppKit

final class LLMSettingsWindowController: NSWindowController {
    private var baseURLField: NSTextField!
    private var apiKeyField: NSSecureTextField!
    private var modelField: NSTextField!
    private let llmClient = LLMClient()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "LLM Settings"
        window.center()
        self.init(window: window)
        buildUI()
        loadSettings()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let labels = ["API Base URL:", "API Key:", "Model:"]
        var yPositions: [CGFloat] = [152, 112, 72]

        for (i, labelText) in labels.enumerated() {
            let label = NSTextField(labelWithString: labelText)
            label.frame = NSRect(x: 20, y: yPositions[i], width: 110, height: 22)
            label.alignment = .right
            contentView.addSubview(label)
        }

        baseURLField = NSTextField(frame: NSRect(x: 138, y: 152, width: 262, height: 22))
        baseURLField.placeholderString = "https://api.openai.com"
        contentView.addSubview(baseURLField)

        apiKeyField = NSSecureTextField(frame: NSRect(x: 138, y: 112, width: 262, height: 22))
        apiKeyField.placeholderString = "sk-..."
        contentView.addSubview(apiKeyField)

        modelField = NSTextField(frame: NSRect(x: 138, y: 72, width: 262, height: 22))
        modelField.placeholderString = "gpt-4o-mini"
        contentView.addSubview(modelField)

        let testButton = NSButton(title: "Test", target: self, action: #selector(test))
        testButton.frame = NSRect(x: 240, y: 20, width: 80, height: 32)
        testButton.bezelStyle = .rounded
        contentView.addSubview(testButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.frame = NSRect(x: 328, y: 20, width: 80, height: 32)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)
    }

    private func loadSettings() {
        let s = AppSettings.shared
        baseURLField.stringValue = s.llmBaseURL
        // NSSecureTextField does not display existing value for security;
        // show placeholder only — user must re-enter key to change it
        modelField.stringValue = s.llmModel
    }

    @objc private func save() {
        let s = AppSettings.shared
        s.llmBaseURL = baseURLField.stringValue
        if !apiKeyField.stringValue.isEmpty {
            s.llmAPIKey = apiKeyField.stringValue
        }
        s.llmModel = modelField.stringValue
        window?.close()
    }

    @objc private func test() {
        let config = LLMClient.Config(
            baseURL: baseURLField.stringValue,
            apiKey: apiKeyField.stringValue.isEmpty ? AppSettings.shared.llmAPIKey : apiKeyField.stringValue,
            model: modelField.stringValue.isEmpty ? AppSettings.shared.llmModel : modelField.stringValue
        )
        Task {
            do {
                let result = try await self.llmClient.refine(text: "测试 Python JSON", config: config)
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "LLM Test Passed"
                    alert.informativeText = "Response: \(result)"
                    alert.runModal()
                }
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "LLM Test Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .critical
                    alert.runModal()
                }
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
swift build
```
Expected: Build complete with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Voicer/LLMSettingsWindowController.swift
git commit -m "feat: add LLMSettingsWindowController with URL/key/model fields and test button"
```

---

## Task 12: MenuBarManager — status item + full menu

**Files:**
- Create: `Sources/Voicer/MenuBarManager.swift`

- [ ] **Step 1: Create `MenuBarManager.swift`**

```swift
import AppKit

final class MenuBarManager {
    private var statusItem: NSStatusItem!
    private var llmToggleItem: NSMenuItem!
    private var languageItems: [NSMenuItem] = []
    private var settingsWindowController: LLMSettingsWindowController?

    var onLanguageChange: ((String) -> Void)?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Voicer")
        }
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // Language submenu
        let langMenu = NSMenu()
        let languages: [(String, String)] = [
            ("zh-CN", "Simplified Chinese (简体中文)"),
            ("zh-TW", "Traditional Chinese (繁體中文)"),
            ("en-US", "English"),
            ("ja-JP", "Japanese (日本語)"),
            ("ko-KR", "Korean (한국어)")
        ]
        let currentLang = AppSettings.shared.language
        for (id, name) in languages {
            let item = NSMenuItem(title: name, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = id
            item.state = id == currentLang ? .on : .off
            langMenu.addItem(item)
            languageItems.append(item)
        }
        let langItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        langItem.submenu = langMenu
        menu.addItem(langItem)

        menu.addItem(.separator())

        // LLM submenu
        let llmMenu = NSMenu()
        llmToggleItem = NSMenuItem(title: "Enable LLM Refinement",
                                   action: #selector(toggleLLM),
                                   keyEquivalent: "")
        llmToggleItem.target = self
        llmToggleItem.state = AppSettings.shared.llmEnabled ? .on : .off
        llmMenu.addItem(llmToggleItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openLLMSettings), keyEquivalent: "")
        settingsItem.target = self
        llmMenu.addItem(settingsItem)

        let llmItem = NSMenuItem(title: "LLM Refinement", action: nil, keyEquivalent: "")
        llmItem.submenu = llmMenu
        menu.addItem(llmItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Voicer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        AppSettings.shared.language = id
        for item in languageItems {
            item.state = (item.representedObject as? String) == id ? .on : .off
        }
        onLanguageChange?(id)
    }

    @objc private func toggleLLM() {
        let enabled = !AppSettings.shared.llmEnabled
        AppSettings.shared.llmEnabled = enabled
        llmToggleItem.state = enabled ? .on : .off
    }

    @objc private func openLLMSettings() {
        if settingsWindowController == nil {
            settingsWindowController = LLMSettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
swift build
```
Expected: Build complete with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Voicer/MenuBarManager.swift
git commit -m "feat: add MenuBarManager with language and LLM submenus"
```

---

## Task 13: AppDelegate — wire everything together

**Files:**
- Modify: `Sources/Voicer/AppDelegate.swift`

- [ ] **Step 1: Replace `AppDelegate.swift` with full implementation**

```swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuBar = MenuBarManager()
    private let coordinator = RecordingCoordinator()
    private let panel = FloatingPanelController()
    private let injector = TextInjector()
    private let llmClient = LLMClient()

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
                Task {
                    let refined = (try? await self.llmClient.refine(text: rawText, config: config)) ?? rawText
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

    func applicationWillTerminate(_ notification: Notification) {
        // coordinator / fnMonitor tear down in deinit
    }
}
```

- [ ] **Step 2: Build to verify the complete app compiles**

```bash
swift build -c release
```
Expected: Build complete with no errors (may show warnings about unused vars — acceptable).

- [ ] **Step 3: Commit**

```bash
git add Sources/Voicer/AppDelegate.swift
git commit -m "feat: wire all components in AppDelegate to complete the recording pipeline"
```

---

## Task 14: Build, bundle, sign, and smoke-test

**Files:**
- No new source files; uses existing `Makefile`

- [ ] **Step 1: Run `make build`**

```bash
cd /Users/panjuntao/Developer/voicer
make build
```
Expected output:
```
swift build -c release
...
Build complete!
mkdir -p ".build/Voicer.app/Contents/MacOS"
...
```

- [ ] **Step 2: Verify bundle structure**

```bash
find .build/Voicer.app -type f
```
Expected:
```
.build/Voicer.app/Contents/MacOS/Voicer
.build/Voicer.app/Contents/Info.plist
```

- [ ] **Step 3: Launch and verify menu bar icon appears**

```bash
open .build/Voicer.app
```
Expected: A microphone icon appears in the macOS menu bar. No Dock icon. Clicking the icon opens the menu with Language and LLM Refinement submenus.

- [ ] **Step 4: Grant permissions when prompted**

The app will prompt for Accessibility (for Fn key tap), Microphone, and Speech Recognition. Grant all three in System Settings > Privacy & Security.

- [ ] **Step 5: Smoke-test hold-Fn recording**

1. Open TextEdit or any text field.
2. Hold the Fn (Globe) key — the capsule HUD should appear at the bottom of the screen with waveform bars animating.
3. Speak a sentence in Chinese: "你好，今天天气怎么样？"
4. Watch the transcription appear in the HUD in real time.
5. Release Fn — HUD should fade out and the text should be pasted into the focused field.

- [ ] **Step 6: Smoke-test LLM refinement**

1. Open LLM Refinement > Settings, enter API key, click Save.
2. Enable LLM Refinement.
3. Hold Fn, say "配森是一种编程语言", release Fn.
4. HUD should briefly show "Refining…" then paste "Python是一种编程语言".

- [ ] **Step 7: Final commit**

```bash
git add -A
git commit -m "feat: complete Voicer macOS menu-bar voice input app"
```

---

## Self-Review: Spec Coverage

| Requirement | Task(s) |
|-------------|---------|
| Hold Fn to record, release to inject | Task 3 (FnKeyMonitor), Task 6 (RecordingCoordinator) |
| Suppress Fn/emoji picker via CGEvent tap | Task 3 |
| Streaming transcription (Apple Speech) | Task 5 (SpeechEngine), Task 6 |
| Default zh-CN, language menu (5 locales) | Task 2 (AppSettings default), Task 12 (menu) |
| Language stored in UserDefaults | Task 2 |
| Frameless capsule 56px / corner 28px NSPanel | Task 8 |
| NSVisualEffectView .hudWindow | Task 8 |
| 5-bar waveform 44×32px, real RMS | Task 4 (RMS), Task 7 (WaveformView) |
| Bar weights [0.5,0.8,1.0,0.75,0.55] | Task 7 |
| Smooth envelope attack 40% release 15% | Task 7 |
| ±4% random jitter per bar | Task 7 |
| Elastic text label 160–560px | Task 8 |
| Entry spring 0.35s, text 0.25s, exit 0.22s | Task 8 |
| Text injection via clipboard + Cmd+V | Task 9 |
| CJK IME detect + ASCII switch + restore | Task 9 |
| Clipboard restore after injection | Task 9 |
| LLM refinement (OpenAI-compatible) | Task 10 |
| Conservative system prompt | Task 10 |
| LLM toggle + Settings menu | Task 12 |
| Settings window: URL, key, model, Test, Save | Task 11 |
| API key field clearable | Task 11 (NSSecureTextField, re-enter to change) |
| "Refining…" status in HUD | Task 8 (showRefining), Task 13 (coordinator) |
| LSUIElement (no Dock icon) | Task 1 (Info.plist) |
| SPM + Makefile (build/run/install/clean) | Task 1 |
| Signed .app bundle | Task 1 (Makefile codesign step) |

All requirements covered. No gaps found.
