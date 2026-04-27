# Voicer UI 优化 + API 语音识别 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 Voicer 的浮动面板改造为 Apple 原生灵动岛风格（顶部中央、三态切换、文字更清晰），并引入第三方 Whisper API 实现多语言自动混合识别，同时用 Provider 下拉框简化 LLM 配置。

**Architecture:** 继续使用纯 AppKit 方案，不引入 SwiftUI。双引擎策略：本地 Apple Speech 做实时预览，录音结束后可选 Whisper API 做最终高精度识别。所有 Provider 兼容 OpenAI 格式，复用现有 LLMClient 的请求逻辑。

**Tech Stack:** Swift 5.9, AppKit, AVFoundation, Speech, Foundation

---

## 文件结构映射

| 文件 | 职责 |
|---|---|
| `LLMProvider.swift` (新增) | 18 个预设 Provider 的静态数据模型，提供 name/baseURL/defaultModel |
| `AppSettings.swift` (修改) | 新增 `llmProviderName`, `speechAPIEnabled`, `speechModel` 持久化字段 |
| `MenuBarManager.swift` (修改) | 移除 Language 子菜单，简化菜单结构 |
| `WaveformView.swift` (修改) | 增加光晕效果、优化动画参数 |
| `FloatingPanelController.swift` (重写) | 灵动岛风格面板：顶部中央位置、三状态管理、清晰文字 |
| `AudioEngine.swift` (修改) | 录音时同步写入临时音频文件，供 API 识别使用 |
| `SpeechAPIClient.swift` (新增) | 将音频文件 POST 到 Whisper API，返回识别文字 |
| `SpeechEngine.swift` (修改) | locale 改为自动检测（`.autoupdatingCurrent`），不再强制固定 |
| `RecordingCoordinator.swift` (修改) | 双引擎协调：本地实时预览 + API 最终识别 + Fallback |
| `AppDelegate.swift` (修改) | 调整事件流：录音中→API识别→LLM润色→注入文字 |
| `LLMSettingsWindowController.swift` (重写) | Provider NSPopUpButton 下拉框 + Speech API 开关 + 向后兼容迁移 |

---

## Task 1: LLMProvider 数据模型 + AppSettings 扩展

**Files:**
- Create: `Sources/Voicer/LLMProvider.swift`
- Modify: `Sources/Voicer/AppSettings.swift`

- [ ] **Step 1: 创建 LLMProvider.swift**

```swift
import Foundation

struct LLMProvider: Equatable {
    let name: String
    let baseURL: String
    let defaultModel: String

    static let all: [LLMProvider] = [
        LLMProvider(name: "OpenAI", baseURL: "https://api.openai.com", defaultModel: "gpt-4o-mini"),
        LLMProvider(name: "DeepSeek", baseURL: "https://api.deepseek.com", defaultModel: "deepseek-chat"),
        LLMProvider(name: "Moonshot (Kimi)", baseURL: "https://api.moonshot.cn", defaultModel: "moonshot-v1-8k"),
        LLMProvider(name: "智谱 AI (GLM)", baseURL: "https://open.bigmodel.cn/api/paas", defaultModel: "glm-4-flash"),
        LLMProvider(name: "ByteDance (豆包)", baseURL: "https://ark.cn-beijing.volces.com/api", defaultModel: "doubao-lite-4k"),
        LLMProvider(name: "Alibaba (通义千问)", baseURL: "https://dashscope.aliyuncs.com/compatible-mode", defaultModel: "qwen-turbo"),
        LLMProvider(name: "Baichuan (百川)", baseURL: "https://api.baichuan-ai.com", defaultModel: "Baichuan4"),
        LLMProvider(name: "MiniMax", baseURL: "https://api.minimax.chat", defaultModel: "abab6.5s-chat"),
        LLMProvider(name: "零一万物 (01.AI)", baseURL: "https://api.lingyiwanwu.com", defaultModel: "yi-lightning"),
        LLMProvider(name: "阶跃星辰 (StepFun)", baseURL: "https://api.stepfun.com", defaultModel: "step-1-8k"),
        LLMProvider(name: "Groq", baseURL: "https://api.groq.com/openai", defaultModel: "llama-3.1-8b"),
        LLMProvider(name: "xAI (Grok)", baseURL: "https://api.x.ai", defaultModel: "grok-2"),
        LLMProvider(name: "Mistral AI", baseURL: "https://api.mistral.ai", defaultModel: "mistral-small"),
        LLMProvider(name: "Cohere", baseURL: "https://api.cohere.ai", defaultModel: "command-r"),
        LLMProvider(name: "Perplexity", baseURL: "https://api.perplexity.ai", defaultModel: "llama-3.1-sonar-small"),
        LLMProvider(name: "Fireworks AI", baseURL: "https://api.fireworks.ai/inference", defaultModel: "accounts/fireworks/models/llama-v3p1-8b"),
        LLMProvider(name: "SiliconFlow", baseURL: "https://api.siliconflow.cn", defaultModel: "Qwen/Qwen2.5-7B-Instruct"),
        LLMProvider(name: "Custom", baseURL: "", defaultModel: ""),
    ]

    static func provider(named name: String) -> LLMProvider {
        all.first { $0.name == name } ?? all[0]
    }
}
```

- [ ] **Step 2: 修改 AppSettings.swift，新增字段和向后兼容迁移**

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
        case llmProviderName = "voicer.llm.providerName"
        case speechAPIEnabled = "voicer.speech.apiEnabled"
        case speechModel = "voicer.speech.model"
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
        get { defaults.string(forKey: Key.llmBaseURL.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.llmBaseURL.rawValue) }
    }

    var llmAPIKey: String {
        get { defaults.string(forKey: Key.llmAPIKey.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.llmAPIKey.rawValue) }
    }

    var llmModel: String {
        get { defaults.string(forKey: Key.llmModel.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.llmModel.rawValue) }
    }

    var llmProviderName: String {
        get {
            if let stored = defaults.string(forKey: Key.llmProviderName.rawValue), !stored.isEmpty {
                return stored
            }
            // 向后兼容：老用户根据 baseURL 反向匹配
            let url = llmBaseURL
            if let matched = LLMProvider.all.first(where: { $0.baseURL == url && $0.name != "Custom" }) {
                defaults.set(matched.name, forKey: Key.llmProviderName.rawValue)
                return matched.name
            }
            return "Custom"
        }
        set { defaults.set(newValue, forKey: Key.llmProviderName.rawValue) }
    }

    var speechAPIEnabled: Bool {
        get { defaults.bool(forKey: Key.speechAPIEnabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.speechAPIEnabled.rawValue) }
    }

    var speechModel: String {
        get { defaults.string(forKey: Key.speechModel.rawValue) ?? "whisper-1" }
        set { defaults.set(newValue, forKey: Key.speechModel.rawValue) }
    }
}
```

- [ ] **Step 3: 编译验证**

Run: `swift build`
Expected: 编译成功（无 error）

- [ ] **Step 4: Commit**

```bash
git add Sources/Voicer/LLMProvider.swift Sources/Voicer/AppSettings.swift
git commit -m "feat: add LLMProvider model and AppSettings speech/provider fields"
```

---

## Task 2: MenuBarManager 移除 Language 菜单

**Files:**
- Modify: `Sources/Voicer/MenuBarManager.swift`

- [ ] **Step 1: 移除 Language 相关代码，保留 LLM 和 Quit**

把 `MenuBarManager.swift` 完整替换为：

```swift
import AppKit

final class MenuBarManager: NSObject {
    private var statusItem: NSStatusItem!
    private var llmToggleItem: NSMenuItem!
    private var settingsWindowController: LLMSettingsWindowController?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Voicer")
        }
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

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

    @objc private func toggleLLM() {
        let enabled = !AppSettings.shared.llmEnabled
        AppSettings.shared.llmEnabled = enabled
        llmToggleItem.state = enabled ? .on : .off
    }

    @objc private func openLLMSettings() {
        if settingsWindowController == nil {
            settingsWindowController = LLMSettingsWindowController()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(settingsWindowClosed),
                name: NSWindow.willCloseNotification,
                object: settingsWindowController?.window
            )
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate()
    }

    @objc private func settingsWindowClosed() {
        settingsWindowController = nil
    }
}
```

- [ ] **Step 2: 编译验证**

Run: `swift build`
Expected: 编译成功

- [ ] **Step 3: Commit**

```bash
git add Sources/Voicer/MenuBarManager.swift
git commit -m "refactor: remove language menu from menu bar"
```

---

## Task 3: WaveformView 优化动画

**Files:**
- Modify: `Sources/Voicer/WaveformView.swift`

- [ ] **Step 1: 增加光晕效果、优化动画参数**

完整替换 `WaveformView.swift`：

```swift
import AppKit
import QuartzCore

final class WaveformView: NSView {
    private let weights: [Float] = [0.5, 0.8, 1.0, 0.75, 0.55]
    private var smoothed: [Float] = Array(repeating: 0, count: 5)
    private var displayLink: CADisplayLink?
    private var barLayers: [CALayer] = []

    private let barWidth: CGFloat = 4
    private let barSpacing: CGFloat = 3
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 26
    private let cornerRadius: CGFloat = 2

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupLayers()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupLayers() {
        barLayers.forEach { $0.removeFromSuperlayer() }
        barLayers = []
        for _ in 0..<5 {
            let layer = CALayer()
            layer.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
            layer.cornerRadius = cornerRadius
            layer.shadowColor = NSColor.white.cgColor
            layer.shadowOffset = CGSize(width: 0, height: 0)
            layer.shadowRadius = 3
            layer.shadowOpacity = 0.4
            self.layer?.addSublayer(layer)
            barLayers.append(layer)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        if let window {
            let link = window.displayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    deinit {
        displayLink?.invalidate()
    }

    @MainActor
    func update(level: Float) {
        let attack: Float = 0.35
        let release: Float = 0.12
        for i in 0..<5 {
            let target = level * weights[i]
            let alpha = target > smoothed[i] ? attack : release
            let jitter = Float.random(in: -0.03...0.03)
            smoothed[i] = smoothed[i] * (1 - alpha) + target * alpha + jitter
            smoothed[i] = max(0, min(1, smoothed[i]))
        }
    }

    @objc private func tick() {
        layoutBars()
    }

    private func layoutBars() {
        let totalBarWidth = CGFloat(5) * barWidth + CGFloat(4) * barSpacing
        let startX = (bounds.width - totalBarWidth) / 2

        for i in 0..<5 {
            let level = CGFloat(smoothed[i])
            let height = minHeight + (maxHeight - minHeight) * level
            let x = startX + CGFloat(i) * (barWidth + barSpacing)
            let y = (bounds.height - height) / 2

            let rect = CGRect(x: x, y: y, width: barWidth, height: height)
            barLayers[i].frame = rect

            // 动态调整光晕强度
            barLayers[i].shadowOpacity = 0.2 + 0.5 * Float(level)
        }
    }

    override func layout() {
        super.layout()
        layoutBars()
    }
}
```

- [ ] **Step 2: 编译验证**

Run: `swift build`
Expected: 编译成功

- [ ] **Step 3: Commit**

```bash
git add Sources/Voicer/WaveformView.swift
git commit -m "feat: add glow effect and smoother animation to waveform"
```

---

## Task 4: FloatingPanelController 灵动岛重写

**Files:**
- Modify: `Sources/Voicer/FloatingPanelController.swift`

- [ ] **Step 1: 重写面板为灵动岛风格**

完整替换 `FloatingPanelController.swift`：

```swift
import AppKit

enum PanelState {
    case recording
    case processing(message: String)
    case hidden
}

final class FloatingPanelController {
    private var panel: NSPanel?
    private var waveformView: WaveformView?
    private var label: NSTextField?
    private var statusIndicator: NSView?
    private var spinner: NSProgressIndicator?
    private var textWidthConstraint: NSLayoutConstraint?
    private var currentState: PanelState = .hidden

    private let panelHeight: CGFloat = 56
    private let cornerRadius: CGFloat = 28
    private let horizontalPadding: CGFloat = 20
    private let waveformWidth: CGFloat = 44
    private let waveformHeight: CGFloat = 32
    private let gap: CGFloat = 12
    private let minTextWidth: CGFloat = 160
    private let maxTextWidth: CGFloat = 560

    // MARK: - Public API

    func showRecording() {
        transition(to: .recording)
    }

    func showProcessing(message: String) {
        transition(to: .processing(message: message))
    }

    func updateTranscription(_ text: String) {
        guard let label else { return }
        label.stringValue = text
        label.textColor = .white
        updateTextWidth(animated: true)
        positionPanel()
    }

    @MainActor
    func updateLevel(_ level: Float) {
        waveformView?.update(level: level)
    }

    func hide() {
        transition(to: .hidden)
    }

    // MARK: - State Management

    private func transition(to state: PanelState) {
        switch state {
        case .recording:
            showPanel()
            configureForRecording()
        case .processing(let message):
            guard panel != nil else { return }
            configureForProcessing(message: message)
        case .hidden:
            animateHide()
        }
        currentState = state
    }

    // MARK: - Panel Lifecycle

    private func showPanel() {
        if panel == nil { buildPanel() }
        guard let panel = panel else { return }

        label?.stringValue = ""
        label?.textColor = .white
        updateTextWidth(animated: false)
        positionPanel()

        panel.alphaValue = 0
        panel.orderFront(nil)

        guard let contentLayer = panel.contentView?.layer else { return }

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

    private func animateHide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            panel.animator().alphaValue = 0
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1.0
            scale.toValue = 0.9
            scale.duration = 0.22
            panel.contentView?.layer?.add(scale, forKey: "exit")
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    // MARK: - State Configurations

    private func configureForRecording() {
        label?.stringValue = "正在聆听…"
        label?.textColor = .white
        waveformView?.isHidden = false
        statusIndicator?.isHidden = false
        spinner?.isHidden = true
        spinner?.stopAnimation(nil)
        updateTextWidth(animated: true)
        positionPanel()
        startStatusPulse()
    }

    private func configureForProcessing(message: String) {
        label?.stringValue = message
        label?.textColor = NSColor.white.withAlphaComponent(0.8)
        waveformView?.isHidden = true
        statusIndicator?.isHidden = true
        spinner?.isHidden = false
        spinner?.startAnimation(nil)
        updateTextWidth(animated: true)
        positionPanel()
        stopStatusPulse()
    }

    // MARK: - Panel Construction

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

        // Status indicator (green pulse dot)
        let dot = NSView(frame: NSRect(x: 0, y: 0, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemGreen.cgColor
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.isHidden = true
        blur.addSubview(dot)
        statusIndicator = dot

        NSLayoutConstraint.activate([
            dot.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -horizontalPadding),
            dot.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
        ])

        // Spinner
        let spinner = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isHidden = true
        blur.addSubview(spinner)
        self.spinner = spinner

        NSLayoutConstraint.activate([
            spinner.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: horizontalPadding),
            spinner.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),
        ])

        // Label
        let tf = NSTextField(labelWithString: "")
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.font = .systemFont(ofSize: 16, weight: .semibold)
        tf.textColor = .white
        tf.lineBreakMode = .byTruncatingTail
        tf.maximumNumberOfLines = 1
        tf.drawsBackground = false
        tf.isBordered = false

        // Text shadow for crispness
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 0
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        tf.shadow = shadow

        blur.addSubview(tf)

        let textLeft = horizontalPadding + waveformWidth + gap
        let widthConstraint = tf.widthAnchor.constraint(equalToConstant: minTextWidth)
        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: textLeft),
            tf.centerYAnchor.constraint(equalTo: blur.centerYAnchor),
            widthConstraint,
            tf.trailingAnchor.constraint(lessThanOrEqualTo: dot.leadingAnchor, constant: -gap)
        ])
        textWidthConstraint = widthConstraint
        label = tf
        panel = p

        p.contentView?.wantsLayer = true
        p.contentView?.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    // MARK: - Layout

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
        let y = screen.visibleFrame.maxY - panel.frame.height - 12
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Status Indicator Animation

    private var pulseAnimation: CABasicAnimation?

    private func startStatusPulse() {
        guard let dotLayer = statusIndicator?.layer else { return }
        pulseAnimation?.removeAnimation(forKey: "pulse")
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.3
        pulse.duration = 1.0
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dotLayer.add(pulse, forKey: "pulse")
        pulseAnimation = pulse
    }

    private func stopStatusPulse() {
        statusIndicator?.layer?.removeAnimation(forKey: "pulse")
        pulseAnimation = nil
    }
}
```

- [ ] **Step 2: 编译验证**

Run: `swift build`
Expected: 编译成功

- [ ] **Step 3: Commit**

```bash
git add Sources/Voicer/FloatingPanelController.swift
git commit -m "feat: redesign floating panel as Dynamic Island style"
```

---

## Task 5: AudioEngine 增加录音文件保存

**Files:**
- Modify: `Sources/Voicer/AudioEngine.swift`

- [ ] **Step 1: 添加临时音频文件写入**

完整替换 `AudioEngine.swift`：

```swift
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
```

- [ ] **Step 2: 编译验证**

Run: `swift build`
Expected: 编译成功

- [ ] **Step 3: Commit**

```bash
git add Sources/Voicer/AudioEngine.swift
git commit -m "feat: add temporary audio file recording for API transcription"
```

---

## Task 6: SpeechAPIClient 新增

**Files:**
- Create: `Sources/Voicer/SpeechAPIClient.swift`

- [ ] **Step 1: 创建 Whisper API 客户端**

```swift
import Foundation

final class SpeechAPIClient {
    struct Config {
        var baseURL: String
        var apiKey: String
        var model: String
    }

    func transcribe(audioFileURL: URL, config: Config) async throws -> String {
        guard !config.apiKey.isEmpty else {
            throw SpeechAPIError.missingAPIKey
        }

        var baseURL = config.baseURL.trimmingCharacters(in: .whitespaces)
        while baseURL.hasSuffix("/") { baseURL = String(baseURL.dropLast()) }

        guard let url = URL(string: baseURL + "/v1/audio/transcriptions") else {
            throw SpeechAPIError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body = createMultipartBody(fileURL: audioFileURL, model: config.model, boundary: boundary)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SpeechAPIError.badResponse((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let text = json?["text"] as? String else {
            throw SpeechAPIError.malformedResponse
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createMultipartBody(fileURL: URL, model: String, boundary: String) -> Data {
        var body = Data()
        let fileData = (try? Data(contentsOf: fileURL)) ?? Data()

        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.appendString("\(model)\r\n")

        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\"\r\n")
        body.appendString("Content-Type: audio/m4a\r\n\r\n")
        body.append(fileData)
        body.appendString("\r\n")

        body.appendString("--\(boundary)--\r\n")
        return body
    }

    enum SpeechAPIError: LocalizedError {
        case missingAPIKey
        case badURL
        case badResponse(Int)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return "API Key is empty"
            case .badURL: return "Speech API Base URL is invalid"
            case .badResponse(let code): return "Speech API returned HTTP \(code)"
            case .malformedResponse: return "Speech API response format unexpected"
            }
        }
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
```

- [ ] **Step 2: 编译验证**

Run: `swift build`
Expected: 编译成功

- [ ] **Step 3: Commit**

```bash
git add Sources/Voicer/SpeechAPIClient.swift
git commit -m "feat: add SpeechAPIClient for Whisper API transcription"
```

---

## Task 7: SpeechEngine 自动语言检测

**Files:**
- Modify: `Sources/Voicer/SpeechEngine.swift`

- [ ] **Step 1: 将 locale 改为自动检测**

完整替换 `SpeechEngine.swift`：

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
    private var lastTranscription: String = ""

    var locale: Locale = .autoupdatingCurrent {
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
            DispatchQueue.main.async {
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
```

- [ ] **Step 2: 编译验证**

Run: `swift build`
Expected: 编译成功

- [ ] **Step 3: Commit**

```bash
git add Sources/Voicer/SpeechEngine.swift
git commit -m "feat: use autoupdating locale for automatic language detection"
```

---

## Task 8: RecordingCoordinator 双引擎集成

**Files:**
- Modify: `Sources/Voicer/RecordingCoordinator.swift`

- [ ] **Step 1: 重写 Coordinator，集成 API 识别**

完整替换 `RecordingCoordinator.swift`：

```swift
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
```

- [ ] **Step 2: 编译验证**

Run: `swift build`
Expected: 编译成功

- [ ] **Step 3: Commit**

```bash
git add Sources/Voicer/RecordingCoordinator.swift
git commit -m "feat: integrate dual-engine speech recognition with API fallback"
```

---

## Task 9: AppDelegate 流程调整

**Files:**
- Modify: `Sources/Voicer/AppDelegate.swift`

- [ ] **Step 1: 调整事件流，适配新面板状态**

完整替换 `AppDelegate.swift`：

```swift
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
```

- [ ] **Step 2: 编译验证**

Run: `swift build`
Expected: 编译成功

- [ ] **Step 3: Commit**

```bash
git add Sources/Voicer/AppDelegate.swift
git commit -m "feat: update AppDelegate flow for dual-engine + new panel states"
```

---

## Task 10: LLMSettingsWindowController Provider 下拉框重写

**Files:**
- Modify: `Sources/Voicer/LLMSettingsWindowController.swift`

- [ ] **Step 1: 重写为 Provider 下拉框 + Speech API 开关**

完整替换 `LLMSettingsWindowController.swift`：

```swift
import AppKit

final class LLMSettingsWindowController: NSWindowController, NSWindowDelegate {
    private var providerPopup: NSPopUpButton!
    private var baseURLField: NSTextField!
    private var apiKeyField: NSSecureTextField!
    private var modelField: NSTextField!
    private var speechToggle: NSButton!
    private var speechModelField: NSTextField!
    private let llmClient = LLMClient()
    private var testTask: Task<Void, Never>?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "LLM Settings"
        window.center()
        self.init(window: window)
        window.delegate = self
        buildUI()
        loadSettings()
    }

    func windowWillClose(_ notification: Notification) {
        testTask?.cancel()
        testTask = nil
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let labelTexts = ["Provider:", "API Base URL:", "API Key:", "Model:", "Speech Model:"]
        let yPositions: [CGFloat] = [232, 192, 152, 112, 52]

        for (i, labelText) in labelTexts.enumerated() {
            let label = NSTextField(labelWithString: labelText)
            label.frame = NSRect(x: 20, y: yPositions[i], width: 110, height: 22)
            label.alignment = .right
            contentView.addSubview(label)
        }

        // Provider popup
        providerPopup = NSPopUpButton(frame: NSRect(x: 138, y: 232, width: 262, height: 24))
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged)
        for provider in LLMProvider.all {
            providerPopup.addItem(withTitle: provider.name)
        }
        contentView.addSubview(providerPopup)

        // Base URL
        baseURLField = NSTextField(frame: NSRect(x: 138, y: 192, width: 262, height: 22))
        baseURLField.placeholderString = "https://api.example.com"
        contentView.addSubview(baseURLField)

        // API Key
        apiKeyField = NSSecureTextField(frame: NSRect(x: 138, y: 152, width: 262, height: 22))
        apiKeyField.placeholderString = "sk-... (enter to change saved key)"
        contentView.addSubview(apiKeyField)

        // Model
        modelField = NSTextField(frame: NSRect(x: 138, y: 112, width: 262, height: 22))
        modelField.placeholderString = "gpt-4o-mini"
        contentView.addSubview(modelField)

        // Speech toggle
        speechToggle = NSButton(checkboxWithTitle: "Use API for Speech Recognition",
                                target: self, action: #selector(toggleSpeechAPI))
        speechToggle.frame = NSRect(x: 138, y: 82, width: 262, height: 20)
        contentView.addSubview(speechToggle)

        // Speech Model
        speechModelField = NSTextField(frame: NSRect(x: 138, y: 52, width: 262, height: 22))
        speechModelField.placeholderString = "whisper-1"
        contentView.addSubview(speechModelField)

        // Buttons
        let testButton = NSButton(title: "Test", target: self, action: #selector(test))
        testButton.frame = NSRect(x: 240, y: 12, width: 80, height: 32)
        testButton.bezelStyle = .rounded
        contentView.addSubview(testButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.frame = NSRect(x: 328, y: 12, width: 80, height: 32)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)
    }

    private func loadSettings() {
        let s = AppSettings.shared
        let provider = LLMProvider.provider(named: s.llmProviderName)
        providerPopup.selectItem(withTitle: provider.name)

        if provider.name == "Custom" {
            baseURLField.stringValue = s.llmBaseURL
            baseURLField.isHidden = false
        } else {
            baseURLField.stringValue = provider.baseURL
            baseURLField.isHidden = true
        }

        modelField.stringValue = s.llmModel
        speechToggle.state = s.speechAPIEnabled ? .on : .off
        speechModelField.stringValue = s.speechModel
    }

    @objc private func providerChanged() {
        guard let title = providerPopup.selectedItem?.title else { return }
        let provider = LLMProvider.provider(named: title)

        if provider.name == "Custom" {
            baseURLField.isHidden = false
            baseURLField.stringValue = AppSettings.shared.llmBaseURL
        } else {
            baseURLField.isHidden = true
            baseURLField.stringValue = provider.baseURL
        }

        modelField.stringValue = provider.defaultModel
    }

    @objc private func toggleSpeechAPI() {
        let enabled = speechToggle.state == .on
        speechModelField.isEnabled = enabled
    }

    @objc private func save() {
        let s = AppSettings.shared
        if let providerName = providerPopup.selectedItem?.title {
            s.llmProviderName = providerName
        }
        s.llmBaseURL = baseURLField.stringValue
        if !apiKeyField.stringValue.isEmpty {
            s.llmAPIKey = apiKeyField.stringValue
        }
        s.llmModel = modelField.stringValue
        s.speechAPIEnabled = speechToggle.state == .on
        s.speechModel = speechModelField.stringValue
        window?.close()
    }

    @objc private func test() {
        testTask?.cancel()
        let providerName = providerPopup.selectedItem?.title ?? "OpenAI"
        let provider = LLMProvider.provider(named: providerName)
        let baseURL = provider.name == "Custom" ? baseURLField.stringValue : provider.baseURL
        let config = LLMClient.Config(
            baseURL: baseURL,
            apiKey: apiKeyField.stringValue.isEmpty ? AppSettings.shared.llmAPIKey : apiKeyField.stringValue,
            model: modelField.stringValue.isEmpty ? AppSettings.shared.llmModel : modelField.stringValue
        )
        testTask = Task {
            do {
                let result = try await self.llmClient.refine(text: "测试 Python JSON", config: config)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "LLM Test Passed"
                    alert.informativeText = "Response: \(result)"
                    alert.runModal()
                }
            } catch {
                guard !Task.isCancelled else { return }
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

- [ ] **Step 2: 编译验证**

Run: `swift build`
Expected: 编译成功

- [ ] **Step 3: Commit**

```bash
git add Sources/Voicer/LLMSettingsWindowController.swift
git commit -m "feat: rewrite settings window with provider dropdown and speech API toggle"
```

---

## Task 11: 最终集成编译 + 运行验证

**Files:**
- All files

- [ ] **Step 1: 全项目编译**

Run: `swift build`
Expected: 编译成功，0 errors, 0 warnings

- [ ] **Step 2: 运行检查（可选，需要 macOS 环境）**

```bash
swift run
```
Expected: App 启动，菜单栏出现麦克风图标，Settings 窗口可正常打开

- [ ] **Step 3: 最终 Commit**

```bash
git add .
git commit -m "feat: complete Dynamic Island UI + API speech recognition integration"
```

---

## Self-Review 检查清单

### 1. Spec 覆盖检查

| Spec 要求 | 对应 Task | 状态 |
|---|---|---|
| 灵动岛风格面板，顶部中央 | Task 4 | ✅ |
| 三状态：录音中/处理中/消失 | Task 4 | ✅ |
| 文字清晰度优化（shadow + semibold） | Task 4 | ✅ |
| 波形动画光晕效果 | Task 3 | ✅ |
| 第三方 API 语音识别 | Task 6, 8 | ✅ |
| 双引擎策略（本地预览 + API 最终） | Task 8 | ✅ |
| Fallback 到本地结果 | Task 8 | ✅ |
| 音频文件临时保存 | Task 5 | ✅ |
| Provider 下拉框（18 个预设） | Task 1, 10 | ✅ |
| 向后兼容迁移 | Task 1 | ✅ |
| Speech API 开关 + 模型字段 | Task 1, 10 | ✅ |
| 移除 Language 菜单 | Task 2 | ✅ |
| 自动语言检测（autoupdatingCurrent） | Task 7 | ✅ |

### 2. Placeholder 扫描

- ❌ 无 "TBD", "TODO", "implement later"
- ❌ 无 "Add appropriate error handling" 等模糊描述
- ❌ 无 "Similar to Task N"
- ✅ 每个代码步骤都包含完整代码

### 3. 类型一致性检查

- `AppSettings.llmProviderName` — Task 1 定义 `String`，Task 10 读写 `String` ✅
- `AppSettings.speechAPIEnabled` — Task 1 定义 `Bool`，Task 8/10 使用 `Bool` ✅
- `SpeechAPIClient.Config` — Task 6 定义 `(baseURL, apiKey, model)`，Task 8 构造匹配 ✅
- `LLMProvider.all` — Task 1 定义 `[LLMProvider]`，Task 10 遍历匹配 ✅
- `PanelState.processing(message:)` — Task 4 定义，Task 9 调用匹配 ✅

---

## 执行方式选择

**Plan complete and saved to `docs/superpowers/plans/2026-04-27-voicer-ui-api-speech-plan.md`.**

**Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
