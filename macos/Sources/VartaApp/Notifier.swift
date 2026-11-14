import Foundation
import os
import UserNotifications

let log = Logger(subsystem: "app.duduphudu.varta", category: "notify")

/// macOS notifications. The alert and "not watching" are time-sensitive so they
/// can break through Focus once the user allows it; a clear or an alert
/// elsewhere is ordinary. Sound is played by the app, not the notification, so
/// it can repeat and stop with the alert.
@MainActor
final class Notifier {
    enum Kind {
        case alert(region: String)
        case clear(region: String)
        case elsewhere(regions: [String])
        case lost(reason: String)
        case rehearsal(region: String)
    }

    private let delegate = Delegate()
    /// Notifications need a real bundle; the bare SwiftPM binary has none, and
    /// UNUserNotificationCenter crashes without one.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    init() {
        center?.delegate = delegate
    }

    func authorize() async -> Bool? {
        guard let center else { return nil }
        let granted = try? await center.requestAuthorization(options: [.alert, .sound])
        let settings = await center.notificationSettings()
        log.notice("authorized=\(granted ?? false) status=\(settings.authorizationStatus.rawValue) alertStyle=\(settings.alertStyle.rawValue) timeSensitive=\(settings.timeSensitiveSetting.rawValue)")
        return granted
    }

    func post(_ kind: Kind) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        let id: String
        switch kind {
        case .alert(let region):
            content.title = "ПОВІТРЯНА ТРИВОГА"
            content.body = region
            content.interruptionLevel = .timeSensitive
            id = "alert"
        case .clear(let region):
            content.title = "Відбій тривоги"
            content.body = region
            content.interruptionLevel = .active
            id = "alert" // replaces the alert, so the list shows what is true now
        case .elsewhere(let regions):
            content.title = "Тривога: " + regions.joined(separator: ", ")
            content.body = "A place you keep an eye on"
            content.interruptionLevel = .active
            id = "elsewhere"
        case .lost(let reason):
            content.title = "Varta is not watching"
            content.body = "Your region is not being checked: \(reason). Silence from Varta does not mean calm right now."
            content.interruptionLevel = .timeSensitive
            id = "lost"
        case .rehearsal(let region):
            content.title = "ТЕСТ · ПОВІТРЯНА ТРИВОГА"
            content.body = "A rehearsal for \(region). Nothing is happening."
            // The same path as a real alert, Focus included: a rehearsal that
            // Focus can hold back proves nothing about the night.
            content.interruptionLevel = .timeSensitive
            id = "rehearsal"
        }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        Task {
            do {
                try await center.add(request)
                log.notice("posted \(id, privacy: .public)")
            } catch {
                log.error("post \(id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func withdrawLost() {
        center?.removeDeliveredNotifications(withIdentifiers: ["lost"])
    }

    /// A menu bar app counts as frontmost often enough that, without this, its
    /// own alerts would be swallowed silently.
    final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
            -> UNNotificationPresentationOptions {
            [.banner, .list]
        }
    }
}
