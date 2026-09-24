import Foundation

/// What the engine is doing, and to which station. The station travels with
/// the state so every screen can render from one value.
enum PlaybackState: Equatable {
    case idle
    case loading(RadioStation)
    case playing(RadioStation)
    case paused(RadioStation)
    case stopped(RadioStation?)
    case failed(String, RadioStation?)

    var station: RadioStation? {
        switch self {
        case .idle: return nil
        case .loading(let s): return s
        case .playing(let s): return s
        case .paused(let s): return s
        case .stopped(let s): return s
        case .failed(_, let s): return s
        }
    }

    var isPlaying: Bool {
        if case .playing = self { return true }
        return false
    }

    var isBusy: Bool {
        if case .loading = self { return true }
        return false
    }
}

// MARK: - Player abstraction (DI seam for tests)
