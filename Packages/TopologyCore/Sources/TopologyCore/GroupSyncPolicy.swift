import DisplayDomain
import Foundation

/// Pure decision core for Display Groups — the "move one member's brightness and the rest follow"
/// feature. Deterministic and clock-free in the same shape as `AdaptiveDisplayPolicy` and
/// `AppPresetPolicy`: the caller injects `now`, threads a caller-owned `GroupSyncState` and
/// `SyncEcho` through, and receives the writes to issue. Every hardware write, OSD, and persistence
/// decision belongs to `AppModel`.
///
/// Two rules carry the feature. **Any member leads**: a user's slider move (or media key) on any
/// present member fans out to the others at `leader + learned offset`. **A correction teaches**: a
/// move on a *different* member shortly after a fan-out is read as the user fixing what sync just
/// did, so the group re-learns that member's offset instead of fanning the correction back out —
/// which is what stops two sliders from chasing each other. ::
///
///     classify(0.60 on builtIn, group {builtIn, desk}, offset[desk] = +0.10)
///     ok: .leader — desk written at 0.70, builtIn is now the leader at 0.60
///
///     classify(0.80 on desk, 4s later)                    // user nudges the follower
///     ok: .followerCorrection(offset: +0.20) — nothing written, desk's offset re-learned
///
///     classify(0.80 on desk, 5 minutes later)             // a fresh interaction, not a fix
///     flag: .leader — desk now leads and builtIn follows
///
/// Precedence: group sync sits BELOW FaceLight and App Presets (a governed display is skipped
/// exactly like `adaptiveTick` skips one) and is mutually exclusive with Adaptive Display — a
/// grouped display is excluded from adaptive targeting by the caller.
public enum GroupSyncPolicy {

    // MARK: - Echo suppression

    /// The loop-killer. Every write OpenDisplay issues on the group's behalf is tagged with a token,
    /// and a tagged write is never read as a leader event — otherwise fanning a leader's value out
    /// to its followers would re-enter the funnel as three more leader events and the group would
    /// oscillate forever.
    ///
    /// A token is live only between `begin` and `end`, so a stale token (replayed after its fan-out
    /// finished) does NOT suppress a genuine user move. The in-flight follower set covers the other
    /// direction: a cache-driven UI binding echoing a follower's new value back into the funnel
    /// during the same fan-out is recognised by display, with no token to carry. ::
    ///
    ///     token = begin(leader: builtIn, followers: [desk])
    ///     ok:   isEcho(display: desk, token: token) — our own write, ignored as a leader
    ///     ok:   isEcho(display: desk, token: nil)   — cache echo during the fan-out, ignored
    ///     end(token)
    ///     flag: isEcho(display: desk, token: token) — fan-out is over; the user's hand leads again
    public struct SyncEcho: Hashable, Sendable {
        /// Marks one fan-out. Opaque on purpose: only `SyncEcho` can tell a live token from a spent
        /// one, so a caller cannot forge suppression.
        public struct Token: Hashable, Sendable {
            fileprivate let sequence: UInt64
            public let leader: DisplayRecordID
        }

        private var nextSequence: UInt64 = 1
        private var followersBySequence: [UInt64: Set<DisplayRecordID>] = [:]

        public init() {}

        /// Opens a fan-out: the returned token tags every write the caller is about to issue, and
        /// `followers` are suppressed by display for the duration.
        public mutating func begin(leader: DisplayRecordID,
                                   followers: [DisplayRecordID] = []) -> Token {
            let sequence = nextSequence
            nextSequence += 1
            followersBySequence[sequence] = Set(followers)
            return Token(sequence: sequence, leader: leader)
        }

        /// Whether this write is one of ours rather than the user's hand.
        public func isEcho(display: DisplayRecordID, token: Token?) -> Bool {
            if let token, followersBySequence[token.sequence] != nil { return true }
            return followersBySequence.values.contains { $0.contains(display) }
        }

        public mutating func end(_ token: Token) {
            followersBySequence[token.sequence] = nil
        }

        /// Whether any fan-out is still open (test/diagnostic affordance — a balanced
        /// begin/end pair must leave this false).
        public var hasOpenFanOut: Bool { !followersBySequence.isEmpty }
    }

    // MARK: - Value types

    /// One follower's owed write. Brightness fan-outs carry `leader + offset`; contrast fan-outs
    /// carry the leader's value unchanged (a flat mirror — see `contrastFanOut`).
    public struct FollowerWrite: Hashable, Sendable {
        public var member: DisplayRecordID
        public var value: Float

        public init(member: DisplayRecordID, value: Float) {
            self.member = member
            self.value = value
        }
    }

    /// What one leader event owes the rest of the group. The three skip lists are reported rather
    /// than silently dropped so the caller can log them; none of them is an error.
    public struct FanOut: Hashable, Sendable {
        public var writes: [FollowerWrite]
        /// Members that aren't currently present (unplugged, turned off) — skipped silently.
        public var absent: [DisplayRecordID]
        /// Members a higher-precedence writer owns right now (FaceLight, an app preset).
        public var governed: [DisplayRecordID]
        /// Members whose panel has no such control (contrast only; always empty for brightness).
        public var unsupported: [DisplayRecordID]

        public init(writes: [FollowerWrite] = [], absent: [DisplayRecordID] = [],
                    governed: [DisplayRecordID] = [], unsupported: [DisplayRecordID] = []) {
            self.writes = writes
            self.absent = absent
            self.governed = governed
            self.unsupported = unsupported
        }

        public var isEmpty: Bool { writes.isEmpty }
    }

    /// The observed world for one write, assembled by the caller.
    public struct World: Hashable, Sendable {
        /// Displays that exist and are usable right now.
        public var present: Set<DisplayRecordID>
        /// Displays a higher-precedence feature currently owns (FaceLight active, app preset applied).
        public var governed: Set<DisplayRecordID>
        /// Displays whose DDC probe found a working contrast channel.
        public var contrastCapable: Set<DisplayRecordID>

        public init(present: Set<DisplayRecordID> = [], governed: Set<DisplayRecordID> = [],
                    contrastCapable: Set<DisplayRecordID> = []) {
            self.present = present
            self.governed = governed
            self.contrastCapable = contrastCapable
        }
    }

    /// Caller-owned per-group evolution state. `leaderValue` is the group's current base level: the
    /// value a follower's offset is measured against, and the anchor a correction re-learns from.
    public struct GroupSyncState: Hashable, Sendable {
        public var leaderRecordID: DisplayRecordID?
        public var leaderValue: Float?
        public var lastFanOutAt: Date?

        public init(leaderRecordID: DisplayRecordID? = nil, leaderValue: Float? = nil,
                    lastFanOutAt: Date? = nil) {
            self.leaderRecordID = leaderRecordID
            self.leaderValue = leaderValue
            self.lastFanOutAt = lastFanOutAt
        }
    }

    /// One user-originated write arriving at the funnel. `token` is non-nil only when OpenDisplay
    /// itself issued the write (a sync fan-out, a FaceLight restore) — see `SyncEcho`.
    public struct ManualWrite: Hashable, Sendable {
        public var value: Float
        public var display: DisplayRecordID
        public var token: SyncEcho.Token?
        public var now: Date
        public var world: World
        public var correctionWindow: TimeInterval

        public init(value: Float, display: DisplayRecordID, token: SyncEcho.Token? = nil,
                    now: Date, world: World,
                    correctionWindow: TimeInterval = GroupSyncPolicy.defaultCorrectionWindow) {
            self.value = value
            self.display = display
            self.token = token
            self.now = now
            self.world = world
            self.correctionWindow = correctionWindow
        }
    }

    /// What a write meant for the group.
    public enum Outcome: Hashable, Sendable {
        /// Our own fan-out coming back around — do nothing at all.
        case echo
        /// A higher-precedence writer owns this display right now (FaceLight, an app preset).
        case governed
        /// The group exists but isn't syncing brightness.
        case syncDisabled
        /// A fresh interaction: this display leads and the rest follow.
        case leader(FanOut)
        /// The user corrected what sync just wrote — the offset is re-learned, nothing is written.
        case followerCorrection(offset: Float)
    }

    /// The classification plus the group and state the caller should store. `group` differs from the
    /// input only on a `followerCorrection` (the re-learned offset); `state` advances on a leader
    /// event and on a correction (which keeps the correction window open for the next nudge).
    public struct ManualWriteResult: Hashable, Sendable {
        public var outcome: Outcome
        public var group: DisplayGroup
        public var state: GroupSyncState

        public init(outcome: Outcome, group: DisplayGroup, state: GroupSyncState) {
            self.outcome = outcome
            self.group = group
            self.state = state
        }
    }

    /// How long after a fan-out a move on another member still reads as a correction rather than a
    /// fresh leader event. Long enough to look at the monitor and drag its slider, short enough that
    /// walking up later and reaching for any display still moves the whole group — which is the
    /// promise of "any member drives all".
    public static let defaultCorrectionWindow: TimeInterval = 30

    // MARK: - Brightness

    /// The writes a leader's brightness owes the rest of the group: `clamp01(value + offset)` per
    /// follower, the leader excluded, absent and governed members reported rather than written.
    public static func followerWrites(leader: DisplayRecordID, value: Float,
                                      group: DisplayGroup, world: World) -> FanOut {
        groupWrites(value, group: group, world: world, excluding: leader)
    }

    /// Every member's write when the GROUP ITSELF is the target — the `group:<name>` CLI selector,
    /// where no display was touched and `value` is simply the group's new base level. Same offset,
    /// clamp, and skip rules as a leader fan-out; nothing is excluded unless the caller names it.
    public static func groupWrites(_ value: Float, group: DisplayGroup, world: World,
                                   excluding leader: DisplayRecordID? = nil) -> FanOut {
        var fanOut = FanOut()
        for member in group.memberRecordIDs where member != leader {
            guard world.present.contains(member) else { fanOut.absent.append(member); continue }
            guard !world.governed.contains(member) else { fanOut.governed.append(member); continue }
            fanOut.writes.append(FollowerWrite(member: member,
                                               value: clamp01(value + group.offset(for: member))))
        }
        return fanOut
    }

    /// Classify one brightness write on a grouped display. The caller resolves the group first
    /// (`DisplayGroupStore.group(containing:in:)`) — an ungrouped display never reaches here.
    public static func classify(_ write: ManualWrite, group: DisplayGroup,
                                state: GroupSyncState, echo: SyncEcho) -> ManualWriteResult {
        guard !echo.isEcho(display: write.display, token: write.token) else {
            return ManualWriteResult(outcome: .echo, group: group, state: state)
        }
        guard group.syncBrightness else {
            return ManualWriteResult(outcome: .syncDisabled, group: group, state: state)
        }
        guard !write.world.governed.contains(write.display) else {
            return ManualWriteResult(outcome: .governed, group: group, state: state)
        }
        if let correction = correctionOffset(write, group: group, state: state) {
            var corrected = group
            corrected.setOffset(correction, for: write.display)
            var advanced = state
            advanced.lastFanOutAt = write.now  // a slow multi-nudge stays one correction
            return ManualWriteResult(outcome: .followerCorrection(offset: corrected.offset(for: write.display)),
                                     group: corrected, state: advanced)
        }
        let fanOut = followerWrites(leader: write.display, value: write.value, group: group,
                                    world: write.world)
        let led = GroupSyncState(leaderRecordID: write.display, leaderValue: write.value,
                                 lastFanOutAt: write.now)
        return ManualWriteResult(outcome: .leader(fanOut), group: group, state: led)
    }

    /// The offset this write teaches, or nil when it is a leader event instead. A correction is a
    /// move on a member other than the current leader, inside the correction window, while that
    /// leader is still part of the group.
    private static func correctionOffset(_ write: ManualWrite, group: DisplayGroup,
                                         state: GroupSyncState) -> Float? {
        guard let leader = state.leaderRecordID, let leaderValue = state.leaderValue,
              let lastFanOutAt = state.lastFanOutAt,
              leader != write.display, group.contains(leader),
              write.now.timeIntervalSince(lastFanOutAt) < write.correctionWindow else { return nil }
        return write.value - leaderValue
    }

    // MARK: - Contrast

    /// Contrast sync is a flat mirror: every present, ungoverned, contrast-capable follower gets the
    /// leader's value verbatim. No offset is learned — contrast has no per-panel calibration story
    /// the way backlight does, and a learned contrast offset would just encode one panel's factory
    /// curve as if it were the user's preference.
    public static func contrastFanOut(_ write: ManualWrite, group: DisplayGroup,
                                      echo: SyncEcho) -> FanOut {
        guard group.syncContrast,
              !echo.isEcho(display: write.display, token: write.token),
              !write.world.governed.contains(write.display) else { return FanOut() }
        var fanOut = FanOut()
        for member in group.memberRecordIDs where member != write.display {
            guard write.world.present.contains(member) else { fanOut.absent.append(member); continue }
            guard !write.world.governed.contains(member) else { fanOut.governed.append(member); continue }
            guard write.world.contrastCapable.contains(member) else {
                fanOut.unsupported.append(member)
                continue
            }
            fanOut.writes.append(FollowerWrite(member: member, value: clamp01(write.value)))
        }
        return fanOut
    }

    private static func clamp01(_ value: Float) -> Float {
        min(1, max(0, value))
    }
}
