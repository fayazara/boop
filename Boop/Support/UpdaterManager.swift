//
//  UpdaterManager.swift
//  Boop
//

import AppKit
import Combine
import Foundation
import Sparkle

/// Manages the Sparkle auto-update lifecycle.
///
/// `SPUStandardUpdaterController` has to exist before `applicationDidFinishLaunching`
/// returns so the scheduled check starts on the right footing.
@MainActor
final class UpdaterManager: NSObject, ObservableObject {
    static let shared = UpdaterManager()

    /// Assigned after `super.init()` so the user-driver delegate can be `self`.
    private var controller: SPUStandardUpdaterController!

    @Published var canCheckForUpdates = false

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var currentVersion: String {
        let bundle = Bundle.main
        let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func start() {
        #if DEBUG
        return
        #else
        controller.startUpdater()
        #endif
    }

    func checkForUpdates() {
        #if DEBUG
        return
        #else
        // Boop is an accessory app with no Dock icon, so Sparkle's windows would
        // otherwise open behind everything. Restored in the delegate below.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        controller.checkForUpdates(nil)
        #endif
    }
}

extension UpdaterManager: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Drop back to being a menu-bar-only app once the update UI is done, so
    /// checking for updates doesn't leave a Dock icon behind for good.
    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
