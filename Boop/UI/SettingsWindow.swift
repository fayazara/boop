//
//  SettingsWindow.swift
//  Boop
//

import AppKit
import SwiftUI

/// Boop is a menu-bar agent, so it owns its settings window directly rather than
/// relying on the standard `Settings` scene.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func open() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let created = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        created.title = "Boop Settings"
        created.isReleasedWhenClosed = false
        created.contentView = NSHostingView(rootView: SettingsView())
        created.center()
        window = created

        NSApp.activate(ignoringOtherApps: true)
        created.makeKeyAndOrderFront(nil)
    }
}
