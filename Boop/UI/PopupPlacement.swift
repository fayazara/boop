//
//  PopupPlacement.swift
//  Boop
//

import AppKit

enum PopupPlacement {
    static let size = NSSize(width: 400, height: 300)

    /// Turns whatever the Accessibility API gave us into a small on-screen
    /// rectangle for the popover to point at.
    ///
    /// `NSPopover` picks the edge and flips itself when space runs out, so all
    /// this has to do is produce a rect that is small, real, and on a screen.
    ///
    /// The pointer is used only when there is genuinely nothing else. Someone who
    /// selects text with the keyboard — or just moves the mouse afterwards —
    /// leaves it nowhere near the words being rewritten.
    static func anchorRect(for bounds: NSRect?, kind: AnchorKind) -> NSRect {
        guard let rect = valid(bounds) else { return pointRect(NSEvent.mouseLocation) }

        switch kind {
        case .glyphs:
            return clamped(rect)
        case .element:
            return clamped(firstLine(of: rect))
        case .window:
            // A whole window says nothing about where the text sits, so here the
            // pointer really is the better signal — if it's even in the window.
            let mouse = NSEvent.mouseLocation
            return clamped(rect.contains(mouse) ? pointRect(mouse) : topLeading(of: rect))
        case .unknown:
            return clamped(pointRect(NSEvent.mouseLocation))
        }
    }

    /// A control can be a wide text area. Aim at its first line, where a short
    /// selection almost always is, rather than the middle of its bottom edge.
    private static func firstLine(of rect: NSRect) -> NSRect {
        guard rect.width > 240 || rect.height > 44 else { return rect }
        let lineHeight: CGFloat = 20
        return NSRect(
            x: rect.minX,
            y: rect.maxY - lineHeight,
            width: min(rect.width, 240),
            height: lineHeight
        )
    }

    private static func topLeading(of rect: NSRect) -> NSRect {
        NSRect(x: rect.minX, y: rect.maxY - 1, width: 1, height: 1)
    }

    private static func pointRect(_ point: NSPoint) -> NSRect {
        NSRect(x: point.x, y: point.y, width: 1, height: 1)
    }

    /// Rejects empty rects and the absurd ones some apps report for large selections.
    private static func valid(_ bounds: NSRect?) -> NSRect? {
        guard let bounds, bounds.width < 6000, bounds.height < 6000,
              bounds.width > 0 || bounds.height > 0
        else { return nil }
        return NSRect(
            x: bounds.minX,
            y: bounds.minY,
            width: max(bounds.width, 1),
            height: max(bounds.height, 1)
        )
    }

    private static func clamped(_ rect: NSRect) -> NSRect {
        guard let screen = screen(containing: rect) else { return rect }
        let visible = screen.visibleFrame
        return NSRect(
            x: min(max(rect.minX, visible.minX), visible.maxX - rect.width),
            y: min(max(rect.minY, visible.minY), visible.maxY - rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    private static func screen(containing rect: NSRect) -> NSScreen? {
        let point = NSPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.screens.first { $0.frame.intersects(rect) }
            ?? NSScreen.main
    }
}
