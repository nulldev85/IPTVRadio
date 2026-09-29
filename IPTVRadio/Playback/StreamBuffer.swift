import Foundation

/// How much audio the player holds in reserve ahead of what is being heard.
///
/// The reserve is what carries a live stream through a gap in delivery: while
/// the network stalls, playback drains it instead of going silent, and when
/// the data catches up it fills again. Its cost is time. The player fills it
/// before anything plays, both when a station starts and after a gap longer
/// than the reserve itself.
///
/// Wi-Fi keeps the standard buffer, so stations start quickly. Cellular data
/// is where the gaps are — fading signal, tower handovers and congested cells
/// all pause delivery for a moment, and with only the standard reserve each
/// of those is an audible pause — so the cellular buffer is the listener's to
/// raise.
///
/// Pure logic, so the choice is unit tested rather than observed.
struct StreamBuffer: Equatable {
    /// Seconds of audio held in reserve.
    let duration: TimeInterval
    /// True when this is the listener's cellular buffer rather than the
    /// standard one.
    let isCellular: Bool

    /// The buffer every stream used before it could be adjusted. The engine's
    /// startup and stall timeouts were tuned against it.
    static let standardDuration: TimeInterval = 4

    /// What the cellular buffer can be set to. It starts at the standard
    /// buffer, because the point is to hold more on cellular, never less; past
    /// half a minute a station takes too long to start to be worth it.
    static let cellularRange: ClosedRange<TimeInterval> = standardDuration...30

    static let standard = StreamBuffer(duration: standardDuration, isCellular: false)

    /// The buffer for a stream opened on the given connection.
    ///
    /// A Personal Hotspot counts as cellular. It reaches the device as Wi-Fi,
    /// but it is cellular data underneath with the same drop-outs, and it is
    /// how a Wi-Fi-only iPad streams in a car. iOS flags it as expensive,
    /// which is what tells it apart from ordinary Wi-Fi.
    static func forConnection(
        isCellular: Bool,
        isExpensive: Bool,
        cellularSetting: TimeInterval
    ) -> StreamBuffer {
        guard isCellular || isExpensive else { return .standard }
        return StreamBuffer(duration: clampedCellularDuration(cellularSetting), isCellular: true)
    }

    /// The cellular setting brought into range. A value that is not finite
    /// falls back to the standard buffer rather than reaching the player,
    /// which converts it to whole milliseconds.
    static func clampedCellularDuration(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else { return standardDuration }
        return min(max(seconds, cellularRange.lowerBound), cellularRange.upperBound)
    }

    /// How much longer than the standard buffer this one takes to fill.
    ///
    /// The engine extends its startup and stall timeouts by this much. Without
    /// it, a stream still filling a larger buffer looks dead and is torn down;
    /// and with a buffer longer than the stall timeout, the reconnect would
    /// start the fill over again, so the station would never play at all.
    var extraFillTime: TimeInterval { max(0, duration - Self.standardDuration) }
}
