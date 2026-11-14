import Foundation

// The ubilling feed: what bin/varta-watch's fetch() does once the bytes are in.
//
// Polite by design. The feed is a free service run by somebody else: it
// refreshes its cache about once a minute and rate-limits by IP, and a burst of
// requests earns a 429 that keeps the watch blind for longer than waiting would.
// So: one request a minute, back off when refused, and say who is asking.

public enum Feed {
    public static let url = URL(string: "https://ubilling.net.ua/aerialalerts/")!
    public static let userAgent = "omarchy-varta-mac/0.1 (+https://github.com/ReidenXerx/omarchy-varta)"
    public static let timeout: TimeInterval = 15
    /// The feed answers in about 4 KB. Anything wildly larger is not the feed.
    public static let ceiling = 256 * 1024
    /// Polling faster than this gets the feed to refuse us.
    public static let minimumInterval: TimeInterval = 30
    public static let interval: TimeInterval = 60

    public struct Answer: Sendable, Equatable {
        public var alerting: Set<String>
        public var sourceTime: Date?
        /// The regions the feed actually has, so nothing has to keep its own copy.
        public var names: [String]
    }

    public struct Problem: Error, CustomStringConvertible, Sendable {
        public var description: String
        public init(_ description: String) { self.description = description }
    }

    /// The cache stamp is local Kyiv time, without an offset. The Linux watcher
    /// reads it in the machine's zone, which is only right inside Ukraine; a Mac
    /// abroad would see every reading as hours stale, so the zone is explicit.
    static let stampFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Kyiv")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    public static func parse(_ data: Data) throws -> Answer {
        if data.count > ceiling { throw Problem("response too large to be the feed") }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw Problem("JSON: \(error.localizedDescription)")
        }
        guard let payload = object as? [String: Any],
              let states = payload["states"] as? [String: Any], !states.isEmpty else {
            throw Problem("feed carried no regions")
        }
        // Names are flattened once, here, so everything downstream works on the
        // same safe strings.
        var names: [String] = []
        var alerting: Set<String> = []
        for (raw, value) in states {
            let name = plain(raw)
            guard !name.isEmpty else { continue }
            names.append(name)
            // `alertnow` must be a real JSON true, not 1 or "true".
            if let entry = value as? [String: Any],
               let now = entry["alertnow"] as? NSNumber,
               CFGetTypeID(now) == CFBooleanGetTypeID(), now.boolValue {
                alerting.insert(name)
            }
        }
        guard !names.isEmpty else { throw Problem("feed carried no usable region names") }
        let sourceTime = (payload["cachedat"] as? String).flatMap { stampFormat.date(from: $0) }
        return Answer(alerting: alerting, sourceTime: sourceTime, names: names.sorted())
    }
}
