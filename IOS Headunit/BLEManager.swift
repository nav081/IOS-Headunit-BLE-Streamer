import Foundation
import CoreBluetooth
import CoreLocation
import Combine

final class BLEManager: NSObject, ObservableObject {
    static let serviceUUID = CBUUID(string: "0000feed-0000-1000-8000-00805f9b34fb")
    static let characteristicUUID = CBUUID(string: "0000beef-0000-1000-8000-00805f9b34fb")

    @Published var isAdvertising = false
    @Published var connectedCentralCount = 0
    @Published var logs: [String] = []

    private var peripheralManager: CBPeripheralManager?
    private var txCharacteristic: CBMutableCharacteristic?

    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
    }

    func startAdvertising() {
        guard let peripheralManager else { return }
        guard peripheralManager.state == .poweredOn else {
            appendLog("Bluetooth not ready")
            return
        }

        if txCharacteristic == nil {
            let characteristic = CBMutableCharacteristic(
                type: Self.characteristicUUID,
                properties: [.notify, .read],
                value: nil,
                permissions: [.readable]
            )
            txCharacteristic = characteristic
            let service = CBMutableService(type: Self.serviceUUID, primary: true)
            service.characteristics = [characteristic]
            peripheralManager.add(service)
        }

        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID]])
        isAdvertising = true
        appendLog("Advertising started")
    }

    func stopAdvertising() {
        peripheralManager?.stopAdvertising()
        isAdvertising = false
        appendLog("Advertising stopped")
    }

    func stream(location: CLLocation, format: PayloadFormat) {
        guard let txCharacteristic else { return }
        let payload: Data = format == .json ? PayloadFormatter.jsonData(from: location) : PayloadFormatter.nmeaData(from: location)
        let success = peripheralManager?.updateValue(payload, for: txCharacteristic, onSubscribedCentrals: nil) ?? false
        if !success { appendLog("Backpressure: updateValue returned false") }
    }

    private func appendLog(_ message: String) {
        logs.append("[\(Date())] \(message)")
        if logs.count > 300 { logs.removeFirst() }
    }
}

extension BLEManager: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        appendLog("BLE state: \(peripheral.state.rawValue)")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        connectedCentralCount += 1
        appendLog("Central subscribed: \(central.identifier)")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        connectedCentralCount = max(0, connectedCentralCount - 1)
        appendLog("Central unsubscribed: \(central.identifier)")
    }
}

enum PayloadFormatter {
    static func jsonData(from location: CLLocation) -> Data {
        let payload = CoordinatePayload(
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            alt: location.altitude,
            speed: max(location.speed, 0),
            timestamp: location.timestamp.timeIntervalSince1970
        )
        return (try? JSONEncoder().encode(payload)) ?? Data()
    }

    static func nmeaData(from location: CLLocation) -> Data {
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmmss"
        formatter.timeZone = .init(secondsFromGMT: 0)
        let time = formatter.string(from: location.timestamp)
        let lat = nmeaCoordinate(location.coordinate.latitude, isLatitude: true)
        let lon = nmeaCoordinate(location.coordinate.longitude, isLatitude: false)
        let speedKnots = max(location.speed, 0) * 1.94384
        let sentence = "$GPRMC,\(time).00,A,\(lat.value),\(lat.dir),\(lon.value),\(lon.dir),\(String(format: "%.1f", speedKnots)),0.0,010100,,,A*00"
        return Data(sentence.utf8)
    }

    private static func nmeaCoordinate(_ coord: Double, isLatitude: Bool) -> (value: String, dir: String) {
        let absCoord = abs(coord)
        let degrees = Int(absCoord)
        let minutes = (absCoord - Double(degrees)) * 60
        if isLatitude {
            return (String(format: "%02d%06.3f", degrees, minutes), coord >= 0 ? "N" : "S")
        }
        return (String(format: "%03d%06.3f", degrees, minutes), coord >= 0 ? "E" : "W")
    }
}
