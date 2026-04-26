import AppKit
import Carbon

final class TextInjector {
    func inject(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let savedItems: [NSPasteboardItem] = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }

        let originalSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let isCJK = detectCJK(source: originalSource)
        if isCJK { switchToASCII() }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.simulatePaste()

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
        guard let cfList = TISCreateInputSourceList(filter, false) else { return }
        let list = cfList.takeRetainedValue() as! CFArray
        guard CFArrayGetCount(list) > 0 else { return }
        let ptr = CFArrayGetValueAtIndex(list, 0)!
        let ascii = Unmanaged<TISInputSource>.fromOpaque(ptr).takeUnretainedValue()
        TISSelectInputSource(ascii)
        Thread.sleep(forTimeInterval: 0.05)
    }

    private func simulatePaste() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let keyV: CGKeyCode = 0x09

        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyV, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: keyV, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
