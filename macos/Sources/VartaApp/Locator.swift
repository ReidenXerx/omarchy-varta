import CoreLocation
import Foundation
import VartaCore

/// Finds which region this Mac is in. Core Location first (with permission):
/// it knows where the Mac is, not where its internet connection comes out. If
/// that is refused or fails, the two IP services from bin/varta-locate, believed
/// only when they agree.
@MainActor
final class Locator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiting: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func locate() async -> Locate.Answer {
        if let location = await currentLocation(),
           let placemark = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "en_US")).first {
            if let region = Locate.fromPlacemark(countryCode: placemark.isoCountryCode,
                                                 administrativeArea: placemark.administrativeArea,
                                                 locality: placemark.locality) {
                return Locate.Answer(region: region, confidence: .located)
            }
            if placemark.isoCountryCode?.uppercased() != "UA" {
                // Location is the better witness; an IP lookup claiming Ukraine
                // while the Mac is elsewhere is a VPN, not a place.
                return Locate.Answer(region: nil, confidence: .unknown, why: "this Mac does not appear to be in Ukraine")
            }
        }
        return await byAddress()
    }

    // MARK: Core Location

    private func currentLocation() async -> CLLocation? {
        guard CLLocationManager.locationServicesEnabled() else { return nil }
        switch manager.authorizationStatus {
        case .denied, .restricted: return nil
        default: break
        }
        return await withCheckedContinuation { continuation in
            waiting?.resume(returning: nil)
            waiting = continuation
            if manager.authorizationStatus == .notDetermined {
                manager.requestWhenInUseAuthorization() // the answer arrives in the delegate
            } else {
                manager.requestLocation()
            }
            // Never wait on location forever: watching the wrong place is bad,
            // watching nothing while a permission sheet sits unanswered is worse.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                self?.finish(nil)
            }
        }
    }

    private func finish(_ location: CLLocation?) {
        waiting?.resume(returning: location)
        waiting = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            guard waiting != nil else { return }
            switch status {
            case .authorizedAlways, .authorized: self.manager.requestLocation()
            case .denied, .restricted: finish(nil)
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        MainActor.assumeIsolated { finish(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finish(nil) }
    }

    // MARK: IP fallback

    private func byAddress() async -> Locate.Answer {
        var seen: [String: String?] = [:]
        var masked = false
        for source in Locate.sources {
            var request = URLRequest(url: source.url, timeoutInterval: 10)
            request.setValue(Feed.userAgent, forHTTPHeaderField: "User-Agent")
            guard let (data, _) = try? await URLSession.shared.data(for: request), data.count <= 64 * 1024,
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let (region, isMasked) = Locate.read(payload)
            seen[source.name] = region
            masked = masked || isMasked
        }
        return Locate.decide(seen: seen, masked: masked)
    }
}
