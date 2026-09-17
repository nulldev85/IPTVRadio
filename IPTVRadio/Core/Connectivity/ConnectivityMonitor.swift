import Foundation
import Network

/// Lightweight connectivity monitor. Publishes reachability and whether the
/// current path is expensive (cellular) so playback can honor user settings.
@MainActor
final class ConnectivityMonitor: ObservableObject {
    enum Status: Equatable {
        case online
        case offline
    }

    @Published private(set) var status: Status = .online
    // Setter is internal to allow unit tests to simulate network paths.
    @Published var isCellular = false
    @Published private(set) var isExpensive = false

    private let monitor = NWPathMonitor()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let isSatisfied = path.status == .satisfied
            let cellular = path.usesInterfaceType(.cellular)
            let expensive = path.isExpensive
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.status = isSatisfied ? .online : .offline
                self.isCellular = cellular
                self.isExpensive = expensive
            }
        }
        monitor.start(queue: DispatchQueue(label: "connectivity.monitor"))
    }

    func stop() {
        monitor.cancel()
        started = false
    }
}
