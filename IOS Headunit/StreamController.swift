import Foundation
import Combine

final class StreamController: ObservableObject {
    @Published var selectedFormat: PayloadFormat = .json
    @Published var isStreaming = false
    @Published var reconnectDelay: TimeInterval = 1
    @Published var locationProvider: LocationProvider

    let bleManager: BLEManager
    
    private var cancellables = Set<AnyCancellable>()

    init(bleManager: BLEManager = .init(), locationProvider: LocationProvider = .init()) {
        self.bleManager = bleManager
        self.locationProvider = locationProvider
        bind()
    }

    func start() {
        isStreaming = true
        reconnectDelay = 1
        locationProvider.start()
        bleManager.startAdvertising()
    }

    func stop() {
        isStreaming = false
        locationProvider.stop()
        bleManager.stopAdvertising()
    }

    private func bind() {
        locationProvider.$latestLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                guard let self, self.isStreaming else { return }
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
    }

    private func retryAdvertisingWithBackoff() {
        let delay = reconnectDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isStreaming else { return }
            self.bleManager.startAdvertising()
            self.reconnectDelay = min(self.reconnectDelay * 2, 32)
        }
    }
}
