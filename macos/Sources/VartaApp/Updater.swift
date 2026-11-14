import Foundation
import Sparkle

/// "Check for Updates…" for the download. Off when the bundle has no feed
/// (the App Store build, `swift build`, the tests): Sparkle would otherwise
/// greet each launch with "the updater failed to start".
@MainActor
final class Updater {
    private let controller: SPUStandardUpdaterController?

    init(bundle: Bundle = .main) {
        let hasFeed = (bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String).map { !$0.isEmpty } ?? false
        let hasKey = (bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String).map { !$0.hasPrefix("PLACEHOLDER") } ?? false
        controller = hasFeed && hasKey
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
    }

    var available: Bool { controller != nil }

    func check() { controller?.checkForUpdates(nil) }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }
}
