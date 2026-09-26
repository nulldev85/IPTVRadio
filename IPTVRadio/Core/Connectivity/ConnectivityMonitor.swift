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
    /// Published after all path fields change, so playback sees a complete
    /// Wi-Fi/cellular transition.
    @Published private(set) var pathRevision = 0

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
                self?.updatePath(
                    status: isSatisfied ? .online : .offline,
                    isCellular: cellular,
                    isExpensive: expensive
                )
            }
        }
        monitor.start(queue: DispatchQueue(label: "connectivity.monitor"))
    }

    func stop() {
        monitor.cancel()
        started = false
    }

    /// Also used by playback tests to simulate a complete network transition.
    func updatePath(status: Status, isCellular: Bool, isExpensive: Bool = false) {
        self.status = status
        self.isCellular = isCellular
        self.isExpensive = isExpensive
        pathRevision &+= 1
    }
}
