import Foundation

/// One navigation step per trackpad gesture or burst of unphased wheel events.
/// Momentum belongs to the completed gesture, never to the next column.
public struct ScrollingGesture: Sendable {
    public enum Phase: Sendable { case began, changed, ended, cancelled, unphased }
    private var active = false
    private var fired = false
    private var distance = 0.0
    private var lastEvent: Double?
    public init() {}

    public mutating func reset() { self = Self() }

    public mutating func consume(delta: Double, time: Double, phase: Phase,
                                 momentum: Bool, precise: Bool) -> WindowDirection? {
        guard delta.isFinite, time.isFinite else { return nil }
        guard !momentum else { return nil }
        if phase == .ended || phase == .cancelled {
            active = false; lastEvent = time
            return nil
        }
        let newBurst = phase == .unphased && lastEvent.map { time - $0 > 0.25 } != false
        if phase == .began || newBurst || (phase == .changed && !active) {
            fired = false; distance = 0
        }
        active = phase != .unphased
        lastEvent = time
        guard !fired else { return nil }
        distance += delta
        guard abs(distance) >= (precise ? 8 : 1) else { return nil }
        fired = true
        return distance > 0 ? .left : .right
    }
}
