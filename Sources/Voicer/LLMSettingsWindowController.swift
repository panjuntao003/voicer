import AppKit

final class LLMSettingsWindowController: NSWindowController, NSWindowDelegate {
    private var providerPopup: NSPopUpButton!
    private var baseURLField: NSTextField!
    private var apiKeyField: NSSecureTextField!
    private var modelField: NSTextField!
    private var speechToggle: NSButton!
    private var speechModelField: NSTextField!
    private var speechWarningLabel: NSTextField!
    private let llmClient = LLMClient()
    private var testTask: Task<Void, Never>?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 310),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
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

        let labels: [(String, CGFloat)] = [
            ("Provider:", 262),
            ("API Key:", 222),
            ("Model:", 182),
            ("", 142),  // speech toggle row
            ("Speech Model:", 102),
        ]

        for (text, y) in labels {
            guard !text.isEmpty else { continue }
            let label = NSTextField(labelWithString: text)
            label.frame = NSRect(x: 20, y: y, width: 110, height: 22)
            label.alignment = .right
            contentView.addSubview(label)
        }

        // Provider popup
        providerPopup = NSPopUpButton(frame: NSRect(x: 138, y: 262, width: 262, height: 24))
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged)
        for provider in LLMProvider.all {
            let title = provider.supportsSpeech ? "\(provider.name) 🎤" : provider.name
            providerPopup.addItem(withTitle: title)
        }
        contentView.addSubview(providerPopup)

        // API Key
        apiKeyField = NSSecureTextField(frame: NSRect(x: 138, y: 222, width: 262, height: 22))
        apiKeyField.placeholderString = "sk-... (enter to change)"
        contentView.addSubview(apiKeyField)

        // Model
        modelField = NSTextField(frame: NSRect(x: 138, y: 182, width: 262, height: 22))
        modelField.placeholderString = "gpt-4o-mini"
        contentView.addSubview(modelField)

        // Speech toggle
        speechToggle = NSButton(checkboxWithTitle: "Use API for Speech Recognition",
                                target: self, action: #selector(toggleSpeechAPI))
        speechToggle.frame = NSRect(x: 138, y: 142, width: 262, height: 20)
        contentView.addSubview(speechToggle)

        // Speech Model
        speechModelField = NSTextField(frame: NSRect(x: 138, y: 102, width: 262, height: 22))
        speechModelField.placeholderString = "whisper-1"
        contentView.addSubview(speechModelField)

        // Speech provider warning
        speechWarningLabel = NSTextField(labelWithString: "")
        speechWarningLabel.frame = NSRect(x: 138, y: 78, width: 280, height: 18)
        speechWarningLabel.font = .systemFont(ofSize: 11)
        speechWarningLabel.textColor = .secondaryLabelColor
        contentView.addSubview(speechWarningLabel)

        // Buttons
        let testButton = NSButton(title: "Test LLM", target: self, action: #selector(test))
        testButton.frame = NSRect(x: 200, y: 12, width: 100, height: 32)
        testButton.bezelStyle = .rounded
        contentView.addSubview(testButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.frame = NSRect(x: 320, y: 12, width: 80, height: 32)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)
    }

    private func currentProviderName() -> String {
        guard let title = providerPopup.selectedItem?.title else { return "OpenAI" }
        return title.replacingOccurrences(of: " 🎤", with: "")
    }

    private func loadSettings() {
        let s = AppSettings.shared
        let provider = LLMProvider.provider(named: s.llmProviderName)
        let displayTitle = provider.supportsSpeech ? "\(provider.name) 🎤" : provider.name
        providerPopup.selectItem(withTitle: displayTitle)

        modelField.stringValue = s.llmModel
        speechToggle.state = s.speechAPIEnabled ? .on : .off
        speechModelField.stringValue = s.speechModel
        speechModelField.isEnabled = s.speechAPIEnabled
        updateSpeechWarning()
    }

    private func updateSpeechWarning() {
        let provider = LLMProvider.provider(named: currentProviderName())
        if !provider.supportsSpeech && speechToggle.state == .on {
            speechWarningLabel.stringValue = "⚠️ \(provider.name) does not support Speech API"
        } else {
            speechWarningLabel.stringValue = ""
        }
    }

    @objc private func providerChanged() {
        let provider = LLMProvider.provider(named: currentProviderName())
        modelField.stringValue = provider.defaultModel
        updateSpeechWarning()
    }

    @objc private func toggleSpeechAPI() {
        let enabled = speechToggle.state == .on
        speechModelField.isEnabled = enabled
        updateSpeechWarning()
    }

    @objc private func save() {
        let s = AppSettings.shared
        let providerName = currentProviderName()
        s.llmProviderName = providerName
        let provider = LLMProvider.provider(named: providerName)
        if provider.name != "Custom" {
            s.llmBaseURL = provider.baseURL
        } else {
            s.llmBaseURL = baseURLField.stringValue
        }
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
        let providerName = currentProviderName()
        let provider = LLMProvider.provider(named: providerName)
        let baseURL = provider.name == "Custom" ? AppSettings.shared.llmBaseURL : provider.baseURL
        let config = LLMClient.Config(
            baseURL: baseURL,
            apiKey: apiKeyField.stringValue.isEmpty ? AppSettings.shared.llmAPIKey : apiKeyField.stringValue,
            model: modelField.stringValue.isEmpty ? provider.defaultModel : modelField.stringValue
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