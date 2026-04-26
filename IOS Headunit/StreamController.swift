import Foundation
import Combine

final class StreamController: ObservableObject {
    @Published var selectedFormat: PayloadFormat = .json
    @Published var isStreaming = false
    @Published var reconnectDelay: TimeInterval = 1
    @Published var locationProvider: LocationProvider

    let bleManager: BLEManager
    
    private var cancellables = Set<AnyCancellable>()
    private let userDefaults = UserDefaults.standard
    private let streamingStateKey = "BLE_Streaming_Active"
    private let selectedFormatKey = "BLE_Selected_Format"

    init(bleManager: BLEManager = .init(), locationProvider: LocationProvider = .init()) {
        self.bleManager = bleManager
        self.locationProvider = locationProvider
        loadPersistedState()
        bind()
    }

    func start() {
        isStreaming = true
        reconnectDelay = 1
        persistState()
        locationProvider.start()
        bleManager.startAdvertising()
        bleManager.appendLog("▶️ STREAMING: Started with format: \(selectedFormat.rawValue.uppercased())")
    }

    func stop() {
        isStreaming = false
        locationProvider.stop()
        bleManager.stopAdvertising()
        persistState()
        bleManager.appendLog("⏹ STREAMING: Stopped")
    }
    
    private func loadPersistedState() {
        let wasStreaming = userDefaults.bool(forKey: streamingStateKey)
        if let formatStr = userDefaults.string(forKey: selectedFormatKey),
           let format = PayloadFormat(rawValue: formatStr) {
            selectedFormat = format
        }
        // Don't auto-resume streaming - user must manually start
        bleManager.appendLog("App Launched - Persisted state loaded")
    }
    
    private func persistState() {
        userDefaults.set(isStreaming, forKey: streamingStateKey)
        userDefaults.set(selectedFormat.rawValue, forKey: selectedFormatKey)
    }

    private func bind() {
        locationProvider.$latestLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                guard let self, self.isStreaming else {
                    if !(self?.isStreaming ?? false) ?? false {
                        self?.bleManager.appendLog("⏸ Location arrived but streaming is OFF")
                    }
                    return
                }
                self.bleManager.appendLog("📤 Sending location via BLE...")
                self.bleManager.stream(location: location, format: self.selectedFormat)
            }
            .store(in: &cancellables)

        bleManager.$connectedCentralCount
            .sink { [weak self] count in
                guard let self else { return }
                if count == 0 && self.isStreaming {
                    self.retryAdvertisingWithBackoff()
                } else {
                    self.reconnectDelay = 1
                }
            }
            .store(in: &cancellables)
        
        // Log format changes
        $selectedFormat
            .sink { [weak self] format in
                guard let self else { return }
                if self.isStreaming {
                    self.bleManager.appendLog("Format changed to: \(format.rawValue.uppercased())")
                    self.persistState()
                }
            }
            .store(in: &cancellables)
    }

    private func retryAdvertisingWithBackoff() {
        let delay = reconnectDelay
        bleManager.appendLog("⚠️ No centrals connected, retrying in \(Int(delay))s...")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isStreaming else { return }
            self.bleManager.startAdvertising()
            self.reconnectDelay = min(self.reconnectDelay * 2, 32)
        }
    }
}
