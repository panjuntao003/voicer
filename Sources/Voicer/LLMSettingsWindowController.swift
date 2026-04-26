import AppKit

final class LLMSettingsWindowController: NSWindowController, NSWindowDelegate {
    private var baseURLField: NSTextField!
    private var apiKeyField: NSSecureTextField!
    private var modelField: NSTextField!
    private let llmClient = LLMClient()
    private var testTask: Task<Void, Never>?

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

        let labelTexts = ["API Base URL:", "API Key:", "Model:"]
        let yPositions: [CGFloat] = [152, 112, 72]

        for (i, labelText) in labelTexts.enumerated() {
            let label = NSTextField(labelWithString: labelText)
            label.frame = NSRect(x: 20, y: yPositions[i], width: 110, height: 22)
            label.alignment = .right
            contentView.addSubview(label)
        }

        baseURLField = NSTextField(frame: NSRect(x: 138, y: 152, width: 262, height: 22))
        baseURLField.placeholderString = "https://api.openai.com"
        contentView.addSubview(baseURLField)

        apiKeyField = NSSecureTextField(frame: NSRect(x: 138, y: 112, width: 262, height: 22))
        apiKeyField.placeholderString = "sk-... (enter to change saved key)"
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
        testTask?.cancel()
        let config = LLMClient.Config(
            baseURL: baseURLField.stringValue,
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
