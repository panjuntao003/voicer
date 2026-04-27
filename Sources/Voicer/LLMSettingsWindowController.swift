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
        window.level = .floating
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
