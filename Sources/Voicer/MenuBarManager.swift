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

        // Clipboard History submenu
        let historyMenu = NSMenu()
        historyMenu.delegate = self
        let historyItem = NSMenuItem(title: "Clipboard History", action: nil, keyEquivalent: "")
        historyItem.submenu = historyMenu
        menu.addItem(historyItem)

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
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.orderFrontRegardless()
    }

    @objc private func settingsWindowClosed() {
        settingsWindowController = nil
    }

    @objc private func copyHistoryItem(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int,
              index < ClipboardHistory.shared.entries.count else { return }
        let text = ClipboardHistory.shared.entries[index].text
        ClipboardHistory.shared.copyToClipboard(text)
    }

    @objc private func clearHistory() {
        ClipboardHistory.shared.clear()
    }
}

extension MenuBarManager: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let entries = ClipboardHistory.shared.entries

        if entries.isEmpty {
            let emptyItem = NSMenuItem(title: "No history yet", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for (index, entry) in entries.prefix(20).enumerated() {
                let preview = String(entry.text.prefix(60)).replacingOccurrences(of: "\n", with: " ")
                let item = NSMenuItem(title: preview, action: #selector(copyHistoryItem(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = index
                item.toolTip = entry.text
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        if !entries.isEmpty {
            let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)
        }
    }
}