import Foundation

/// The resolutions a user has pinned ("favourited") per display, so they surface first and can be
/// recalled quickly. Pure value logic in the cross-platform core (exercised by `make test`); the disk
/// store and UI live elsewhere. Favourites are keyed by **stable display identity**
/// (`DisplayRecordID`), so they survive reconnects, and by mode (point-size + refresh + HiDPI), so they
/// survive the display's mode list changing.
public struct FavoriteResolutions: Hashable, Sendable, Codable {
    /// Per-display favourite mode keys, **newest first**.
    private var byDisplay: [String: [String]]

    public init(byDisplay: [String: [String]] = [:]) { self.byDisplay = byDisplay }

    /// A stable key for a mode: point size + integer refresh + HiDPI marker.
    public static func key(for mode: DisplayMode) -> String {
        "\(mode.pointWidth)x\(mode.pointHeight)@\(Int(mode.refreshHz.rounded()))" + (mode.isHiDPI ? "@2x" : "")
    }

    public func isFavorite(_ mode: DisplayMode, for display: DisplayRecordID) -> Bool {
        (byDisplay[display.rawValue] ?? []).contains(Self.key(for: mode))
    }

    public func favoriteKeys(for display: DisplayRecordID) -> [String] {
        byDisplay[display.rawValue] ?? []
    }

    /// Adds the mode as a favourite if absent (newest first), removes it if already present.
    public mutating func toggle(_ mode: DisplayMode, for display: DisplayRecordID) {
        let k = Self.key(for: mode)
        var list = byDisplay[display.rawValue] ?? []
        if let i = list.firstIndex(of: k) { list.remove(at: i) } else { list.insert(k, at: 0) }
        byDisplay[display.rawValue] = list.isEmpty ? nil : list
    }

    public mutating func add(_ mode: DisplayMode, for display: DisplayRecordID) {
        guard !isFavorite(mode, for: display) else { return }
        toggle(mode, for: display)
    }

    public mutating func remove(_ mode: DisplayMode, for display: DisplayRecordID) {
        guard isFavorite(mode, for: display) else { return }
        toggle(mode, for: display)
    }

    /// Favourites (newest first, resolved against `stops` so stale ones drop out) followed by the
    /// remaining area-sorted stops — deduped. The single list a resolution control steps through.
    public func merged(stops: [DisplayMode], for display: DisplayRecordID) -> [DisplayMode] {
        let favKeys = byDisplay[display.rawValue] ?? []
        var result: [DisplayMode] = []
        var used: Set<String> = []
        for k in favKeys {
            if !used.contains(k), let mode = stops.first(where: { Self.key(for: $0) == k }) {
                result.append(mode); used.insert(k)
            }
        }
        for mode in stops where !used.contains(Self.key(for: mode)) { result.append(mode) }
        return result
    }
}
