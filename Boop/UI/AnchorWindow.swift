//
//  AnchorWindow.swift
//  Boop
//

import AppKit

/// An invisible panel laid over the selected text.
///
/// `NSPopover` can only anchor to an `NSView` inside one of our own windows, but
/// the text being improved belongs to some other app. Parking a transparent
/// panel on the selection's rectangle gives the popover something to point its
/// notch at.
///
/// It's a `.nonactivatingPanel` so showing it never takes focus from the app the
/// user is typing in — activating would grey out the very selection Boop is
/// about to replace.
final class AnchorWindow: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        // Never intercept clicks meant for the app underneath.
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        contentView = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
