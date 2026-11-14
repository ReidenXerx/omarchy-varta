import Foundation

// What shell/Service.qml decides on top of the watch: what to show, and when to
// speak up. Kept pure (every call takes `now`) so the rules are tested without
// timers or a network.

/// What the menu bar shows. Four answers, not two.
public enum Status: Equatable, Sendable {
    /// No region chosen yet.
    case unset
    /// Just started, just woke, or the region just changed: not calm, not lost,
    /// just not heard from yet. Every launch would otherwise flash "not
    /// watching" for the second before the first reading lands.
    case starting
    case calm
    case alert(since: Date?)
    /// Anything else, and it must look as loud as an alert.
    case notWatching(reason: String)

    public var isAlert: Bool { if case .alert = self { true } else { false } }
    public var isLost: Bool { if case .notWatching = self { true } else { false } }
}

/// Something worth telling a person about, once.
public enum Event: Equatable, Sendable {
    /// Your region went under alert. Breaks through.
    case alertHere(region: String)
    /// Your region's alert ended.
    case clearHere(region: String)
    /// Places you keep an eye on went under alert. Said once, quietly.
    case alertElsewhere(regions: [String])
    /// The watch stopped being able to see. Said once per episode.
    case lost(reason: String)
    /// And it can see again.
    case regained
}

public struct Monitor: Sendable {
    /// How long a fresh start, a wake or a region change gets before failing to
    /// read counts as lost. The network is usually a moment behind a waking Mac.
    public static let grace: TimeInterval = 90

    public private(set) var watch: Watch
    public private(set) var lastError: String?
    private var everRead = false
    private var patientUntil: Date
    /// region|since of the alert already announced, so a blind spell in the
    /// middle of one alert does not announce it twice.
    private var announced: String?
    private var announcedElsewhere: Set<String> = []
    private var wasLost = false

    public init(region: String, others: [String] = [], now: Date) {
        watch = Watch(region: region, others: others)
        patientUntil = now.addingTimeInterval(Self.grace)
    }

    public var region: String { watch.region }

    // MARK: feeding it

    public mutating func observe(_ reading: Reading, now: Date) -> [Event] {
        watch.observe(reading)
        lastError = nil
        if watch.health(at: now) == .ok { everRead = true }
        return events(at: now)
    }

    public mutating func failed(_ error: String, now: Date) -> [Event] {
        watch.failed(at: now)
        lastError = error
        return events(at: now)
    }

    /// The Mac woke up. Its network is usually a moment behind it, and that is
    /// not the feed being lost: shouting about it every morning is how a warning
    /// becomes something you look past.
    public mutating func resumed(now: Date) {
        everRead = false
        patientUntil = now.addingTimeInterval(Self.grace)
    }

    /// Time passing changes things on its own: a reading going stale is news
    /// even when no new reading arrives. Call this on a timer.
    public mutating func tick(now: Date) -> [Event] { events(at: now) }

    // MARK: reading it

    public func status(at now: Date) -> Status {
        if watch.region.isEmpty { return .unset }
        let health = watch.health(at: now)
        if health == .ok {
            return watch.alerting(in: watch.region) ? .alert(since: watch.since(watch.region)) : .calm
        }
        let patient = now < patientUntil
        if !everRead && patient { return .starting }
        return .notWatching(reason: reason(at: now, health: health))
    }

    /// Why it cannot vouch for anything, in words for a person.
    public func reason(at now: Date, health: Health) -> String {
        if let lastError { return plainly(lastError) }
        if let age = watch.readingAge(at: now), age >= staleAfter {
            return "the last reading is \(Int(age / 60)) min old"
        }
        if let sourceAge = watch.sourceAge(at: now), sourceAge >= staleAfter {
            // Answers, but stopped changing: the failure this app exists for.
            return "the feed has stopped updating"
        }
        return "cannot read the feed"
    }

    public func elsewhere(at now: Date) -> [Elsewhere] { watch.elsewhere(at: now) }

    // MARK: deciding what to say

    private mutating func events(at now: Date) -> [Event] {
        var out: [Event] = []
        let status = status(at: now)

        if status.isLost && !wasLost, case .notWatching(let why) = status {
            out.append(.lost(reason: why))
        } else if wasLost && (status == .calm || status.isAlert) {
            out.append(.regained)
        }
        wasLost = status.isLost

        switch status {
        case .alert(let since):
            let key = "\(watch.region)|\(since.map { "\($0.timeIntervalSince1970)" } ?? "")"
            if announced != key {
                out.append(.alertHere(region: watch.region))
                announced = key
            }
        case .calm:
            if announced != nil {
                out.append(.clearHere(region: watch.region))
                announced = nil
            }
        default:
            break // not knowing ends nothing and starts nothing
        }

        let raisedElsewhere = Set(watch.elsewhere(at: now).filter { $0.alert == true }.map(\.region))
        if watch.health(at: now) == .ok {
            let fresh = watch.others.filter { raisedElsewhere.contains($0) && !announcedElsewhere.contains($0) }
            if !fresh.isEmpty { out.append(.alertElsewhere(regions: fresh)) }
            announcedElsewhere = raisedElsewhere
        }
        return out
    }
}
