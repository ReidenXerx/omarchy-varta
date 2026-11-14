import Foundation
import VartaCore

/// One request to the feed. Mirrors fetch() in bin/varta-watch: one request,
/// everything the caller could want from it, and failures described in words
/// `plainly()` can turn into a sentence for a person.
enum Poller {
    /// VARTA_FEED points the app at a saved response (a file:// URL) for
    /// development, so working on the UI never spends the feed's patience.
    static let feedURL: URL = {
        if let override = ProcessInfo.processInfo.environment["VARTA_FEED"], let url = URL(string: override) {
            return url
        }
        return Feed.url
    }()

    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = Feed.timeout
        config.timeoutIntervalForResource = Feed.timeout
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    static func fetch() async throws -> Feed.Answer {
        var request = URLRequest(url: feedURL)
        request.setValue(Feed.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw Feed.Problem(describe(error))
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            if http.statusCode == 429 { throw Feed.Problem("feed refused us for asking too often (429)") }
            throw Feed.Problem("HTTP \(http.statusCode)")
        }
        return try Feed.parse(data)
    }

    /// URLError codes in the vocabulary plainly() already understands.
    static func describe(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return "not connected to the internet"
        case .cannotFindHost, .dnsLookupFailed:
            return "temporary failure in name resolution"
        case .timedOut:
            return "timed out"
        case .cannotConnectToHost:
            return "connection refused"
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
            return "ssl: \(error.localizedDescription)"
        default:
            return error.localizedDescription
        }
    }
}
