//
//  PopupController.swift
//  Boop
//

import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI

@MainActor
@Observable
final class PopupController {
    static let shared = PopupController()

    private(set) var original = ""
    private(set) var output = ""
    private(set) var isStreaming = false
    private(set) var isReasoning = false
    private(set) var errorMessage: String?
    private(set) var modelName = ""
    private(set) var didCopy = false
    /// Name of the app the text came from, e.g. "Google Chrome".
    private(set) var targetAppName: String?

    @ObservationIgnored private var popover: NSPopover?
    @ObservationIgnored private var anchorWindow: AnchorWindow?
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var sourceApp: NSRunningApplication?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var globalKeyMonitor: Any?
    @ObservationIgnored private var clickMonitor: Any?
    @ObservationIgnored private lazy var popoverDelegate = PopoverDelegate { [weak self] in
        self?.teardown()
    }

    private init() {}

    var canAct: Bool { !output.isEmpty && !isStreaming }

    // MARK: - Entry point

    /// Called when the global hot key fires.
    func trigger() {
        guard AccessibilityPermission.isGranted else {
            AccessibilityPermission.request()
            return
        }
        guard BoopSettings.shared.isConfigured else {
            SettingsWindow.open()
            return
        }

        // Remember who to hand focus (and the paste) back to. If Boop somehow is
        // frontmost, there's no foreign selection to read.
        let frontmost = NSWorkspace.shared.frontmostApplication
        guard frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        sourceApp = frontmost
        targetAppName = frontmost?.localizedName

        Task {
            guard let selection = await TextCapture.capture() else {
                present(anchoredTo: nil, kind: .unknown)
                fail("Select some text first, then press the Boop hot key.")
                return
            }
            original = selection.text
            present(anchoredTo: selection.anchor, kind: selection.anchorKind)
            start()
        }
    }

    // MARK: - Streaming

    func regenerate() {
        guard !original.isEmpty else { return }
        start()
    }

    private func start() {
        streamTask?.cancel()
        output = ""
        errorMessage = nil
        didCopy = false
        isStreaming = true
        HotKeyManager.shared.disableConfirmKey()

        let settings = BoopSettings.shared
        modelName = settings.model.name
        let client = GatewayClient(settings: settings)
        let prompt = settings.prompt
        let model = settings.modelID
        let effort = settings.reasoningEffort
        let text = original
        isReasoning = effort != .default

        streamTask = Task {
            do {
                let deltas = client.stream(
                    model: model, system: prompt, user: text, effort: effort
                )
                // Tokens arrive far faster than the display refreshes. Appending
                // each one straight to `output` makes SwiftUI update several times
                // per frame, which trips a runtime issue — and a runtime issue
                // pulls Xcode to the front, stealing focus mid-stream.
                var pending = ""
                var lastFlush = ContinuousClock.now
                for try await delta in deltas {
                    pending += delta
                    if ContinuousClock.now - lastFlush >= .milliseconds(50) {
                        output += pending
                        pending = ""
                        lastFlush = ContinuousClock.now
                    }
                }
                if !pending.isEmpty { output += pending }
                isStreaming = false
                if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    errorMessage = "The model returned an empty response."
                } else {
                    HotKeyManager.shared.enableConfirmKey()
                }
            } catch {
                isStreaming = false
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    private func fail(_ message: String) {
        streamTask?.cancel()
        HotKeyManager.shared.disableConfirmKey()
        isStreaming = false
        original = ""
        output = ""
        didCopy = false
        errorMessage = message
    }

    // MARK: - Actions

    func copyOutput() {
        guard canAct else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmedOutput, forType: .string)
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            didCopy = false
        }
    }

    /// Puts the text on the pasteboard, gives focus back to the original app and
    /// sends it a ⌘V so the improved text replaces the selection.
    func pasteOutput() {
        guard canAct else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmedOutput, forType: .string)

        let app = sourceApp
        dismiss()

        Task {
            // Same trap as the ⌘C capture: a held modifier would turn ⌘V into
            // something else entirely.
            await Synthetic.waitForModifiersToClear()
            app?.activate()
            try? await Task.sleep(for: .milliseconds(120))
            Synthetic.paste()
        }
    }

    /// "Paste into Google Chrome" when we know where the text came from.
    var pasteLabel: String {
        guard let name = targetAppName, !name.isEmpty else { return "Paste" }
        return "Paste into \(name)"
    }

    private var trimmedOutput: String {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Presentation

    private func present(anchoredTo bounds: NSRect?, kind: AnchorKind) {
        let rect = PopupPlacement.anchorRect(for: bounds, kind: kind)

        let window = anchorWindow ?? AnchorWindow()
        anchorWindow = window
        window.setFrame(rect, display: false)
        window.contentView?.frame = NSRect(origin: .zero, size: rect.size)
        window.orderFrontRegardless()

        guard let view = window.contentView else { return }
        let popover = self.popover ?? makePopover()
        self.popover = popover

        // Deliberately no NSApp.activate(): taking focus greys out the selection
        // Boop is about to replace, and drags our other windows forward.
        if !popover.isShown {
            // Prefer hanging below the selection; the popover flips itself when
            // it runs out of room and keeps its notch on the text either way.
            popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
        // NSPopover builds its own window; make that one non-activating too so a
        // click on Copy or Paste doesn't yank focus away from the source app.
        if let popoverWindow = popover.contentViewController?.view.window as? NSPanel {
            popoverWindow.styleMask.insert(.nonactivatingPanel)
            popoverWindow.becomesKeyOnlyIfNeeded = true
        }
        popover.contentViewController?.view.window?.orderFrontRegardless()
        installDismissMonitors()
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.contentSize = PopupPlacement.size
        // `.transient` closes whenever our app stops being active — but Boop is
        // never active by design, and anything stealing focus mid-stream would
        // make the popup vanish. Dismissal is handled explicitly instead.
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = popoverDelegate

        let host = NSHostingController(rootView: PopupView(controller: self))
        host.preferredContentSize = PopupPlacement.size
        popover.contentViewController = host
        return popover
    }

    func dismiss() {
        if popover?.isShown == true { popover?.performClose(nil) }
        teardown()
    }

    /// Idempotent — reached both from `dismiss()` and from the popover closing
    /// itself when the user clicks away.
    private func teardown() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        // Release Return the moment the popup goes away — nothing else on the
        // system can use that key while it's claimed.
        HotKeyManager.shared.disableConfirmKey()
        removeDismissMonitors()
        anchorWindow?.orderOut(nil)
    }

    /// Boop isn't the active app while the popup is up, so Escape has to be caught
    /// globally; the local monitor covers the case where a click did focus us.
    private func installDismissMonitors() {
        removeDismissMonitors()

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Int(event.keyCode) == kVK_Escape else { return }
            self?.dismiss()
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Int(event.keyCode) == kVK_Escape else { return event }
            self?.dismiss()
            return nil
        }
        // Global mouse monitors only see clicks in *other* apps, so this dismisses
        // on a click away without swallowing clicks on our own buttons.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func removeDismissMonitors() {
        for monitor in [keyMonitor, globalKeyMonitor, clickMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        keyMonitor = nil
        globalKeyMonitor = nil
        clickMonitor = nil
    }
}

/// `@Observable` types can't also be `NSObject` subclasses, so the popover's
/// delegate lives here.
private final class PopoverDelegate: NSObject, NSPopoverDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func popoverDidClose(_ notification: Notification) {
        onClose()
    }
}
