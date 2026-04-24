import Foundation

final class SimulatedRouteGenerator {
    func generateLoopRoute(startLat: Double, startLon: Double, steps: Int) -> [CoordinatePayload] {
        guard steps > 0 else { return [] }
        return (0..<steps).map { idx in
            let angle = (Double(idx) / Double(steps)) * 2 * Double.pi
            let lat = startLat + 0.003 * cos(angle)
            let lon = startLon + 0.003 * sin(angle)
            let speed = 10 + 2 * sin(angle)
            return CoordinatePayload(
                lat: lat,
                lon: lon,
                alt: 25.0,
                speed: speed,
                timestamp: Date().timeIntervalSince1970 + Double(idx)
            )
        }
    }
}
