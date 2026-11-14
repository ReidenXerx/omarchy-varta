import Foundation

// Port of app/history.py: what has already happened, so the watch is about
// more than this minute.
//
// What is stored is transitions, not alerts: one line each time a region goes
// under alert or comes out of one. A watcher can be killed at any moment, so an
// append-only line is the unit that survives. Spells are rebuilt by pairing
// transitions on the way out, so a spell still running is simply one not closed.
//
// One difference from Linux: the Mac records every region the feed reports, not
// only the watched ones, so changing your region does not start you from zero.
// The summary still only counts the regions you watch.

public enum History {
    /// About a month of all 26 regions on a bad month. Past this the oldest go.
    public static let maxRecords = 60_000

    /// A spell longer than this is not an alert: it is a watcher that died while
    /// one was running and came back after it ended.
    public static let implausible: TimeInterval = 18 * 3600

    /// A change first seen after this long without a trusted reading happened
    /// at some unknown moment inside the gap (Varta quit, the Mac asleep, the
    /// feed down). Its time is recorded but marked uncertain, and spells it
    /// opens or closes are left out of every duration and the by-hour chart:
    /// otherwise twelve hours with the lid shut become a twelve-hour alert.
    public static let gapLimit: TimeInterval = 10 * 60
}

/// A region crossing into or out of an alert, at a moment.
public struct Transition: Equatable, Sendable {
    public var region: String
    public var at: Date
    public var alert: Bool
    /// Seen only after a gap in watching; see History.gapLimit.
    public var uncertain: Bool

    public init(region: String, at: Date, alert: Bool, uncertain: Bool = false) {
        self.region = region
        self.at = at
        self.alert = alert
        self.uncertain = uncertain
    }

    /// The same shape as the Linux file, so the two can be merged by hand.
    public var line: String {
        var object: [String: Any] = ["region": region, "at": at.formatted(.iso8601), "alert": alert]
        // Only written when true, so lines stay the Linux shape; Linux ignores it.
        if uncertain { object["uncertain"] = true }
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    /// A line, or nil if it is not one. Never throws: the file is read on a path
    /// that must not fail because somebody hand-edited it.
    public static func parse(_ line: String) -> Transition? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stamp = object["at"] as? String, let at = date(stamp),
              let region = object["region"] as? String, !region.isEmpty else { return nil }
        let alert = (object["alert"] as? Bool) ?? false
        let uncertain = (object["uncertain"] as? Bool) ?? false
        return Transition(region: region, at: at, alert: alert, uncertain: uncertain)
    }

    /// ISO 8601 as Python writes it (with or without fraction or zone). A time
    /// without a zone is read as UTC rather than refused.
    static func date(_ text: String) -> Date? {
        for options: ISO8601DateFormatter.Options in [
            [.withInternetDateTime], [.withInternetDateTime, .withFractionalSeconds],
        ] {
            let f = ISO8601DateFormatter()
            f.formatOptions = options
            if let d = f.date(from: text) { return d }
        }
        let naive = DateFormatter()
        naive.locale = Locale(identifier: "en_US_POSIX")
        naive.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"] {
            naive.dateFormat = format
            if let d = naive.date(from: text) { return d }
        }
        return nil
    }
}

/// Turns a stream of readings into the transitions worth writing down.
///
/// It holds only what it last saw per region, so a watcher that restarts simply
/// learns the current state on its first reading and writes a transition only
/// if something genuinely changed.
public struct Ledger: Sendable {
    public private(set) var state: [String: Bool]

    public init(known: [String: Bool] = [:]) { state = known }

    public mutating func observe(_ region: String, alerting: Bool, at when: Date, uncertain: Bool = false) -> Transition? {
        guard !region.isEmpty else { return nil }
        let was = state[region]
        state[region] = alerting
        // The first sighting of a region is not a transition: treating it as one
        // would invent an alert every time the watcher restarts.
        guard let was, was != alerting else { return nil }
        return Transition(region: region, at: when, alert: alerting, uncertain: uncertain)
    }
}

public struct Spell: Equatable, Sendable, Codable {
    public var region: String
    public var start: Date
    /// nil while it is still running.
    public var end: Date?
    /// Its start or end was only seen after a gap in watching: it happened, but
    /// how long it lasted and when it began are not known.
    public var uncertain = false

    public func length(at now: Date) -> TimeInterval { (end ?? now).timeIntervalSince(start) }
}

/// Paired into periods, oldest first.
public func spells(_ transitions: [Transition]) -> [Spell] {
    var open: [String: Transition] = [:]
    var out: [Spell] = []
    for t in transitions.sorted(by: { $0.at < $1.at }) {
        if t.alert {
            if open[t.region] == nil { open[t.region] = t }
        } else if let start = open.removeValue(forKey: t.region) {
            out.append(Spell(region: t.region, start: start.at, end: t.at, uncertain: start.uncertain || t.uncertain))
        }
    }
    for (region, start) in open {
        out.append(Spell(region: region, start: start.at, end: nil, uncertain: start.uncertain))
    }
    return out.sorted { $0.start < $1.start }
}

public struct Summary: Equatable, Sendable, Codable {
    public struct RegionTotal: Equatable, Sendable, Codable {
        public var region: String
        public var count: Int
        public var seconds: Int
    }

    public var days: Int
    public var regions: [RegionTotal]
    /// Alerts by the local hour they began: "when do they start" is the
    /// question people ask, and they ask it in their own clock.
    public var byHour: [Int]
    public var total: Int
    public var longest: Spell?
    public var ongoing: [Spell]
    /// How long it has been quiet everywhere watched. nil while anything runs.
    public var quietSeconds: Int?
    /// Alerts that happened but were only seen across a gap in watching, so
    /// when and how long are unknown. Optional so older snapshots still decode.
    public var untimed: Int?

    public static func empty(days: Int) -> Summary {
        Summary(days: days, regions: [], byHour: Array(repeating: 0, count: 24), total: 0,
                longest: nil, ongoing: [], quietSeconds: nil, untimed: 0)
    }
}

/// What the dropdown shows: how many, how long, and when they tend to come.
public func summarise(_ transitions: [Transition], now: Date, days: Int = 7,
                      only regions: Set<String>? = nil, calendar: Calendar = .current) -> Summary {
    let since = now.addingTimeInterval(-Double(days) * 86_400)
    let every = spells(regions.map { r in transitions.filter { r.contains($0.region) } } ?? transitions)
    let recent = every.filter { ($0.end ?? now) >= since }

    var totals: [String: Summary.RegionTotal] = [:]
    var byHour = Array(repeating: 0, count: 24)
    var longest: Spell?
    for s in recent {
        let length = s.length(at: now)
        if length > History.implausible || s.uncertain { continue }
        var r = totals[s.region] ?? .init(region: s.region, count: 0, seconds: 0)
        r.count += 1
        r.seconds += Int(length)
        totals[s.region] = r
        byHour[calendar.component(.hour, from: s.start)] += 1
        if longest == nil || length > longest!.length(at: now) { longest = s }
    }

    let ongoing = every.filter { $0.end == nil }
    let lastSpell = every.filter { $0.end != nil }.max { $0.end! < $1.end! }
    // "Quiet for" from an end only seen after a gap would understate it by the
    // gap; better to say nothing.
    let lastEnd = lastSpell?.uncertain == true ? nil : lastSpell?.end
    return Summary(
        days: days,
        regions: totals.values.sorted { $0.seconds > $1.seconds },
        byHour: byHour,
        total: totals.values.reduce(0) { $0 + $1.count },
        longest: longest,
        ongoing: ongoing,
        quietSeconds: (lastEnd != nil && ongoing.isEmpty) ? Int(now.timeIntervalSince(lastEnd!)) : nil,
        untimed: recent.filter { $0.uncertain && $0.end != nil }.count
    )
}

/// The newest `cap` lines. Oldest history is the first thing nobody misses.
public func trim(_ lines: [String], cap: Int = History.maxRecords) -> [String] {
    lines.count > cap ? Array(lines.suffix(cap)) : lines
}
