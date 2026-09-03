//
//  BoopApp.swift
//  Boop
//
//  Created by Fayaz Ahmed Aralikatti on 03/09/26.
//

import AppKit
import SwiftUI

@main
struct BoopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Bindable private var settings = BoopSettings.shared

    var body: some Scene {
        MenuBarExtra("Boop", image: "BoopMark") {
            Button("Improve Selection") { PopupController.shared.trigger() }
            Text(KeyCodes.description(code: settings.hotKeyCode, modifiers: settings.hotKeyModifiers))
            Divider()
            Button("Settings…") { SettingsWindow.open() }
            Divider()
            Button("Quit Boop") { NSApp.terminate(nil) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        HotKeyManager.shared.onTrigger = { PopupController.shared.trigger() }
        HotKeyManager.shared.onConfirm = { PopupController.shared.pasteOutput() }
        HotKeyManager.shared.reload()

        if !AccessibilityPermission.isGranted {
            AccessibilityPermission.request()
        } else if !BoopSettings.shared.isConfigured {
            SettingsWindow.open()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregisterAll()
    }
}
