import DisplayDomain
import Foundation

/// What a hardware media key does (Batch-3 #1). Distinct from `HotkeyAction` (configurable Carbon
/// chords): these are the fixed `NX_KEYTYPE_*` keys captured by the macOS event tap, mapped here to a
/// semantic action plus a signed step so the app can drive the right control on the right display.
public enum MediaKeyAction: String, Hashable, Sendable, CaseIterable {
    case brightnessUp
    case brightnessDown
    case volumeUp
    case volumeDown
    case muteToggle

    /// The IOKit `NX_KEYTYPE_*` subtype code → action (`ev_keymap.h`). Unknown codes return nil, so the
    /// tap lets that key pass through to macOS untouched.
    public static func from(nxKeyType code: Int) -> MediaKeyAction? {
        switch code {
        case NXKeyType.soundUp: return .volumeUp
        case NXKeyType.soundDown: return .volumeDown
        case NXKeyType.mute: return .muteToggle
        case NXKeyType.brightnessUp: return .brightnessUp
        case NXKeyType.brightnessDown: return .brightnessDown
        default: return nil
        }
    }

    /// True for the volume/mute keys. Unlike brightness (which follows `MediaKeyTargetMode`), these
    /// route to whichever display carries the system's *default audio output* — driving that monitor's
    /// DDC volume (VCP `0x62`) only when the sound is actually coming out of it, and otherwise passing
    /// through so macOS adjusts the real output device (speakers, AirPods, USB DAC) with its own HUD.
    public var isVolume: Bool {
        switch self {
        case .volumeUp, .volumeDown, .muteToggle: return true
        case .brightnessUp, .brightnessDown: return false
        }
    }

    public var isBrightness: Bool { !isVolume }

    /// +1 to raise, -1 to lower, 0 for a non-directional action (mute).
    public var sign: Float {
        switch self {
        case .brightnessUp, .volumeUp: return 1
        case .brightnessDown, .volumeDown: return -1
        case .muteToggle: return 0
        }
    }

    /// The signed level change this key applies. macOS moves brightness/volume in 1/16 steps, and a
    /// quarter-step (1/64) while ⇧⌥ is held — mirror that. Mute returns 0 (the caller toggles state).
    public func signedDelta(fineStep: Bool) -> Float {
        sign * (fineStep ? MediaKeyStep.fine : MediaKeyStep.coarse)
    }
}

/// macOS media-key step sizes (fraction of the 0...1 range).
public enum MediaKeyStep {
    public static let coarse: Float = 1.0 / 16.0
    public static let fine: Float = 1.0 / 64.0
}

/// IOKit `NX_KEYTYPE_*` subtype codes for the media keys we care about (`ev_keymap.h`). Held here as
/// plain constants so the cross-platform core needn't import IOKit; the macOS tap decodes the event
/// subtype and passes the integer in.
public enum NXKeyType {
    public static let soundUp = 0
    public static let soundDown = 1
    public static let brightnessUp = 2
    public static let brightnessDown = 3
    public static let mute = 7
}

/// Which display a media key acts on (persisted in settings, Batch-3 #3/#5).
public enum MediaKeyTargetMode: String, Hashable, Sendable, Codable, CaseIterable {
    /// The display under the pointer (falls back to the main display).
    case underCursor
    /// Always the current main display.
    case mainDisplay
    /// Always the built-in panel (falls back to main).
    case builtInAlways
}

/// Chooses the display a media key should drive (Batch-3 #1). Pure.
///
/// Brightness keys follow `mode` (under cursor / main / built-in). Volume/mute keys IGNORE `mode` and
/// the cursor entirely: they route to `audioTarget` — the display carrying the system's default audio
/// output — so the keys drive the DDC volume of whatever the sound is actually playing on. Returns nil
/// to let the key pass through to macOS: for brightness when there's no active display, for volume when
/// the audio route isn't a display, isn't active, or isn't DDC-volume-capable.
public enum MediaKeyTargetPolicy {
    public static func target(
        for action: MediaKeyAction,
        in displays: [DisplayObservation],
        cursor: DisplayOrigin?,
        mode: MediaKeyTargetMode,
        volumeCapable: Set<DisplayRecordID>,
        audioTarget: DisplayRecordID?
    ) -> DisplayObservation? {
        let active = displays.filter { $0.isActive }
        guard !active.isEmpty else { return nil }

        if action.isVolume {
            // Volume follows the default audio output device, not the brightness target mode. Drive the
            // monitor's DDC volume only when the audio routes through an active, DDC-volume-capable
            // display; otherwise nil so the tap lets the key fall through to the real output device.
            guard let audioTarget, volumeCapable.contains(audioTarget),
                  let target = active.first(where: { $0.recordID == audioTarget })
            else { return nil }
            return target
        }

        switch mode {
        case .underCursor:
            return cursor.flatMap { point in active.first { contains($0, point) } }
                ?? active.first { $0.isMain } ?? active.first
        case .mainDisplay:
            return active.first { $0.isMain } ?? active.first
        case .builtInAlways:
            return active.first { $0.displayClass == .builtIn }
                ?? active.first { $0.isMain } ?? active.first
        }
    }

    /// True if global point `p` lies within `display`'s bounds (origin + point size).
    static func contains(_ display: DisplayObservation, _ p: DisplayOrigin) -> Bool {
        guard let mode = display.mode else { return false }
        return p.x >= display.origin.x && p.x < display.origin.x + mode.pointWidth
            && p.y >= display.origin.y && p.y < display.origin.y + mode.pointHeight
    }
}
