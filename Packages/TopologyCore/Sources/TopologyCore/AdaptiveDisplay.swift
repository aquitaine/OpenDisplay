import Foundation

/// Tunables for Adaptive Display, derived from `OpenDisplaySettings` (one value object so the
/// policy signature stays stable as knobs are added).
public struct AdaptiveDisplayConfig: Hashable, Sendable {
    /// Minute-of-day the day phase begins (ramp up starts here).
    public var dayStartMinute: Int
    /// Minute-of-day the night phase begins (ramp down starts here).
    public var nightStartMinute: Int
    /// Width in minutes of the linear ramp at each edge.
    public var transitionMinutes: Int
    /// Schedule-fallback brightness plateaus (0...1).
    public var fallbackDayLevel: Float
    public var fallbackNightLevel: Float
    /// Colour-preset code applied during the evening phase (MCCS 0x14).
    public var eveningPreset: Int
    /// Minimum target movement before a DDC write is issued. Keeps quiet-light ticks write-free
    /// and bounds bus traffic; DDC values are 0...100 on most panels, so 0.02 ≈ 2 panel steps.
    public var hysteresis: Float
    /// Seconds after a manual brightness change during which adaptive stays hands-off (sync mode).
    public var manualCooldown: TimeInterval

    public init(dayStartMinute: Int = 420, nightStartMinute: Int = 1140, transitionMinutes: Int = 30,
                fallbackDayLevel: Float = 0.8, fallbackNightLevel: Float = 0.35,
                eveningPreset: Int = 4, hysteresis: Float = 0.02, manualCooldown: TimeInterval = 60) {
        self.dayStartMinute = dayStartMinute
        self.nightStartMinute = nightStartMinute
        self.transitionMinutes = transitionMinutes
        self.fallbackDayLevel = fallbackDayLevel
        self.fallbackNightLevel = fallbackNightLevel
        self.eveningPreset = eveningPreset
        self.hysteresis = hysteresis
        self.manualCooldown = manualCooldown
    }
}

extension OpenDisplaySettings {
    /// The adaptive tunables as one value (hysteresis/cooldown are code constants, not settings).
    public var adaptiveConfig: AdaptiveDisplayConfig {
        AdaptiveDisplayConfig(
            dayStartMinute: adaptiveDayStartMinute, nightStartMinute: adaptiveNightStartMinute,
            transitionMinutes: adaptiveTransitionMinutes, fallbackDayLevel: adaptiveFallbackDayLevel,
            fallbackNightLevel: adaptiveFallbackNightLevel, eveningPreset: adaptiveEveningPreset)
    }
}

/// Pure decision core for Adaptive Display (brightness sync + evening warmth), the "transfer the
/// built-in display's intelligence to the external monitor" feature.
///
/// Deterministic and clock-free: the caller injects `now` (used only for cooldown arithmetic) and
/// `minuteOfDay` (so the policy never touches Calendar/timezones), threads a caller-owned
/// `DisplayState` through, and receives a `Decision` naming the writes to perform. All hardware,
/// persistence, and UI side effects belong to the caller (AppModel) — this type is exercised by
/// `make test` like `MediaKeyTargetPolicy` and `OSDPresentationPolicy`.
public enum AdaptiveDisplayPolicy {
    public enum WarmthPhase: String, Hashable, Sendable, Codable { case day, evening }

    /// Caller-owned per-display evolution state, threaded through `evaluate`.
    public struct DisplayState: Hashable, Sendable {
        /// Hysteresis anchor: the last brightness adaptive wrote (or adopted from a manual change).
        public var lastWrittenBrightness: Float?
        /// Learned offset relative to the built-in (sync mode): external = builtIn + offset.
        public var brightnessOffset: Float
        /// When the user last changed brightness manually (cooldown anchor); nil = never.
        public var manualBrightnessAt: Date?
        /// Schedule-mode adoption: the schedule target at the moment of the manual change. While the
        /// schedule target stays within hysteresis of this anchor, adaptive holds off — a bare
        /// cooldown would snap the user's setting back after 60s even though nothing changed.
        public var manualScheduleAnchor: Float?
        /// Which warmth phase the policy believes this display is in. Seed `.day`.
        public var warmthPhase: WarmthPhase
        /// The user picked a preset manually during the current evening phase — adopt it for the
        /// rest of the phase (no more preset writes until the next transition).
        public var presetOverridden: Bool

        public init(lastWrittenBrightness: Float? = nil, brightnessOffset: Float = 0,
                    manualBrightnessAt: Date? = nil, manualScheduleAnchor: Float? = nil,
                    warmthPhase: WarmthPhase = .day, presetOverridden: Bool = false) {
            self.lastWrittenBrightness = lastWrittenBrightness
            self.brightnessOffset = brightnessOffset
            self.manualBrightnessAt = manualBrightnessAt
            self.manualScheduleAnchor = manualScheduleAnchor
            self.warmthPhase = warmthPhase
            self.presetOverridden = presetOverridden
        }
    }

    /// One tick's worth of observed world, assembled by the caller.
    public struct Input: Hashable, Sendable {
        public var now: Date
        public var minuteOfDay: Int
        /// Topology says a built-in panel is ACTIVE (false ⇒ built-in off or lid closed). Never
        /// derive this from a read failure — a transient failure must skip the tick, not flip modes.
        public var builtInPresent: Bool
        /// The built-in's current brightness, nil on a transient read failure.
        public var builtInBrightness: Float?
        /// Smoothed ambient light in lux, when the sensor is readable (lid open). Drives brightness
        /// directly when the built-in is off-but-lid-open — the user's "internal display off, Mac
        /// keyboard" mode — so real light intelligence survives without any panel to mirror.
        public var ambientLux: Double?
        /// This external is asleep — adaptive must not touch it at all.
        public var displayAsleep: Bool
        /// The external's current colour preset (cache); nil ⇒ warmth is inert for this display.
        public var currentPreset: Int?
        /// Persisted day-preset memory (nil ⇒ no restore owed).
        public var dayPreset: Int?
        /// macOS Night Shift's live state; nil ⇒ reader unavailable → schedule decides evening.
        public var nightShiftActive: Bool?
        public var brightnessSyncEnabled: Bool
        public var warmthEnabled: Bool

        public init(now: Date, minuteOfDay: Int, builtInPresent: Bool, builtInBrightness: Float?,
                    ambientLux: Double? = nil, displayAsleep: Bool, currentPreset: Int?,
                    dayPreset: Int?, nightShiftActive: Bool?, brightnessSyncEnabled: Bool,
                    warmthEnabled: Bool) {
            self.now = now
            self.minuteOfDay = minuteOfDay
            self.builtInPresent = builtInPresent
            self.builtInBrightness = builtInBrightness
            self.ambientLux = ambientLux
            self.displayAsleep = displayAsleep
            self.currentPreset = currentPreset
            self.dayPreset = dayPreset
            self.nightShiftActive = nightShiftActive
            self.brightnessSyncEnabled = brightnessSyncEnabled
            self.warmthEnabled = warmthEnabled
        }
    }

    /// What the caller should do this tick. Apply in THIS order: persist `rememberDayPreset`
    /// (BEFORE the preset write — the restore-owed invariant), then `presetWrite`, then
    /// `clearDayPreset` (persist the removal), then `brightnessWrite`, then store `state`.
    public struct Decision: Hashable, Sendable {
        public var brightnessWrite: Float?
        public var presetWrite: Int?
        public var rememberDayPreset: Int?
        public var clearDayPreset: Bool
        public var state: DisplayState

        public init(brightnessWrite: Float? = nil, presetWrite: Int? = nil,
                    rememberDayPreset: Int? = nil, clearDayPreset: Bool = false,
                    state: DisplayState) {
            self.brightnessWrite = brightnessWrite
            self.presetWrite = presetWrite
            self.rememberDayPreset = rememberDayPreset
            self.clearDayPreset = clearDayPreset
            self.state = state
        }
    }

    // MARK: - Schedule curve

    /// The schedule-fallback brightness at a minute-of-day: day/night plateaus joined by linear
    /// ramps of `transitionMinutes` starting at each edge (day ramps UP from `dayStartMinute`,
    /// night ramps DOWN from `nightStartMinute`). Handles night phases that wrap midnight.
    public static func scheduleLevel(atMinute minute: Int, config: AdaptiveDisplayConfig) -> Float {
        let ramp = max(1, config.transitionMinutes)
        let day = config.fallbackDayLevel
        let night = config.fallbackNightLevel
        if let progress = rampProgress(minute, from: config.dayStartMinute, width: ramp) {
            return night + (day - night) * progress  // morning: night → day
        }
        if let progress = rampProgress(minute, from: config.nightStartMinute, width: ramp) {
            return day - (day - night) * progress    // evening: day → night
        }
        return isNightPlateau(minute, config: config) ? night : day
    }

    /// Whether a minute-of-day falls in the night phase (for warmth, the schedule fallback when
    /// Night Shift is unreadable). The evening phase begins AT `nightStartMinute` and ends AT
    /// `dayStartMinute`; transitions don't apply to warmth — presets are discrete.
    public static func scheduleIsNight(atMinute minute: Int, config: AdaptiveDisplayConfig) -> Bool {
        inWrappedRange(minute, from: config.nightStartMinute, to: config.dayStartMinute)
    }

    /// Brightness level for an ambient light reading: log-linear from 10 lux (dark room → 0.25)
    /// to 5000 lux (bright daylight room → 1.0). Log because perception and typical indoor
    /// lighting both span orders of magnitude — linear lux would slam to full brightness the
    /// moment a lamp comes on. The learned per-display offset applies on top, so the curve only
    /// has to be *reasonable*, not perfect for every room.
    public static func ambientLevel(forLux lux: Double) -> Float {
        let floorLux = 10.0, ceilLux = 5000.0
        let floorLevel: Float = 0.25, ceilLevel: Float = 1.0
        guard lux > floorLux else { return floorLevel }
        guard lux < ceilLux else { return ceilLevel }
        let progress = Float((log10(lux) - log10(floorLux)) / (log10(ceilLux) - log10(floorLux)))
        return floorLevel + (ceilLevel - floorLevel) * progress
    }

    /// Progress 0...1 through a ramp starting at `start` of `width` minutes, or nil outside it
    /// (wrap-aware: a ramp beginning at 23:50 continues past midnight).
    private static func rampProgress(_ minute: Int, from start: Int, width: Int) -> Float? {
        let delta = ((minute - start) % 1440 + 1440) % 1440
        guard delta < width else { return nil }
        return (Float(delta) + 1) / Float(width)
    }

    private static func isNightPlateau(_ minute: Int, config: AdaptiveDisplayConfig) -> Bool {
        inWrappedRange(minute, from: config.nightStartMinute, to: config.dayStartMinute)
    }

    /// Whether `minute` lies in [from, to) on a 24h clock, correctly when the range wraps midnight.
    private static func inWrappedRange(_ minute: Int, from: Int, to: Int) -> Bool {
        if from == to { return false }
        if from < to { return minute >= from && minute < to }
        return minute >= from || minute < to
    }

    // MARK: - Manual-change bookkeeping

    /// Record a user-initiated brightness change on a synced display. Sets the cooldown stamp and
    /// the hysteresis anchor (so post-cooldown resumption doesn't immediately re-write). When a
    /// live reference level exists (the built-in's brightness in sync mode, or the ambient-light
    /// curve level in sensor mode) the change *teaches the offset* relative to it; with no
    /// reference (schedule mode) it records the adoption anchor instead — see
    /// `DisplayState.manualScheduleAnchor`.
    public static func noteManualBrightness(_ value: Float, reference: Float?,
                                            scheduleTarget: Float, at now: Date,
                                            state: DisplayState) -> DisplayState {
        var state = state
        state.manualBrightnessAt = now
        state.lastWrittenBrightness = value
        if let reference {
            state.brightnessOffset = min(1, max(-1, value - reference))
        } else {
            state.manualScheduleAnchor = scheduleTarget
        }
        return state
    }

    /// Record a user-initiated colour-preset change: adopt it for the rest of the current warmth
    /// phase (the configured evening preset is untouched — a one-night adoption).
    public static func noteManualPreset(state: DisplayState) -> DisplayState {
        var state = state
        state.presetOverridden = true
        return state
    }

    // MARK: - Tick evaluation

    public static func evaluate(_ input: Input, config: AdaptiveDisplayConfig,
                                state: DisplayState) -> Decision {
        var state = state
        guard !input.displayAsleep else { return Decision(state: state) }

        var brightnessWrite: Float?
        if input.brightnessSyncEnabled {
            brightnessWrite = brightnessDecision(input, config: config, state: &state)
        }

        var presetWrite: Int?
        var rememberDayPreset: Int?
        var clearDayPreset = false
        if input.warmthEnabled, let currentPreset = input.currentPreset {
            let isEvening = input.nightShiftActive ?? scheduleIsNight(atMinute: input.minuteOfDay,
                                                                      config: config)
            // Drift detection: some other hand (monitor buttons, another app) changed the preset
            // mid-evening — adopt it exactly like an in-app manual change.
            if state.warmthPhase == .evening, !state.presetOverridden,
               currentPreset != config.eveningPreset, isEvening {
                state.presetOverridden = true
            }
            if isEvening, state.warmthPhase == .day {
                state.warmthPhase = .evening
                state.presetOverridden = false
                if currentPreset != config.eveningPreset {
                    // Remember day ONLY when nothing is owed: after a relaunch mid-evening the
                    // owed memory is the true day preset — re-capturing would save the warm one.
                    if input.dayPreset == nil { rememberDayPreset = currentPreset }
                    presetWrite = config.eveningPreset
                }
            } else if !isEvening {
                if state.warmthPhase == .evening {
                    state.warmthPhase = .day
                    state.presetOverridden = false
                }
                // One rule covers the morning transition, crash-recovery at a daytime launch, and
                // re-enable during day: any owed day preset gets restored and the memory cleared.
                if let owed = input.dayPreset {
                    if currentPreset != owed { presetWrite = owed }
                    clearDayPreset = true
                }
            }
        }

        return Decision(brightnessWrite: brightnessWrite, presetWrite: presetWrite,
                        rememberDayPreset: rememberDayPreset, clearDayPreset: clearDayPreset,
                        state: state)
    }

    private static func brightnessDecision(_ input: Input, config: AdaptiveDisplayConfig,
                                           state: inout DisplayState) -> Float? {
        // Cooldown: the user just adjusted this display — stay hands-off.
        if let manualAt = state.manualBrightnessAt,
           input.now < manualAt.addingTimeInterval(config.manualCooldown) {
            return nil
        }
        let target: Float
        if input.builtInPresent {
            // Sync mode. A nil sample is a transient read failure: skip the tick — NEVER treat it
            // as built-in-gone (that would yank brightness to a fallback level on a hiccup).
            guard let builtIn = input.builtInBrightness else { return nil }
            target = min(1, max(0, builtIn + state.brightnessOffset))
            state.manualScheduleAnchor = nil  // anchor is a schedule-mode concept
        } else if let lux = input.ambientLux {
            // Ambient mode: built-in off but the lid is open, so the light sensor still sees the
            // room — follow it directly. Same offset-learning contract as sync mode.
            target = min(1, max(0, ambientLevel(forLux: lux) + state.brightnessOffset))
            state.manualScheduleAnchor = nil
        } else {
            target = scheduleLevel(atMinute: input.minuteOfDay, config: config)
            // Schedule-mode adoption: hold the user's manual level until the schedule target
            // itself moves past hysteresis from where it was when they set it.
            if let anchor = state.manualScheduleAnchor {
                if abs(target - anchor) < config.hysteresis { return nil }
                state.manualScheduleAnchor = nil
            }
        }
        if let last = state.lastWrittenBrightness, abs(target - last) < config.hysteresis {
            return nil
        }
        state.lastWrittenBrightness = target
        return target
    }
}
