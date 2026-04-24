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
                    Text("Streaming: \(controller.isStreaming ? "On" : "Off")")
                    Text("Advertising: \(controller.bleManager.isAdvertising ? "Yes" : "No")")
                    Text("Connected centrals: \(controller.bleManager.connectedCentralCount)")
                }
                Section("Controls") {
                    Picker("Payload", selection: $controller.selectedFormat) {
                        ForEach(PayloadFormat.allCases, id: \.self) { format in
                            Text(format.rawValue.uppercased()).tag(format)
                        }
                    }
                    Button(controller.isStreaming ? "Stop Stream" : "Start Stream") {
                        controller.isStreaming ? controller.stop() : controller.start()
                    }
                }
            }
            .navigationTitle("GPS BLE Streamer")
        }
    }

    private var deviceListView: some View {
        NavigationView {
            List {
                Text("Service: \(BLEManager.serviceUUID.uuidString)")
                Text("Characteristic: \(BLEManager.characteristicUUID.uuidString)")
                ForEach(controller.bleManager.logs.suffix(20), id: \.self) { log in
                    Text(log).font(.caption2)
                }
            }
            .navigationTitle("Device List")
        }
    }

    private var settingsView: some View {
        NavigationView {
            Form {
                Toggle("Use Simulated Route", isOn: $controller.locationProvider.useSimulatedRoute)
                Section("Location Logs") {
                    ForEach(controller.locationProvider.logs.suffix(20), id: \.self) { log in
                        Text(log).font(.caption2)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
