import Foundation

/// Derives the monotonic, area-sorted list of resolution "stops" the resolution slider steps through,
/// and maps a display's current mode back to its stop index. One stop per point-size (HiDPI preferred,
/// then highest refresh), area-ascending with deterministic tie-breakers so the stops never reorder
/// and the slider's index discipline stays stable. Pure value logic shared by the slider UI and
/// exercised directly by `make test`.
public enum ResolutionStops {
    /// One representative `DisplayMode` per point-size, ascending by pixel area (then width, then
    /// height, so equal-area sizes still order deterministically). For each point-size the
    /// representative is the HiDPI variant when present, otherwise the highest refresh rate.
    public static func areaSorted(from modes: [DisplayMode]) -> [DisplayMode] {
        var best: [PointSize: DisplayMode] = [:]
        for mode in modes {
            let key = PointSize(width: mode.pointWidth, height: mode.pointHeight)
            if let existing = best[key] {
                if rank(mode) > rank(existing) { best[key] = mode }
            } else {
                best[key] = mode
            }
        }
        return best.values.sorted { lhs, rhs in
            (lhs.pointWidth * lhs.pointHeight, lhs.pointWidth, lhs.pointHeight)
                < (rhs.pointWidth * rhs.pointHeight, rhs.pointWidth, rhs.pointHeight)
        }
    }

    /// The index of `mode`'s point-size within `stops`, or nil if absent. Matches on point-size only,
    /// so it stays correct regardless of the current refresh-rate or HiDPI variant.
    public static func index(of mode: DisplayMode, in stops: [DisplayMode]) -> Int? {
        stops.firstIndex { $0.pointWidth == mode.pointWidth && $0.pointHeight == mode.pointHeight }
    }

    /// Ranking used to pick the representative mode for a point-size: HiDPI wins, then higher refresh.
    private static func rank(_ mode: DisplayMode) -> (Int, Double) {
        (mode.isHiDPI ? 1 : 0, mode.refreshHz)
    }

    private struct PointSize: Hashable { let width: Int; let height: Int }
}
