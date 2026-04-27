import AppKit

final class MenuBarManager: NSObject {
    private var statusItem: NSStatusItem!
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

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Voicer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    @objc private func openSettings() {
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
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.settingsWindowController?.window?.makeFirstResponder(nil)
        }
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