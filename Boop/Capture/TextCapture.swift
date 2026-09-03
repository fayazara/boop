//
//  TextCapture.swift
//  Boop
//

import AppKit
import ApplicationServices

/// How much the anchor rectangle actually tells us about where the text is.
enum AnchorKind {
    /// The rect of the selected glyphs. Point straight at it.
    case glyphs
    /// The focused control. The selection is somewhere inside it.
    case element
    /// Just the app's window — barely narrows anything down.
    case window
    /// Nothing at all.
    case unknown
}

/// What Boop managed to grab when the hot key fired.
struct Selection {
    let text: String
    /// Where to point the popover, in AppKit screen coordinates (origin
    /// bottom-left), or nil when nothing could be worked out at all.
    let anchor: NSRect?
    let anchorKind: AnchorKind
}

enum TextCapture {
    /// Reads the current selection, preferring the Accessibility API and falling
    /// back to a ⌘C round-trip for apps (Electron, some web views) that don't
    /// expose `AXSelectedText`.
    static func capture() async -> Selection? {
        let app = frontmostAppElement()
        let focused = focusedElement(in: app)
        if let focused { AXUIElementSetMessagingTimeout(focused, 0.4) }

        // Best case: the exact rect of the selected glyphs. Plenty of controls
        // (Xcode's search field among them) don't implement AXBoundsForRange, so
        // fall back to the focused control, then to its window.
        let anchor: (NSRect, AnchorKind)? =
            focused.flatMap(selectionBounds).map { ($0, .glyphs) }
            ?? focused.flatMap(elementFrame).map { ($0, .element) }
            ?? app.flatMap(focusedWindowFrame).map { ($0, .window) }

        let rect = anchor?.0
        let kind = anchor?.1 ?? .unknown

        if let focused,
           let text = attribute(focused, kAXSelectedTextAttribute) as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Selection(text: text, anchor: rect, anchorKind: kind)
        }

        if let copied = await copyViaPasteboard() {
            return Selection(text: copied, anchor: rect, anchorKind: kind)
        }
        return nil
    }

    /// The frontmost app's AX element, with Chromium's full accessibility tree
    /// switched on.
    ///
    /// Chrome, Electron and friends ship a stub AX tree until a client asks for
    /// the real one by setting `AXManualAccessibility`. Without it there is no
    /// focused element and no text bounds, which is why Boop used to fall all the
    /// way through to the mouse pointer in a Chrome text box. Other apps just
    /// reject the attribute, which is harmless.
    private static func frontmostAppElement() -> AXUIElement? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.4)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return app
    }

    /// The system-wide query is cheapest, but comes back empty for apps that only
    /// just enabled accessibility — so ask the app itself as well.
    private static func focusedElement(in app: AXUIElement?) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.4)
        if let focused = element(system, kAXFocusedUIElementAttribute) { return focused }
        return app.flatMap { element($0, kAXFocusedUIElementAttribute) }
    }

    private static func focusedWindowFrame(_ app: AXUIElement) -> NSRect? {
        guard let window = element(app, kAXFocusedWindowAttribute) else { return nil }
        return elementFrame(window)
    }

    // MARK: - Accessibility

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func element(_ parent: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(parent, name), CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    /// Asks the focused element for the on-screen rectangle of its selected range.
    private static func selectionBounds(_ element: AXUIElement) -> NSRect? {
        guard let rangeValue = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(rangeValue) == AXValueGetTypeID()
        else { return nil }

        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range), range.length > 0 else {
            return nil
        }

        // Long selections often report a rect spanning the whole block. Asking about
        // the first chunk keeps the anchor near where the user is actually looking.
        var probe = CFRange(location: range.location, length: min(range.length, 1))
        guard let probeValue = AXValueCreate(.cfRange, &probe) else { return nil }

        var result: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            probeValue,
            &result
        ) == .success, let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(result as! AXValue, .cgRect, &rect), rect.width.isFinite,
              rect.height.isFinite, rect.height > 0
        else { return nil }
        // A single glyph can legitimately report zero width.
        rect.size.width = max(rect.width, 1)
        return convertFromAX(rect)
    }

    private static func elementFrame(_ element: AXUIElement) -> NSRect? {
        guard let value = attribute(element, "AXFrame"), CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect), !rect.isEmpty else { return nil }
        return convertFromAX(rect)
    }

    /// Accessibility reports top-left-origin coordinates relative to the display
    /// whose origin is (0,0); AppKit wants bottom-left origin.
    private static func convertFromAX(_ rect: CGRect) -> NSRect {
        let zeroScreen = NSScreen.screens.first { $0.frame.origin == .zero }
            ?? NSScreen.screens.first
        guard let zeroScreen else { return rect }
        return NSRect(
            x: rect.origin.x,
            y: zeroScreen.frame.maxY - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    // MARK: - Pasteboard fallback

    private static func copyViaPasteboard() async -> String? {
        await Synthetic.waitForModifiersToClear()

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture()
        let changeCountBefore = pasteboard.changeCount

        Synthetic.copy()

        // Apps answer ⌘C on their own schedule; poll briefly rather than guessing.
        var copied: String?
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(20))
            if pasteboard.changeCount != changeCountBefore {
                copied = pasteboard.string(forType: .string)
                break
            }
        }

        snapshot.restore()

        guard let copied, !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return copied
    }
}
