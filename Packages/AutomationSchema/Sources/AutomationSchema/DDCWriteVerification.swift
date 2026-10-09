/// Decides whether a DDC write actually took, from a read-back of the same feature.
///
/// Why this exists: DDC/CI writes are fire-and-forget. A monitor ACKs a Set-VCP it then silently
/// ignores — an LG HDR WQHD+ drops every contrast write while its picture mode locks contrast, and
/// only honours colour-preset codes 5/8/11 even though it reports a max of 12. Without a read-back
/// the app's slider/menu shows the value we *asked for*, not the one the panel is at, so the
/// control looks like it "does nothing" and the UI lies about it.
///
/// The decision is deliberately conservative in one direction: a missing read-back (`nil`) is
/// `.unknown`, never `.ignored`. DDC reads are flaky (busy bus, waking scaler, mildly wedged
/// panels), and calling a good write "ignored" would snap a correct slider back to a stale value —
/// strictly worse than leaving the optimistic value in place.
public enum DDCWriteVerification: Equatable, Sendable {
    /// The panel reports the value we wrote (within `tolerance`).
    case applied
    /// The panel answered with a different value — it ignored or clamped the write.
    case ignored(actual: Int)
    /// No read-back; nothing can be concluded.
    case unknown

    /// - Parameters:
    ///   - target: the value last written, in the panel's native units.
    ///   - readback: the panel's current value from a Get-VCP after the write, or nil if unread.
    ///   - tolerance: accepted absolute difference. Continuous controls use 1 because the 0...1
    ///     slider is scaled to the panel's max and rounded, and some panels quantise by one unit;
    ///     discrete features (colour preset) must use 0.
    public static func outcome(target: Int, readback: Int?, tolerance: Int = 0) -> DDCWriteVerification {
        guard let readback else { return .unknown }
        return abs(readback - target) <= max(tolerance, 0) ? .applied : .ignored(actual: readback)
    }
}
