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
    @Published var connectedDevices: [ConnectedDevice] = []

    private var peripheralManager: CBPeripheralManager?
    private var txCharacteristic: CBMutableCharacteristic?
    private var isCharacteristicReady = false
    private var advertisingRequested = false
    private var advertisingRetryCount = 0
    private let maxAdvertisingRetryCount = 6
    private var locationQueue: [CLLocation] = []
    private var isProcessingQueue = false
    private var deviceMap: [UUID: ConnectedDevice] = [:] // Track devices by UUID

    override init() {
        super.init()
        appendLog("🧩 BLEManager initialized, creating peripheral manager")
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
    }

    func startAdvertising() {
        advertisingRequested = true
        advertisingRetryCount = 0
        guard let peripheralManager else {
            appendLog("❌ ERROR: peripheralManager is nil")
            return
        }
        appendLog("▶️ startAdvertising called - current BLE state: \(stateDescription(peripheralManager.state))")
        guard peripheralManager.state == .poweredOn else {
            if peripheralManager.state == .unknown {
                appendLog("⏳ Bluetooth state unknown, waiting for poweredOn")
                scheduleAdvertisingRetry()
            } else {
                appendLog("⚠️ Bluetooth not ready (state: \(stateDescription(peripheralManager.state))) - waiting for poweredOn")
            }
            return
        }
        beginAdvertising()
    }

    private func beginAdvertising() {
        guard let peripheralManager else { return }
        guard !isAdvertising else {
            appendLog("ℹ️ Already advertising")
            return
        }

        appendLog("🚀 Starting advertising...")

        if txCharacteristic == nil {
            appendLog("📝 Creating service and characteristic...")
            let characteristic = CBMutableCharacteristic(
                type: Self.characteristicUUID,
                properties: [.notify, .read],
                value: nil,
                permissions: [.readable]
            )
            txCharacteristic = characteristic
            let service = CBMutableService(type: Self.serviceUUID, primary: true)
            service.characteristics = [characteristic]
            appendLog("   Service UUID: \(Self.serviceUUID.uuidString)")
            appendLog("   Characteristic UUID: \(Self.characteristicUUID.uuidString)")
            peripheralManager.add(service)
            appendLog("   ✓ Service added (waiting for didAdd callback)")
        } else {
            appendLog("   ℹ️ Service/characteristic already created")
            peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID]])
            isAdvertising = true
            appendLog("   ✓ Advertising started")
        }
    }

    private func scheduleAdvertisingRetry(after delay: TimeInterval = 1.0) {
        guard advertisingRequested else { return }
        guard advertisingRetryCount < maxAdvertisingRetryCount else {
            appendLog("❌ BLE advertising retry limit reached")
            return
        }
        advertisingRetryCount += 1
        let retryNumber = advertisingRetryCount
        appendLog("⏱ Scheduling advertising retry #\(retryNumber) in \(Int(delay))s")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.advertisingRequested else { return }
            guard let peripheralManager = self.peripheralManager else {
                self.appendLog("❌ No peripheral manager available for retry")
                return
            }
            self.appendLog("🔁 Retry #\(retryNumber): checking BLE state again (\(self.stateDescription(peripheralManager.state)))")
            if peripheralManager.state == .poweredOn {
                self.beginAdvertising()
            } else if peripheralManager.state == .unknown {
                self.scheduleAdvertisingRetry(after: min(2.0, delay * 2))
            } else {
                self.appendLog("⚠️ BLE still not ready after retry (state: \(self.stateDescription(peripheralManager.state)))")
            }
        }
    }

    func stopAdvertising() {
        peripheralManager?.stopAdvertising()
        advertisingRequested = false
        isAdvertising = false
        isCharacteristicReady = false
        appendLog("Advertising stopped")
    }

    func stream(location: CLLocation, format: PayloadFormat) {
        guard isCharacteristicReady, let txCharacteristic else {
            appendLog("⚠️ Queueing location: characteristic not ready (isReady=\(isCharacteristicReady), hasTx=\(txCharacteristic != nil))")
            locationQueue.append(location)
            return
        }
        appendLog("✓ Characteristic ready, processing location")
        processLocationWithFormat(location, format: format)
    }
    
    private func processLocationWithFormat(_ location: CLLocation, format: PayloadFormat) {
        guard let txCharacteristic else { return }
        let payload: Data = format == .json ? 
            PayloadFormatter.jsonData(from: location) : 
            PayloadFormatter.nmeaData(from: location)
        
        guard !payload.isEmpty else {
            appendLog("ERROR: Failed to format location data")
            return
        }
        
        let success = peripheralManager?.updateValue(payload, for: txCharacteristic, onSubscribedCentrals: nil) ?? false
        if !success {
            appendLog("Backpressure: queue full, buffering location")
            locationQueue.append(location)
        } else {
            appendLog("📊 DATA: \(payload.count) bytes sent to \(connectedCentralCount) device(s)")
            // Update device stats
            for (uuid, _) in deviceMap {
                if var device = deviceMap[uuid], device.isConnected {
                    device.dataPacketsSent += 1
                    device.lastUpdateTime = Date()
                    device.totalBytesSent += payload.count
                    deviceMap[uuid] = device
                }
            }
            connectedDevices = Array(deviceMap.values).sorted { $0.connectedAt > $1.connectedAt }
            processQueuedLocations(format: format)
        }
    }
    
    private func processQueuedLocations(format: PayloadFormat) {
        guard !isProcessingQueue else { return }
        isProcessingQueue = true
        guard let txCharacteristic else{
            isProcessingQueue = false
            return
        }
        
        while !locationQueue.isEmpty && connectedCentralCount > 0 {
            let location = locationQueue.removeFirst()
            let payload: Data = format == .json ? 
                PayloadFormatter.jsonData(from: location) : 
                PayloadFormatter.nmeaData(from: location)
            
            guard !payload.isEmpty else {
                appendLog("ERROR: Failed to format queued location")
                continue
            }
            
            let success = peripheralManager?.updateValue(payload, for: txCharacteristic, onSubscribedCentrals: nil) ?? false
            if !success {
                locationQueue.insert(location, at: 0)
                break
            }
        }
        
        isProcessingQueue = false
    }

    func appendLog(_ message: String) {
        let timestamp = Date().formatted(date: .omitted, time: .standard)
        logs.append("[\(timestamp)] \(message)")
        if logs.count > 300 { logs.removeFirst() }
    }
}

extension BLEManager: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let stateStr = stateDescription(peripheral.state)
        appendLog("🔵 BLE state changed to: \(stateStr)")
        if peripheral.state != .poweredOn {
            isCharacteristicReady = false
            appendLog("⚠️ BLE not powered on, characteristic marked not ready")
            if peripheral.state == .unknown && advertisingRequested {
                appendLog("⏳ BLE state still unknown, retrying advertising soon")
                scheduleAdvertisingRetry()
            }
        } else {
            appendLog("✅ BLE powered on, ready to advertise")
            advertisingRetryCount = 0
            if advertisingRequested {
                appendLog("🔁 Resuming pending advertising now that Bluetooth is powered on")
                beginAdvertising()
            }
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            appendLog("❌ ERROR: Failed to add service: \(error.localizedDescription)")
            isCharacteristicReady = false
        } else {
            isCharacteristicReady = true
            appendLog("📡 Service added successfully!")
            appendLog("   Starting advertising...")
            guard let peripheralManager = self.peripheralManager else { return }
            peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID]])
            isAdvertising = true
            appendLog("   ✓ Advertising started")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        connectedCentralCount += 1
        let deviceId = central.identifier.uuidString.prefix(8)
        let fullUUID = central.identifier.uuidString
        let device = ConnectedDevice(
            id: central.identifier,
            deviceId: String(deviceId),
            connectedAt: Date()
        )
        deviceMap[central.identifier] = device
        connectedDevices = Array(deviceMap.values).sorted { $0.connectedAt > $1.connectedAt }
        appendLog("🟢 DEVICE SUBSCRIBED: [\(deviceId)] Full UUID: \(fullUUID)")
        appendLog("   Total connected: \(connectedCentralCount) | connectedDevices count: \(connectedDevices.count)")
        print("DEBUG: didSubscribeTo called - Device: \(deviceId), connectedDevices: \(connectedDevices)")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        connectedCentralCount = max(0, connectedCentralCount - 1)
        let deviceId = central.identifier.uuidString.prefix(8)
        if var device = deviceMap[central.identifier] {
            device.disconnectedAt = Date()
            deviceMap[central.identifier] = device
        }
        connectedDevices = Array(deviceMap.values).sorted { $0.connectedAt > $1.connectedAt }
        appendLog("🔴 DEVICE UNSUBSCRIBED: [\(deviceId)] | Total connected: \(connectedCentralCount)")
        print("DEBUG: didUnsubscribeFrom called - Device: \(deviceId)")
    }
    
    private func stateDescription(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "Unknown"
        case .resetting: return "Resetting"
        case .unsupported: return "Unsupported"
        case .unauthorized: return "Unauthorized"
        case .poweredOff: return "PoweredOff"
        case .poweredOn: return "PoweredOn"
        @unknown default: return "Unknown"
        }
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
        do {
            return try JSONEncoder().encode(payload)
        } catch {
            print("JSON encoding error: \(error)")
            return Data()
        }
    }

    static func nmeaData(from location: CLLocation) -> Data {
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmmss"
        formatter.timeZone = .init(secondsFromGMT: 0)
        let time = formatter.string(from: location.timestamp)
        let lat = nmeaCoordinate(location.coordinate.latitude, isLatitude: true)
        let lon = nmeaCoordinate(location.coordinate.longitude, isLatitude: false)
        let speedKnots = max(location.speed, 0) * 1.94384
        
        // Build sentence without checksum
        let sentenceWithoutChecksum = "GPRMC,\(time).00,A,\(lat.value),\(lat.dir),\(lon.value),\(lon.dir),\(String(format: "%.1f", speedKnots)),0.0,010100,,,A"
        let checksum = calculateNMEAChecksum(sentenceWithoutChecksum)
        let sentence = "$\(sentenceWithoutChecksum)*\(checksum)"
        return Data(sentence.utf8)
    }

    private static func calculateNMEAChecksum(_ sentence: String) -> String {
        var checksum: UInt8 = 0
        for byte in sentence.utf8 {
            checksum ^= byte
        }
        return String(format: "%02X", checksum)
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
