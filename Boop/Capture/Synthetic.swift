//
//  Synthetic.swift
//  Boop
//

import AppKit
import Carbon.HIToolbox

/// Posts synthetic ⌘C / ⌘V into whatever app is frontmost.
enum Synthetic {
    /// Waits for the user to let go of the hot-key chord.
    ///
    /// Posted keystrokes pick up whatever modifiers are physically held down. Boop
    /// is triggered by a Hyper chord, so firing ⌘C too early makes the target app
    /// see ⌃⌥⇧⌘C — which does nothing, and looks exactly like "no text selected".
    static func waitForModifiersToClear() async {
        let chord: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        for _ in 0..<40 {
            if NSEvent.modifierFlags.intersection(chord).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(15))
        }
    }

    private static func makeSource() -> CGEventSource? {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        return source
    }

    static func pressCommand(key: CGKeyCode) {
        let source = makeSource()
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    static func copy() { pressCommand(key: CGKeyCode(kVK_ANSI_C)) }
    static func paste() { pressCommand(key: CGKeyCode(kVK_ANSI_V)) }
}

/// Save/restore of the general pasteboard, so the ⌘C fallback doesn't clobber
/// whatever the user had copied.
struct PasteboardSnapshot {
    private let items: [[String: Data]]

    static func capture() -> PasteboardSnapshot {
        let items = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var stored: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { stored[type.rawValue] = data }
            }
            return stored
        }
        return PasteboardSnapshot(items: items)
    }

    func restore() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items.map { stored in
            let item = NSPasteboardItem()
            for (type, data) in stored {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        })
    }
}
