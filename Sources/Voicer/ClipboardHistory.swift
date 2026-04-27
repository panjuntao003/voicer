import AppKit

struct ClipboardEntry: Codable {
    let text: String
    let timestamp: Date
}

final class ClipboardHistory {
    static let shared = ClipboardHistory()
    private let maxEntries = 100
    private let defaults = UserDefaults.standard
    private let key = "voicer.clipboardHistory"

    private(set) var entries: [ClipboardEntry] = []

    init() {
        load()
    }

    func add(_ text: String) {
        guard !text.isEmpty else { return }
        let entry = ClipboardEntry(text: text, timestamp: Date())
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: NSPasteboard.PasteboardType.string)
    }

    func delete(at index: Int) {
        guard index >= 0 && index < entries.count else { return }
        entries.remove(at: index)
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ClipboardEntry].self, from: data) else {
            entries = []
            return
        }
        entries = decoded
    }
}