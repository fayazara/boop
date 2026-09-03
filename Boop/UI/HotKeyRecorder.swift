//
//  HotKeyRecorder.swift
//  Boop
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click, then press a shortcut. Records the raw key code plus modifiers so the
/// Carbon hot key can be re-registered.
struct HotKeyRecorder: View {
    @Bindable var settings: BoopSettings

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var isTaken = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggle) {
                Text(label)
                    .font(.system(size: 12, design: isRecording ? .default : .monospaced))
                    .foregroundStyle(isRecording ? Color.secondary : Color.primary)
                    .frame(minWidth: 130)
                    .padding(.vertical, 3)
            }

            if KeyCodes.isHyper(settings.hotKeyModifiers) {
                Text("Hyper")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
            }

            if isTaken {
                Label("In use by another app", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onAppear { isTaken = !HotKeyManager.shared.isTriggerRegistered }
        .onDisappear(perform: stop)
    }

    private var label: String {
        isRecording
            ? "Press a shortcut…"
            : KeyCodes.description(code: settings.hotKeyCode, modifiers: settings.hotKeyModifiers)
    }

    private func toggle() {
        isRecording ? stop() : start()
    }

    private func start() {
        isRecording = true
        // Otherwise the live hot key eats the very chord we're trying to record.
        HotKeyManager.shared.suspendTrigger()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                stop()
                return nil
            }
            let modifiers = KeyCodes.carbonModifiers(from: event.modifierFlags)
            // A bare key would fire constantly; require at least one modifier.
            guard modifiers != 0 else { return nil }

            settings.hotKeyCode = UInt32(event.keyCode)
            settings.hotKeyModifiers = modifiers
            stop()
            return nil
        }
    }

    private func stop() {
        guard isRecording else { return }
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        // Registration fails when something else already owns the chord — Raycast
        // still holding Hyper+A, for instance.
        isTaken = !HotKeyManager.shared.reload()
    }
}
