import Foundation

// Port of bin/varta-locate's decision: which region this Mac is in, and how sure.
//
// On the Mac, Core Location (with permission) is asked first. This is the
// fallback: two public IP services, believed only when both give the same
// answer. A confident wrong region would watch the wrong place while looking like
// it worked, so an uncertain result says so and leaves the choice to the person.

public enum Locate {
    public enum Confidence: String, Sendable, Equatable {
        /// Core Location placed the Mac in a region.
        case located
        case agreed, single, masked, disagreed, unknown
    }

    public struct Answer: Sendable, Equatable {
        public var region: String?
        public var confidence: Confidence
        public var why: String?

        public init(region: String?, confidence: Confidence, why: String? = nil) {
            self.region = region
            self.confidence = confidence
            self.why = why
        }
    }

    public static let sources: [(name: String, url: URL)] = [
        ("ipwho.is", URL(string: "https://ipwho.is/")!),
        ("ip-api.com", URL(string: "http://ip-api.com/json/?fields=status,country,regionName,region,proxy,hosting")!),
    ]

    /// A region name the feed would recognise, and whether the address looks
    /// like it is being routed through something.
    public static func read(_ payload: [String: Any]) -> (region: String?, masked: Bool) {
        let country = payload["country"] as? String
        guard country == "Ukraine" || country == "UA" else { return (nil, false) }
        let masked = (payload["proxy"] as? Bool ?? false) || (payload["hosting"] as? Bool ?? false)
        let code = (payload["region_code"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? payload["region"] as? String
        let name = (payload["regionName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? payload["region"] as? String
        return (Regions.fromISO(code) ?? Regions.fromName(name), masked)
    }

    /// `seen` holds every service that answered (nil: answered, but not with a
    /// Ukrainian region).
    public static func decide(seen: [String: String?], masked: Bool) -> Answer {
        let found = seen.values.compactMap { $0 }
        let answers = Set(found)
        if masked {
            return Answer(region: nil, confidence: .masked,
                          why: "the address looks like a VPN or a hosting provider, so where it appears to be is not where you are")
        }
        if answers.count == 1, seen.count >= 2, found.count >= 2 {
            return Answer(region: answers.first, confidence: .agreed)
        }
        if answers.count == 1 {
            return Answer(region: answers.first, confidence: .single,
                          why: "only one service answered, so this is worth checking")
        }
        if answers.count > 1 {
            return Answer(region: nil, confidence: .disagreed,
                          why: "the services place this Mac in different regions")
        }
        return Answer(region: nil, confidence: .unknown, why: "no service could place this Mac in Ukraine")
    }

    /// Core Location's reverse geocode, asked in English so the names match the
    /// stems Regions knows. Kyiv city is its own administrative area.
    public static func fromPlacemark(countryCode: String?, administrativeArea: String?, locality: String?) -> String? {
        guard countryCode?.uppercased() == "UA" else { return nil }
        if let area = administrativeArea, let region = Regions.fromName(area) { return region }
        return Regions.fromName(locality)
    }
}
