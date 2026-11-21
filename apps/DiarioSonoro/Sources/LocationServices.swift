import Foundation
import CoreLocation
import WeatherKit
import SonoroCore

/// One "while in use" fix at recording time, never continuous tracking.
final class LocationService: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private var fixWaiters: [CheckedContinuation<GeoPoint?, Never>] = []
    private var authWaiters: [CheckedContinuation<LocationAccess, Never>] = []

    /// Create on the main thread (CLLocationManager needs a run loop).
    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    var access: LocationAccess {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return .allowed
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    func requestAccess() async -> LocationAccess {
        let current = access
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { (c: CheckedContinuation<LocationAccess, Never>) in
            DispatchQueue.main.async {
                self.authWaiters.append(c)
                self.manager.requestWhenInUseAuthorization()
            }
        }
    }

    func currentLocation() async -> GeoPoint? {
        guard access == .allowed else { return nil }
        return await withCheckedContinuation { (c: CheckedContinuation<GeoPoint?, Never>) in
            DispatchQueue.main.async {
                self.fixWaiters.append(c)
                if self.fixWaiters.count == 1 { self.manager.requestLocation() }
                // Never wait more than 10 s.
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { self.resolveFix(nil) }
            }
        }
    }

    func placeInfo(for point: GeoPoint) async -> PlaceInfo? {
        let geocoder = CLGeocoder()
        let loc = CLLocation(latitude: point.lat, longitude: point.lon)
        guard let mark = try? await geocoder.reverseGeocodeLocation(loc, preferredLocale: Locale(identifier: "it_IT")).first else {
            return nil
        }
        let name = mark.areasOfInterest?.first ?? mark.thoroughfare ?? mark.name
        return PlaceInfo(name: name, locality: mark.locality ?? mark.subAdministrativeArea)
    }

    private func resolveFix(_ point: GeoPoint?) {
        let waiters = fixWaiters
        fixWaiters = []
        waiters.forEach { $0.resume(returning: point) }
    }

    // MARK: CLLocationManagerDelegate (called on the main thread)

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        let point = GeoPoint(lat: l.coordinate.latitude, lon: l.coordinate.longitude, accuracy: l.horizontalAccuracy)
        DispatchQueue.main.async { self.resolveFix(point) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { self.resolveFix(nil) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = access
        guard status != .notDetermined else { return }
        DispatchQueue.main.async {
            let waiters = self.authWaiters
            self.authWaiters = []
            waiters.forEach { $0.resume(returning: status) }
        }
    }
}

/// WeatherKit: needs the WeatherKit capability of a paid developer account.
/// With a free Apple ID the request fails and the clip is simply saved
/// without weather.
final class WeatherKitProvider: WeatherProviding {
    func weather(at point: GeoPoint, date: Date) async -> WeatherInfo? {
        do {
            let current = try await WeatherService.shared.weather(for: CLLocation(latitude: point.lat, longitude: point.lon), including: .current)
            return WeatherInfo(symbol: current.symbolName, condition: current.condition.description,
                               temperatureC: current.temperature.converted(to: .celsius).value)
        } catch {
            return nil
        }
    }
}
