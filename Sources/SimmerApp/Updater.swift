import AppKit
import Combine
import Sparkle

/// Owns Sparkle's updater for the whole app lifetime.
///
/// Start it once at launch (in the app delegate):
///
///     _ = UpdaterController.shared
///
/// Any view can then ask for an update check without importing Sparkle:
///
///     NotificationCenter.default.post(name: UpdaterController.checkForUpdatesNotification, object: nil)
///
/// The feed URL, the EdDSA public key and the default check schedule live in Resources/Info.plist
/// (SUFeedURL, SUPublicEDKey, SUEnableAutomaticChecks, SUScheduledCheckInterval).
///
/// Sparkle replaces only Simmer.app. The root helper (simmerd) is a separate install, so after an
/// update the app compares `status.helperVersion` with `Simmer.helperVersion` and offers to
/// reinstall the helper when they differ.
@MainActor
final class UpdaterController: NSObject, ObservableObject {
    static let shared = UpdaterController()

    /// Post this (object: nil) to start a user-initiated update check, e.g. from "Check for Updates…".
    nonisolated static let checkForUpdatesNotification = Notification.Name("SimmerCheckForUpdates")

    /// True when Sparkle can start a check now (false while a check or an install is in progress).
    @Published private(set) var canCheckForUpdates = false

    private var controller: SPUStandardUpdaterController!
    private var observers: [NSObjectProtocol] = []
    private var cancellables: Set<AnyCancellable> = []

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: self,
                                                  userDriverDelegate: self)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
            .store(in: &cancellables)
        observers.append(NotificationCenter.default.addObserver(
            forName: Self.checkForUpdatesNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { UpdaterController.shared.checkForUpdates() }
        })
    }

    var updater: SPUUpdater { controller.updater }

    /// Mirrors the "Automatically check for updates" preference (stored by Sparkle in user defaults).
    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    /// Mirrors "Automatically download and install updates".
    var automaticallyDownloadsUpdates: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set {
            objectWillChange.send()
            updater.automaticallyDownloadsUpdates = newValue
        }
    }

    var lastUpdateCheckDate: Date? { updater.lastUpdateCheckDate }

    /// User-initiated check: shows Sparkle's window, also when no update is available.
    func checkForUpdates() {
        // Simmer is a menu bar app (LSUIElement); bring it forward so Sparkle's window is visible.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdaterController: SPUUpdaterDelegate {
    /// Posted just before Sparkle relaunches the new version. The new app then checks the helper version.
    nonisolated static let willRelaunchNotification = Notification.Name("SimmerUpdaterWillRelaunch")

    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        NotificationCenter.default.post(name: Self.willRelaunchNotification, object: nil)
    }
}

// MARK: - SPUStandardUserDriverDelegate

extension UpdaterController: SPUStandardUserDriverDelegate {
    /// A menu bar app has no Dock icon, so scheduled update alerts would otherwise appear behind other
    /// windows. Opting in to gentle reminders lets Sparkle show them politely; we bring the app forward.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                               forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        guard handleShowingUpdate else { return }
        DispatchQueue.main.async { NSApp.activate(ignoringOtherApps: true) }
    }
}
