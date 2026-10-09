import Sparkle
import SwiftUI

/// Sparkle auto-update: a daily background check against the appcast attached to the latest GitHub release.
/// Dev builds (version "0.0.0-dev", or no feed in Info.plist) never check.
@MainActor
final class Updates: ObservableObject {
    static let shared = Updates()

    /// Set when a newer version was found; the mascot hops for joy.
    @Published var found = Date.distantPast

    private let delegate = Delegate()
    private(set) var controller: SPUStandardUpdaterController?

    var enabled: Bool { controller != nil }

    private init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        guard info["SUFeedURL"] != nil, !version.contains("dev") else { return }
        delegate.onFound = { [weak self] in Task { @MainActor in self?.found = Date().addingTimeInterval(1.6) } }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: delegate, userDriverDelegate: nil)
    }

    func checkNow() { controller?.checkForUpdates(nil) }

    private final class Delegate: NSObject, SPUUpdaterDelegate {
        var onFound: (() -> Void)?
        func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { onFound?() }
    }
}
