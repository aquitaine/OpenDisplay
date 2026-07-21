import Foundation

/// What a schedule entry is pinned to. `.time` uses a fixed minute-of-day; the solar anchors are
/// resolved per day from `SolarEvents`, so "sunset" tracks the season automatically.
public enum ScheduleAnchor: String, Hashable, Sendable, Codable, CaseIterable {
    case time, sunrise, solarNoon, sunset
}

/// How brightness moves toward an entry's level as its anchor approaches.
public enum ScheduleTransition: String, Hashable, Sendable, Codable, CaseIterable {
    /// Step to the new level exactly at the anchor.
    case instant
    /// Linear ramp of `rampMinutes` (default 30) finishing at the anchor.
    case ramp
    /// Linear glide from the previous entry spread across the whole gap before this anchor.
    case continuous
}

/// One user-authored point in a Clock Mode schedule: "brightness `brightness` at `anchor` (± offset),
/// reached via `transition`". For example 70% thirty minutes before sunrise is
/// `anchor: .sunrise, offsetMinutes: -30, brightness: 0.7, transition: .ramp`.
public struct ClockScheduleEntry: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var anchor: ScheduleAnchor
    /// Minute-of-day for a `.time` anchor; ignored for solar anchors.
    public var timeMinute: Int
    /// Minutes added to the anchor moment. Negative means "before" (−30 = thirty minutes before).
    public var offsetMinutes: Int
    /// Target hardware brightness, 0...1.
    public var brightness: Float
    public var transition: ScheduleTransition

    public init(id: UUID = UUID(), anchor: ScheduleAnchor, timeMinute: Int = 0,
                offsetMinutes: Int = 0, brightness: Float, transition: ScheduleTransition = .ramp) {
        self.id = id
        self.anchor = anchor
        self.timeMinute = timeMinute
        self.offsetMinutes = offsetMinutes
        self.brightness = brightness
        self.transition = transition
    }
}

/// Pure Clock Mode engine: resolve a set of user entries to the brightness owed at a given
/// minute-of-day. Deterministic and clock-free — the caller supplies the minute and the day's solar
/// events — so it is exercised by `make test` like the other TopologyCore policies. All hysteresis,
/// cooldown, and hardware writes belong to the caller (which routes this target through
/// `AdaptiveDisplayPolicy` so the write is silent and never fights a manual change).
public enum ClockSchedulePolicy {
    /// Ramp width for `.ramp` transitions (the Lunar-parity "30-minute transition").
    public static let defaultRampMinutes = 30

    private static let minutesPerDay = 1440

    /// A schedule entry resolved to an absolute local minute-of-day for one day's solar events.
    private struct ResolvedKeyframe {
        var minute: Int
        var brightness: Float
        var transition: ScheduleTransition
    }

    /// The scheduled brightness (0...1) at `minuteOfDay`, or nil when the schedule cannot govern this
    /// moment: no entries at all, or only solar-anchored entries whose anchors are unavailable (no
    /// location supplied, or polar day/night). Wrap-aware across midnight.
    public static func brightness(atMinute minuteOfDay: Int, entries: [ClockScheduleEntry],
                                  solar: SolarEvents?,
                                  rampMinutes: Int = defaultRampMinutes) -> Float? {
        let keyframes = resolvedKeyframes(entries: entries, solar: solar)
        guard let first = keyframes.first else { return nil }
        guard keyframes.count > 1 else { return first.brightness }

        let upcomingIndex = keyframes.firstIndex { $0.minute > minuteOfDay } ?? 0
        let upcoming = keyframes[upcomingIndex]
        let previous = keyframes[(upcomingIndex - 1 + keyframes.count) % keyframes.count]
        let gap = positiveGap(from: previous.minute, to: upcoming.minute)
        let elapsed = wrappedMinute(minuteOfDay - previous.minute)
        return transitionValue(elapsed: elapsed, gap: gap, from: previous.brightness,
                               to: upcoming.brightness, transition: upcoming.transition,
                               rampMinutes: rampMinutes)
    }

    /// The absolute local minute-of-day an entry fires on, or nil when its solar anchor is
    /// unavailable for the day.
    public static func resolvedMinute(for entry: ClockScheduleEntry, solar: SolarEvents?) -> Int? {
        let anchorMinute: Int?
        switch entry.anchor {
        case .time: anchorMinute = entry.timeMinute
        case .sunrise: anchorMinute = solar?.sunriseMinute
        case .solarNoon: anchorMinute = solar?.solarNoonMinute
        case .sunset: anchorMinute = solar?.sunsetMinute
        }
        guard let anchorMinute else { return nil }
        return wrappedMinute(anchorMinute + entry.offsetMinutes)
    }

    private static func resolvedKeyframes(entries: [ClockScheduleEntry],
                                          solar: SolarEvents?) -> [ResolvedKeyframe] {
        entries
            .compactMap { entry -> ResolvedKeyframe? in
                guard let minute = resolvedMinute(for: entry, solar: solar) else { return nil }
                return ResolvedKeyframe(minute: minute, brightness: entry.brightness,
                                        transition: entry.transition)
            }
            .sorted { $0.minute < $1.minute }
    }

    private static func transitionValue(elapsed: Int, gap: Int, from: Float, to: Float,
                                        transition: ScheduleTransition,
                                        rampMinutes: Int) -> Float {
        switch transition {
        case .instant:
            return from
        case .continuous:
            return interpolate(from: from, to: to, fraction: Float(elapsed) / Float(gap))
        case .ramp:
            let width = min(max(1, rampMinutes), gap)
            let rampStart = gap - width
            guard elapsed > rampStart else { return from }
            return interpolate(from: from, to: to, fraction: Float(elapsed - rampStart) / Float(width))
        }
    }

    private static func interpolate(from: Float, to: Float, fraction: Float) -> Float {
        from + (to - from) * min(1, max(0, fraction))
    }

    /// Minutes between two anchors going forward on the clock; a coincident pair spans the full day.
    private static func positiveGap(from start: Int, to end: Int) -> Int {
        let forward = wrappedMinute(end - start)
        return forward == 0 ? minutesPerDay : forward
    }

    private static func wrappedMinute(_ minute: Int) -> Int {
        ((minute % minutesPerDay) + minutesPerDay) % minutesPerDay
    }
}
