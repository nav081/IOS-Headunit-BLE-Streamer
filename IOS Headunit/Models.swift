import Foundation
import CoreLocation

enum PayloadFormat: String, CaseIterable, Codable {
    case json
    case nmea
}

struct CoordinatePayload: Codable, Equatable {
    let lat: Double
    let lon: Double
    let alt: Double
    let speed: Double
    let timestamp: TimeInterval
}

extension CLLocation {
    func isValidForStreaming() -> Bool {
        coordinate.latitude >= -90 &&
        coordinate.latitude <= 90 &&
        coordinate.longitude >= -180 &&
        coordinate.longitude <= 180 &&
        horizontalAccuracy >= 0
    }
}
