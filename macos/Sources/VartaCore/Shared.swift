import Foundation

/// What the app hands the desktop widget: a small file in the shared app group.
///
/// The widget cannot poll the feed itself, and the app can be quit, crash or be
/// asleep. So the snapshot carries `trustedUntil`, and past it the widget says
/// "not watching" on its own: a widget left showing "calm" from a dead app is
/// exactly the silence this project exists to rule out.
public struct Shared: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case unset, starting, calm, alert, lost
    }

    public var region: String
    public var kind: Kind
    public var since: Date?
    public var reason: String?
    /// Past this, nothing in the snapshot may be believed.
    public var trustedUntil: Date?
    public var summary: Summary
    public var writtenAt: Date

    public init(region: String, kind: Kind, since: Date?, reason: String?, trustedUntil: Date?,
                summary: Summary, writtenAt: Date) {
        self.region = region
        self.kind = kind
        self.since = since
        self.reason = reason
        self.trustedUntil = trustedUntil
        self.summary = summary
        self.writtenAt = writtenAt
    }

    /// From the app's monitor, at a moment.
    public init(monitor: Monitor, summary: Summary, now: Date) {
        let status = monitor.status(at: now)
        let watch = monitor.watch
        var until: Date?
        if let last = watch.lastOK {
            until = last.fetchedAt.addingTimeInterval(staleAfter)
            if let source = last.sourceTime {
                until = min(until!, source.addingTimeInterval(staleAfter))
            }
        }
        let (kind, since, reason): (Kind, Date?, String?) = switch status {
        case .unset: (.unset, nil, nil)
        case .starting: (.starting, nil, nil)
        case .calm: (.calm, nil, nil)
        case .alert(let since): (.alert, since, nil)
        case .notWatching(let why): (.lost, nil, why)
        }
        self.init(region: monitor.region, kind: kind, since: since, reason: reason,
                  trustedUntil: until, summary: summary, writtenAt: now)
    }

    /// When the app last had a reading it trusted.
    public var checkedAt: Date? { trustedUntil.map { $0.addingTimeInterval(-staleAfter) } }

    /// What the widget may show at `date`. Calm and alert both expire.
    ///
    /// `slack` is for the widget: WidgetKit refreshes on its own budget, minutes
    /// late at best, so a widget that expired on the menu bar's four minutes
    /// would cry "not watching" most of the time. It shows "checked at" instead,
    /// and only gives up once the app has clearly stopped.
    public func shown(at date: Date, slack: TimeInterval = 0) -> (kind: Kind, reason: String?) {
        switch kind {
        case .calm, .alert:
            if let trustedUntil, date >= trustedUntil.addingTimeInterval(slack) {
                return (.lost, "Varta has not read the feed since \(trustedUntil.addingTimeInterval(-staleAfter).formatted(date: .omitted, time: .shortened))")
            }
            return (kind, nil)
        case .starting:
            // Starting is a moment, not a state to sit in.
            if date.timeIntervalSince(writtenAt) > Monitor.grace + 60 + slack {
                return (.lost, "Varta has not been heard from")
            }
            return (kind, nil)
        default:
            return (kind, reason)
        }
    }

    public static let fileName = "shared.json"

    public func write(to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        try data.write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }

    public static func read(from directory: URL) -> Shared? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)) else { return nil }
        return try? decoder.decode(Shared.self, from: data)
    }
}
