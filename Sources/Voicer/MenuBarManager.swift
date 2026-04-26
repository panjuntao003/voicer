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
