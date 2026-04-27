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
