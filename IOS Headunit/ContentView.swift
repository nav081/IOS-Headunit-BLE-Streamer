import SwiftUI
import CoreBluetooth

struct ContentView: View {
    @StateObject private var controller = StreamController()

    var body: some View {
        TabView {
            homeView
                .tabItem { Label("Home", systemImage: "house") }
            deviceListView
                .tabItem { Label("Devices", systemImage: "dot.radiowaves.left.and.right") }
            settingsView
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .onAppear { controller.locationProvider.requestPermissions() }
    }

    private var homeView: some View {
        NavigationView {
            Form {
                Section("Status") {
                    HStack {
                        Text("Streaming")
                        Spacer()
                        Text(controller.isStreaming ? "▶️ ON" : "⏹ OFF")
                            .foregroundColor(controller.isStreaming ? .green : .red)
                            .fontWeight(.bold)
                    }
                    HStack {
                        Text("Bluetooth Permission")
                        Spacer()
                        Text(bluetoothPermissionText)
                            .foregroundColor(bluetoothPermissionColor)
                            .fontWeight(.semibold)
                    }
                    HStack {
                        Text("Bluetooth State")
                        Spacer()
                        Text(bluetoothStateText)
                            .foregroundColor(bluetoothStateColor)
                    }
                    HStack {
                        Text("Advertising")
                        Spacer()
                        Text(controller.bleManager.isAdvertising ? "✓ Yes" : "✗ No")
                            .foregroundColor(controller.bleManager.isAdvertising ? .green : .gray)
                    }
                    HStack {
                        Text("Connected Devices")
                        Spacer()
                        Text("\(controller.bleManager.connectedCentralCount)")
                            .fontWeight(.bold)
                            .foregroundColor(controller.bleManager.connectedCentralCount > 0 ? .green : .gray)
                    }
                }
                Section("Controls") {
                    Picker("Payload Format", selection: $controller.selectedFormat) {
                        ForEach(PayloadFormat.allCases, id: \.self) { format in
                            Text(format.rawValue.uppercased()).tag(format)
                        }
                    }
                    Button(controller.isStreaming ? "Stop Stream" : "Start Stream") {
                        controller.isStreaming ? controller.stop() : controller.start()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .foregroundColor(.white)
                    .background(controller.isStreaming ? Color.red : Color.green)
                    .cornerRadius(8)
                }
                Section("Recent Logs") {
                    if controller.bleManager.logs.isEmpty {
                        Text("No logs yet").foregroundColor(.gray)
                    } else {
                        ForEach(controller.bleManager.logs.suffix(10), id: \.self) { log in
                            Text(log).font(.caption2).lineLimit(2)
                        }
                    }
                }
            }
            .navigationTitle("GPS BLE Streamer")
        }
    }

    private var deviceListView: some View {
        NavigationView {
            List {
                Section("Service Info") {
                    Text("Service UUID:")
                    Text(BLEManager.serviceUUID.uuidString)
                        .font(.caption)
                        .textSelection(.enabled)
                    Text("Characteristic UUID:")
                    Text(BLEManager.characteristicUUID.uuidString)
                        .font(.caption)
                        .textSelection(.enabled)
                }
                
                if !controller.bleManager.connectedDevices.isEmpty {
                    Section("Connected Devices (\(controller.bleManager.connectedDevices.filter { $0.isConnected }.count))") {
                        ForEach(controller.bleManager.connectedDevices.filter { $0.isConnected }, id: \.id) { device in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Device ID: \(device.deviceId)")
                                        .fontWeight(.bold)
                                    Spacer()
                                    Text("🟢 Active")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                                Text("Connected: \(device.connectedAt.formatted(date: .omitted, time: .standard))")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                HStack {
                                    Text("Packets: \(device.dataPacketsSent)")
                                    Spacer()
                                    Text("Bytes: \(device.totalBytesSent)")
                                }
                                .font(.caption2)
                                .foregroundColor(.blue)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                if controller.bleManager.connectedDevices.contains(where: { !$0.isConnected }) {
                    Section("Disconnected Devices") {
                        ForEach(controller.bleManager.connectedDevices.filter { !$0.isConnected }, id: \.id) { device in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Device ID: \(device.deviceId)")
                                        .fontWeight(.bold)
                                    Spacer()
                                    Text("🔴 Offline")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                Text("Duration: \(formatDuration(device.connectionDuration))")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                HStack {
                                    Text("Packets: \(device.dataPacketsSent)")
                                    Spacer()
                                    Text("Bytes: \(device.totalBytesSent)")
                                }
                                .font(.caption2)
                                .foregroundColor(.gray)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                Section("BLE Event Log (Last 15)") {
                    if controller.bleManager.logs.isEmpty {
                        Text("No events").foregroundColor(.gray)
                    } else {
                        ForEach(controller.bleManager.logs.suffix(15), id: \.self) { log in
                            Text(log).font(.caption2).lineLimit(3)
                        }
                    }
                }
            }
            .navigationTitle("Device List")
        }
    }

    private var settingsView: some View {
        NavigationView {
            Form {
                Section("Location Mode") {
                    Toggle("Use Simulated Route", isOn: $controller.locationProvider.useSimulatedRoute)
                        .onChange(of: controller.locationProvider.useSimulatedRoute) { _, newValue in
                            if controller.isStreaming {
                                controller.locationProvider.stop()
                                controller.locationProvider.start()
                            }
                        }
                }
                Section("Location Logs") {
                    if controller.locationProvider.logs.isEmpty {
                        Text("No logs").foregroundColor(.gray)
                    } else {
                        ForEach(controller.locationProvider.logs.suffix(15), id: \.self) { log in
                            Text(log).font(.caption2).lineLimit(2)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return "\(mins)m \(secs)s"
        }
        return "\(secs)s"
    }

    private var bluetoothPermissionText: String {
        switch controller.bleManager.authorizationStatus {
        case .allowedAlways:
            return "Allowed"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Determined"
        @unknown default:
            return "Unknown"
        }
    }

    private var bluetoothPermissionColor: Color {
        switch controller.bleManager.authorizationStatus {
        case .allowedAlways:
            return .green
        case .denied, .restricted:
            return .red
        case .notDetermined:
            return .orange
        @unknown default:
            return .gray
        }
    }

    private var bluetoothStateText: String {
        controller.bleManager.isAdvertising ? "Powered On" : "Waiting / Off"
    }

    private var bluetoothStateColor: Color {
        controller.bleManager.isAdvertising ? .green : .gray
    }
}
