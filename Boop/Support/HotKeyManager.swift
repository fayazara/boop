//
//  HotKeyManager.swift
//  Boop
//

import AppKit
import Carbon.HIToolbox

/// Carbon's `RegisterEventHotKey` is used rather than an `NSEvent` global monitor
/// because it actually swallows the keystroke instead of letting it fall through
/// to whatever app you were typing in.
///
/// That matters twice over: for the trigger chord, and for the Return key that
/// confirms a result. Boop is never the active app, so a plain event monitor
/// would paste *and* leave a newline behind in the field.
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onTrigger: (() -> Void)?
    var onConfirm: (() -> Void)?

    private var triggerRef: EventHotKeyRef?
    private var confirmRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private let signature = OSType(0x424F_4F50) // 'BOOP'
    private enum ID: UInt32 { case trigger = 1, confirm = 2 }

    private init() {}

    // MARK: - Trigger chord

    var isTriggerRegistered: Bool { triggerRef != nil }

    /// Releases the trigger chord so it can be typed rather than acted on.
    ///
    /// Carbon hot keys swallow their keystroke, so a live Hyper+A would fire the
    /// popup instead of ever reaching the shortcut recorder — making it
    /// impossible to re-record the shortcut you already have. Call `reload()` to
    /// put it back.
    func suspendTrigger() {
        if let triggerRef { UnregisterEventHotKey(triggerRef) }
        triggerRef = nil
    }

    /// Registers the hot key currently stored in settings, replacing any previous one.
    @discardableResult
    func reload() -> Bool {
        if let triggerRef { UnregisterEventHotKey(triggerRef) }
        triggerRef = nil
        installHandlerIfNeeded()

        let settings = BoopSettings.shared
        guard settings.hotKeyModifiers != 0 else { return false }
        triggerRef = register(
            code: settings.hotKeyCode, modifiers: settings.hotKeyModifiers, id: .trigger
        )
        return triggerRef != nil
    }

    // MARK: - Return to confirm

    /// Claims the Return key while a finished result is on screen. Kept as narrow
    /// as possible — nothing else on the system can use Return until it's released.
    func enableConfirmKey() {
        guard confirmRef == nil else { return }
        installHandlerIfNeeded()
        confirmRef = register(code: UInt32(kVK_Return), modifiers: 0, id: .confirm)
    }

    func disableConfirmKey() {
        if let confirmRef { UnregisterEventHotKey(confirmRef) }
        confirmRef = nil
    }

    func unregisterAll() {
        if let triggerRef { UnregisterEventHotKey(triggerRef) }
        triggerRef = nil
        disableConfirmKey()
    }

    // MARK: - Plumbing

    private func register(code: UInt32, modifiers: UInt32, id: ID) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id.rawValue)
        let status = RegisterEventHotKey(
            code, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref
        )
        return status == noErr ? ref : nil
    }

    fileprivate func fire(id: UInt32) {
        switch ID(rawValue: id) {
        case .trigger: onTrigger?()
        case .confirm: onConfirm?()
        case nil: break
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), boopHotKeyCallback, 1, &spec, nil, &handlerRef)
    }
}

/// Carbon hands us a bare C function pointer, so this cannot capture anything.
private nonisolated func boopHotKeyCallback(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return noErr }

    let id = hotKeyID.id
    DispatchQueue.main.async {
        MainActor.assumeIsolated { HotKeyManager.shared.fire(id: id) }
    }
    return noErr
}
