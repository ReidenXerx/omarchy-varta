import Foundation

// Port of app/watchcore.py: deciding what to believe about the feed.
//
// The rule the whole design turns on: silence must never be ambiguous. "No
// alert" and "I cannot see the feed" look identical on a screen, and one of them
// can get somebody hurt, so anything other than a fresh, successful reading is a
// state the interface has to show as loudly as an alert.

/// The feed caches upstream for about a minute, so a reading older than this is
/// not a network blip: something has stopped.
public let staleAfter: TimeInterval = 4 * 60
/// Past this with no successful reading at all, the app is not watching anything
/// and must stop implying that it is.
public let blindAfter: TimeInterval = 8 * 60

public enum Health: String, Sendable, Equatable {
    case ok, stale, blind
}

/// One successful answer from the feed.
public struct Reading: Sendable, Equatable {
    public var fetchedAt: Date
    /// When the feed says its cache was made. A fresh answer can carry an old
    /// cache, and that is how a frozen feed shows itself.
    public var sourceTime: Date?
    public var alerting: Set<String>

    public init(fetchedAt: Date, sourceTime: Date?, alerting: Set<String>) {
        self.fetchedAt = fetchedAt
        self.sourceTime = sourceTime
        self.alerting = alerting
    }
}

/// A place being kept an eye on. `alert` is nil when the watch cannot vouch for
/// anything: not knowing is its own answer.
public struct Elsewhere: Sendable, Equatable {
    public var region: String
    public var alert: Bool?
    public var since: Date?
}

/// What the poller knows, updated reading by reading.
///
/// `region` is where you are: the one that earns a notification that breaks
/// through. `others` are places you keep an eye on (family, friends), worth
/// knowing about without being interrupted for.
public struct Watch: Sendable {
    public var region: String
    public var others: [String]
    public private(set) var lastOK: Reading?
    public private(set) var lastAttempt: Date?
    public private(set) var consecutiveFailures = 0
    /// When this app first saw each alert begin. The free feed's own `changed`
    /// field is the epoch for most regions, so "seen since" is the honest best.
    public private(set) var seenSince: [String: Date] = [:]

    public init(region: String, others: [String] = []) {
        self.region = region
        self.others = others
    }

    public mutating func observe(_ reading: Reading) {
        let previous = lastOK?.alerting ?? []
        let watched = Set([region] + others)
        for r in reading.alerting.subtracting(previous).intersection(watched) {
            seenSince[r] = reading.fetchedAt
        }
        for r in previous.subtracting(reading.alerting).intersection(watched) {
            seenSince[r] = nil
        }
        lastOK = reading
        lastAttempt = reading.fetchedAt
        consecutiveFailures = 0
    }

    public mutating func failed(at when: Date) {
        lastAttempt = when
        consecutiveFailures += 1
    }

    /// Never optimistic: the older the evidence, the less it claims.
    public func health(at now: Date) -> Health {
        guard let last = lastOK else { return .blind }
        let age = now.timeIntervalSince(last.fetchedAt)
        if age >= blindAfter { return .blind }
        if age >= staleAfter { return .stale }
        // A reading can arrive fresh and still carry an old cache behind it.
        if let sourceAge = sourceAge(at: now), sourceAge >= staleAfter { return .stale }
        return .ok
    }

    public func sourceAge(at now: Date) -> TimeInterval? {
        guard let source = lastOK?.sourceTime else { return nil }
        return now.timeIntervalSince(source)
    }

    public func alerting(in region: String) -> Bool {
        lastOK?.alerting.contains(region) ?? false
    }

    /// True, false, or nil for "I cannot see". Only ever true or false on
    /// evidence the watch currently trusts.
    public func alertHere(at now: Date) -> Bool? {
        health(at: now) == .ok ? alerting(in: region) : nil
    }

    public func since(_ region: String) -> Date? { seenSince[region] }

    /// The places kept an eye on, in the order they were given. Blind about here
    /// means blind about there too.
    public func elsewhere(at now: Date) -> [Elsewhere] {
        let trusted = health(at: now) == .ok
        return others.map {
            Elsewhere(region: $0, alert: trusted ? alerting(in: $0) : nil, since: seenSince[$0])
        }
    }

    public var alertingCount: Int { lastOK?.alerting.count ?? 0 }

    public func readingAge(at now: Date) -> TimeInterval? {
        lastOK.map { now.timeIntervalSince($0.fetchedAt) }
    }
}

/// How long to wait after a failure.
///
/// The feed rate-limits hard: a burst of retries earns a 429, which would keep
/// the app blind for longer than simply waiting. So retries slow down, but never
/// past the point of checking a few times an hour.
public func backoff(failures: Int, base: TimeInterval = 60, ceiling: TimeInterval = 300) -> TimeInterval {
    guard failures > 0 else { return base }
    return min(ceiling, base * pow(2, Double(min(failures - 1, 3))))
}
