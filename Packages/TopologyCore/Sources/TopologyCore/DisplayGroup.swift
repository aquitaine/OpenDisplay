import DisplayDomain
import Foundation

/// A user-defined set of displays whose brightness (and optionally contrast) moves together — the
/// "groups, sync" half of PRD §5.3's controls line. Distinct from Adaptive Display's built-in →
/// external mirror: the members are chosen by hand, any member drives the rest, and the group keeps
/// working with the built-in panel turned off.
///
/// `offsetByMember` is what keeps two mismatched panels usable together: a follower is written at
/// `leader + offset`, and the offset is *learned* from the user's own correction rather than
/// configured up front (see `GroupSyncPolicy.classify`, outcome `.followerCorrection`). Keys are
/// `DisplayRecordID.rawValue` — raw-representable dictionary keys encode as flat arrays in JSON, the
/// same reason `adaptiveBrightnessOffsetByDisplay` is String-keyed.
public struct DisplayGroup: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var memberRecordIDs: [DisplayRecordID]
    public var syncBrightness: Bool
    public var syncContrast: Bool
    public var offsetByMember: [String: Float]

    public init(id: UUID = UUID(), name: String, memberRecordIDs: [DisplayRecordID] = [],
                syncBrightness: Bool = true, syncContrast: Bool = false,
                offsetByMember: [String: Float] = [:]) {
        self.id = id
        self.name = name
        self.memberRecordIDs = memberRecordIDs
        self.syncBrightness = syncBrightness
        self.syncContrast = syncContrast
        self.offsetByMember = offsetByMember
    }

    /// Widest offset the policy will learn or apply, mirroring `AdaptiveDisplayPolicy`'s own
    /// ±1 clamp on a learned offset. A tighter bound would silently discard part of a correction the
    /// user actually made and re-impose the clipped value on the next fan-out — the slider war the
    /// learning exists to prevent.
    public static let offsetLimit: Float = 1

    /// The range the settings ± slider spans by default. Real panels sit well inside it; a learned
    /// offset beyond it stays legal (see `offsetLimit`) and the slider widens to show it.
    public static let nominalOffsetLimit: Float = 0.5

    public func contains(_ member: DisplayRecordID) -> Bool {
        memberRecordIDs.contains(member)
    }

    /// This member's learned brightness offset relative to the group's leader (0 when nothing has
    /// been learned yet, which is the right answer for a fresh member).
    public func offset(for member: DisplayRecordID) -> Float {
        offsetByMember[member.rawValue] ?? 0
    }

    public mutating func setOffset(_ offset: Float, for member: DisplayRecordID) {
        offsetByMember[member.rawValue] = Self.clampOffset(offset)
    }

    public static func clampOffset(_ offset: Float) -> Float {
        min(offsetLimit, max(-offsetLimit, offset))
    }
}

/// Pure store logic for the configured groups (`OpenDisplaySettings.displayGroups`). Every mutation
/// is a value-in / value-out transform so the app layer only has to persist the result.
///
/// The one invariant worth naming: **a display belongs to at most one group**. Two groups claiming
/// the same display would each fan a leader write out to it, and the display would end up wherever
/// the later write happened to land. Adding a display to a second group therefore removes it from
/// the first rather than failing. ::
///
///     addMember(desk, to: gaming, in: [work(desk, laptop), gaming()])
///     ok: [work(laptop), gaming(desk)]   — desk left `work` on the way in
public enum DisplayGroupStore {
    /// The group a display belongs to, or nil when it is ungrouped.
    public static func group(containing member: DisplayRecordID,
                             in groups: [DisplayGroup]) -> DisplayGroup? {
        groups.first { $0.contains(member) }
    }

    /// Case-insensitive name lookup — what the `group:<name>` CLI selector resolves through.
    public static func group(named name: String, in groups: [DisplayGroup]) -> DisplayGroup? {
        groups.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Appends a new group, or nil when the name is already taken (names are the CLI's handle on a
    /// group, so two groups sharing one would make `group:desk` ambiguous).
    public static func create(named name: String, in groups: [DisplayGroup],
                              id: UUID = UUID()) -> [DisplayGroup]? {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, group(named: cleaned, in: groups) == nil else { return nil }
        return groups + [DisplayGroup(id: id, name: cleaned)]
    }

    public static func delete(id: UUID, from groups: [DisplayGroup]) -> [DisplayGroup] {
        groups.filter { $0.id != id }
    }

    /// Replaces the stored group with the same id, re-applying the one-group-per-display invariant
    /// against the members it now claims. Unknown ids are ignored.
    public static func update(_ group: DisplayGroup, in groups: [DisplayGroup]) -> [DisplayGroup] {
        guard groups.contains(where: { $0.id == group.id }) else { return groups }
        return groups.map { existing in
            guard existing.id != group.id else { return group }
            return withoutMembers(group.memberRecordIDs, from: existing)
        }
    }

    /// Adds a display to a group, removing it from whichever group held it before.
    public static func addMember(_ member: DisplayRecordID, to groupID: UUID,
                                 in groups: [DisplayGroup]) -> [DisplayGroup] {
        groups.map { existing in
            guard existing.id == groupID else { return withoutMembers([member], from: existing) }
            guard !existing.contains(member) else { return existing }
            var claimed = existing
            claimed.memberRecordIDs.append(member)
            return claimed
        }
    }

    /// Drops a display from a group, forgetting the offset learned for it there — a member that
    /// rejoins later is a fresh relationship, not a resumption of the old one.
    public static func removeMember(_ member: DisplayRecordID, from groupID: UUID,
                                    in groups: [DisplayGroup]) -> [DisplayGroup] {
        groups.map { existing in
            guard existing.id == groupID else { return existing }
            return withoutMembers([member], from: existing)
        }
    }

    /// True when this display's brightness is driven by a group, so the caller (`adaptiveTick`) can
    /// leave it alone: Adaptive Display and group sync are mutually exclusive per display.
    public static func isGroupGoverned(_ member: DisplayRecordID, in groups: [DisplayGroup]) -> Bool {
        group(containing: member, in: groups)?.syncBrightness ?? false
    }

    private static func withoutMembers(_ members: [DisplayRecordID],
                                       from group: DisplayGroup) -> DisplayGroup {
        let leaving = Set(members)
        guard group.memberRecordIDs.contains(where: leaving.contains) else { return group }
        var trimmed = group
        trimmed.memberRecordIDs.removeAll(where: leaving.contains)
        for member in leaving { trimmed.offsetByMember[member.rawValue] = nil }
        return trimmed
    }
}
