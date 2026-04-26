import Foundation
import CoreLocation

enum PayloadFormat: String, CaseIterable, Codable {
    case json
    case nmea
}

struct ConnectedDevice: Identifiable {
    let id: UUID
    var deviceId: String
    var connectedAt: Date
    var disconnectedAt: Date?
    var dataPacketsSent: Int = 0
    var lastUpdateTime: Date?
    var totalBytesSent: Int = 0
    
    var isConnected: Bool { disconnectedAt == nil }
    var connectionDuration: TimeInterval { (disconnectedAt ?? Date()).timeIntervalSince(connectedAt) }
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
