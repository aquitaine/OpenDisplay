import Foundation

/// Distinguishes external brightness changes from asynchronous writes made by the app.
public struct BrightnessMonitor: Sendable {
    public private(set) var revision: UInt64 = 0
    private var value: Float?
    private var writing = false

    public init() {}

    public mutating func beginWrite() {
        revision += 1
        writing = true
    }

    /// Read back the settled hardware level, including any quantization by the display.
    public mutating func endWrite(value: Float?) {
        revision += 1
        writing = false
        self.value = value
    }

    /// The revision must be captured before the asynchronous read. A read overlapping a write
    /// cannot become a user change, even if that write has finished by the time the read returns.
    public mutating func observe(_ sample: Float, revision: UInt64) -> Bool {
        guard !writing, revision == self.revision, sample.isFinite, (0...1).contains(sample) else {
            return false
        }
        guard let value else {
            self.value = sample
            return false
        }
        guard abs(sample - value) > 0.004 else { return false }
        self.value = sample
        return true
    }
}
