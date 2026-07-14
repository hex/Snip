// ABOUTME: Wraps Sparkle's SPUStandardUpdaterController for menu-triggered and automatic update checks.
// ABOUTME: Exposes the auto-check flag as observable state for the settings toggle.
import Foundation
import Observation
@preconcurrency import Sparkle

@MainActor
@Observable
final class UpdaterController {
    @ObservationIgnored private let controller: SPUStandardUpdaterController

    /// Mirrors Sparkle's setting so SwiftUI observes changes; Sparkle persists the value itself.
    var automaticallyChecksForUpdates: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
