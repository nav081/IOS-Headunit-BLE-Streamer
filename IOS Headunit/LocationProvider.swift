import Foundation
import CoreLocation
import Combine

final class LocationProvider: NSObject, ObservableObject {
    private let manager = CLLocationManager()
    @Published var latestLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var logs: [String] = []
    @Published var useSimulatedRoute = false

    private let simulator = SimulatedRouteGenerator()
    private var timer: Timer?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
    }
    
    deinit {
        timer?.invalidate()
        timer = nil
        manager.stopUpdatingLocation()
    }

    func requestPermissions() {
        manager.requestWhenInUseAuthorization()
        manager.requestAlwaysAuthorization()
    }

    func start() {
        if useSimulatedRoute {
            startSimulation()
        } else {
            stopSimulation()
            manager.startUpdatingLocation()
            appendLog("Location updates started")
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        stopSimulation()
        appendLog("Location updates stopped")
    }

    private func startSimulation() {
        timer?.invalidate()
        var points = simulator.generateLoopRoute(startLat: 37.7749, startLon: -122.4194, steps: 200)
        appendLog("Simulated route started with \(points.count) points")
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if points.isEmpty {
                points = self.simulator.generateLoopRoute(startLat: 37.7749, startLon: -122.4194, steps: 200)
                self.appendLog("Simulated route loop restarted with \(points.count) points")
            }
            let point = points.removeFirst()
            self.latestLocation = CLLocation(
                coordinate: .init(latitude: point.lat, longitude: point.lon),
                altitude: point.alt,
                horizontalAccuracy: 3.0,
                verticalAccuracy: 5.0,
                timestamp: Date()
            )
            let latStr = String(format: "%.4f", point.lat)
            let lonStr = String(format: "%.4f", point.lon)
            self.appendLog("📍 Simulated location: \(latStr), \(lonStr)")
        }
    }

    private func stopSimulation() {
        timer?.invalidate()
        timer = nil
    }

    private func appendLog(_ message: String) {
        logs.append("[\(Date())] \(message)")
        if logs.count > 300 { logs.removeFirst() }
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        appendLog("Authorization changed: \(authorizationStatus.rawValue)")
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.isValidForStreaming() else {
            if let loc = locations.last {
                appendLog("⚠️ Invalid location: lat=\(loc.coordinate.latitude), lon=\(loc.coordinate.longitude)")
            }
            return
        }
        latestLocation = loc
        appendLog("📍 Location received: \(String(format: "%.4f", loc.coordinate.latitude)), \(String(format: "%.4f", loc.coordinate.longitude))")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        appendLog("Location error: \(error.localizedDescription)")
    }
}
