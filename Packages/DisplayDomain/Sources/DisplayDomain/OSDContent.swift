import Foundation

/// What an on-screen-display HUD should show for a brightness/volume/mute change (Batch-3 #2). Pure
/// value type (exercised by `make test`); the macOS layer renders it in a floating panel.
public struct OSDContent: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable, Codable {
        case brightness
        case volume
        case mute
    }

    /// Number of segments in the native-style bar.
    public static let segmentCount = 16

    public var kind: Kind
    /// Normalized level, always clamped to 0...1.
    public var value: Float

    public init(kind: Kind, value: Float) {
        self.kind = kind
        self.value = max(0, min(1, value))
    }

    /// Filled segments (0...16) for the bar, rounded to the nearest segment.
    public var filledSegments: Int {
        let n = Int((value * Float(Self.segmentCount)).rounded())
        return max(0, min(Self.segmentCount, n))
    }

    /// Whole-percent level for an optional numeric readout.
    public var percent: Int { Int((value * 100).rounded()) }

    /// SF Symbol glyph for this content. A style may swap it, but this is the native-looking default.
    public var glyph: String {
        switch kind {
        case .brightness: return "sun.max"
        case .mute: return "speaker.slash"
        case .volume:
            if value <= 0 { return "speaker.slash" }
            return value < 0.5 ? "speaker.wave.1" : "speaker.wave.2"
        }
    }
}
