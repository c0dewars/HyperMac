import Foundation

/// A navigation target is authoritative until explicit user focus changes it.
/// App activation acknowledgements can arrive late or out of order during repeats.
public struct ScrollingFocus: Sendable {
    public private(set) var requested: Int?
    public init() {}
    public mutating func request(_ id: Int) { requested = id }
    public mutating func userInteracted() { requested = nil }
    public mutating func resolve(observed: Int?, live: Set<Int>, fallback: Int?) -> Int? {
        if let requested, live.contains(requested) { return requested }
        requested = nil
        if let observed, live.contains(observed) { return observed }
        return fallback.flatMap { live.contains($0) ? $0 : nil }
    }
}
