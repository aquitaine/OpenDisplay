import DisplayDomain
import XCTest
@testable import TopologyCore

final class GroupSyncPolicyTests: XCTestCase {
    private typealias Policy = GroupSyncPolicy

    private let epoch = Date(timeIntervalSinceReferenceDate: 0)
    private let builtIn = DisplayRecordID(rawValue: "cgid:1")
    private let desk = DisplayRecordID(rawValue: "cgid:2")
    private let side = DisplayRecordID(rawValue: "cgid:3")

    private func group(offsets: [DisplayRecordID: Float] = [:], syncBrightness: Bool = true,
                       syncContrast: Bool = false,
                       members: [DisplayRecordID]? = nil) -> DisplayGroup {
        var made = DisplayGroup(name: "Desk", memberRecordIDs: members ?? [builtIn, desk, side],
                                syncBrightness: syncBrightness, syncContrast: syncContrast)
        for (member, offset) in offsets { made.setOffset(offset, for: member) }
        return made
    }

    private func world(present: [DisplayRecordID]? = nil, governed: [DisplayRecordID] = [],
                       contrastCapable: [DisplayRecordID]? = nil) -> Policy.World {
        let live = present ?? [builtIn, desk, side]
        return Policy.World(present: Set(live), governed: Set(governed),
                            contrastCapable: Set(contrastCapable ?? live))
    }

    private func write(_ value: Float, on display: DisplayRecordID,
                       token: Policy.SyncEcho.Token? = nil, at now: Date? = nil,
                       world: Policy.World? = nil) -> Policy.ManualWrite {
        Policy.ManualWrite(value: value, display: display, token: token, now: now ?? epoch,
                           world: world ?? self.world())
    }

    /// The fan-out a leader event produced, or a failure when the outcome was something else.
    private func fanOut(of result: Policy.ManualWriteResult,
                        file: StaticString = #filePath, line: UInt = #line) -> Policy.FanOut {
        guard case .leader(let fanOut) = result.outcome else {
            XCTFail("expected a leader event, got \(result.outcome)", file: file, line: line)
            return Policy.FanOut()
        }
        return fanOut
    }

    private func values(_ fanOut: Policy.FanOut) -> [DisplayRecordID: Float] {
        Dictionary(uniqueKeysWithValues: fanOut.writes.map { ($0.member, $0.value) })
    }

    /// The offset a correction taught, or a failure when the outcome was something else. Float
    /// arithmetic makes the enum itself a poor comparison target (0.8 − 0.6 is not exactly 0.2), so
    /// every offset assertion goes through here and compares with an accuracy.
    private func learnedOffset(of result: Policy.ManualWriteResult,
                               file: StaticString = #filePath, line: UInt = #line) -> Float {
        guard case .followerCorrection(let offset) = result.outcome else {
            XCTFail("expected a follower correction, got \(result.outcome)", file: file, line: line)
            return .nan
        }
        return offset
    }

    /// Asserts a fan-out wrote exactly these members, each within Float tolerance of its value.
    private func assertWrites(_ fanOut: Policy.FanOut, _ expected: [DisplayRecordID: Float],
                              file: StaticString = #filePath, line: UInt = #line) {
        let written = values(fanOut)
        XCTAssertEqual(Set(written.keys), Set(expected.keys), file: file, line: line)
        for (member, value) in expected {
            XCTAssertEqual(written[member] ?? .nan, value, accuracy: 0.0001, file: file, line: line)
        }
    }

    // MARK: - Fan-out with offsets

    func testLeaderFansOutToEveryOtherMember() {
        let result = Policy.classify(write(0.6, on: builtIn), group: group(),
                                     state: Policy.GroupSyncState(), echo: Policy.SyncEcho())
        assertWrites(fanOut(of: result), [desk: 0.6, side: 0.6])
    }

    func testTheLeaderIsNeverWrittenByItsOwnFanOut() {
        let result = Policy.classify(write(0.6, on: builtIn), group: group(),
                                     state: Policy.GroupSyncState(), echo: Policy.SyncEcho())
        XCTAssertFalse(fanOut(of: result).writes.contains { $0.member == builtIn })
    }

    func testEachFollowerGetsItsOwnLearnedOffset() {
        let result = Policy.classify(write(0.5, on: builtIn),
                                     group: group(offsets: [desk: 0.15, side: -0.2]),
                                     state: Policy.GroupSyncState(), echo: Policy.SyncEcho())
        assertWrites(fanOut(of: result), [desk: 0.65, side: 0.3])
    }

    func testFollowerValuesClampToTheTopOfTheRange() {
        let result = Policy.classify(write(0.95, on: builtIn), group: group(offsets: [desk: 0.4]),
                                     state: Policy.GroupSyncState(), echo: Policy.SyncEcho())
        assertWrites(fanOut(of: result), [desk: 1.0, side: 0.95])
    }

    func testFollowerValuesClampToTheBottomOfTheRange() {
        let result = Policy.classify(write(0.05, on: builtIn), group: group(offsets: [desk: -0.4]),
                                     state: Policy.GroupSyncState(), echo: Policy.SyncEcho())
        assertWrites(fanOut(of: result), [desk: 0, side: 0.05])
    }

    func testAnyMemberCanLead() {
        let result = Policy.classify(write(0.4, on: side), group: group(offsets: [builtIn: 0.1]),
                                     state: Policy.GroupSyncState(), echo: Policy.SyncEcho())
        assertWrites(fanOut(of: result), [builtIn: 0.5, desk: 0.4])
    }

    func testALeaderEventRecordsTheGroupsNewBaseLevel() {
        let result = Policy.classify(write(0.6, on: builtIn), group: group(),
                                     state: Policy.GroupSyncState(), echo: Policy.SyncEcho())
        XCTAssertEqual(result.state.leaderRecordID, builtIn)
        XCTAssertEqual(result.state.leaderValue, 0.6)
        XCTAssertEqual(result.state.lastFanOutAt, epoch)
    }

    // MARK: - Absent + governed members

    func testAnAbsentMemberIsSkippedAndReportedRatherThanWritten() {
        let result = Policy.classify(write(0.6, on: builtIn, world: world(present: [builtIn, desk])),
                                     group: group(), state: Policy.GroupSyncState(),
                                     echo: Policy.SyncEcho())
        let fannedOut = fanOut(of: result)
        assertWrites(fannedOut, [desk: 0.6])
        XCTAssertEqual(fannedOut.absent, [side])
    }

    func testAGovernedFollowerIsSkippedSoFaceLightAndAppPresetsKeepTheirDisplay() {
        let result = Policy.classify(write(0.6, on: builtIn, world: world(governed: [side])),
                                     group: group(), state: Policy.GroupSyncState(),
                                     echo: Policy.SyncEcho())
        let fannedOut = fanOut(of: result)
        assertWrites(fannedOut, [desk: 0.6])
        XCTAssertEqual(fannedOut.governed, [side])
    }

    func testAWriteOnAGovernedDisplayNeverLeadsTheGroup() {
        let result = Policy.classify(write(1.0, on: desk, world: world(governed: [desk])),
                                     group: group(), state: Policy.GroupSyncState(),
                                     echo: Policy.SyncEcho())
        XCTAssertEqual(result.outcome, .governed)
        XCTAssertNil(result.state.leaderValue)
    }

    func testAGroupWithBrightnessSyncOffWritesNothing() {
        let result = Policy.classify(write(0.6, on: builtIn), group: group(syncBrightness: false),
                                     state: Policy.GroupSyncState(), echo: Policy.SyncEcho())
        XCTAssertEqual(result.outcome, .syncDisabled)
    }

    // MARK: - Echo suppression

    func testAWriteTaggedWithALiveTokenIsIgnoredAsALeader() {
        var echo = Policy.SyncEcho()
        let token = echo.begin(leader: builtIn, followers: [desk, side])
        let result = Policy.classify(write(0.6, on: desk, token: token), group: group(),
                                     state: Policy.GroupSyncState(), echo: echo)
        XCTAssertEqual(result.outcome, .echo)
    }

    func testAnUntaggedWriteOnAnInFlightFollowerIsIgnoredAsALeader() {
        var echo = Policy.SyncEcho()
        _ = echo.begin(leader: builtIn, followers: [desk])
        let result = Policy.classify(write(0.6, on: desk), group: group(),
                                     state: Policy.GroupSyncState(), echo: echo)
        XCTAssertEqual(result.outcome, .echo)
    }

    func testAFinishedFanOutStopsSuppressingTheUsersHand() {
        var echo = Policy.SyncEcho()
        let token = echo.begin(leader: builtIn, followers: [desk])
        echo.end(token)
        let result = Policy.classify(write(0.6, on: desk, token: token), group: group(),
                                     state: Policy.GroupSyncState(), echo: echo)
        XCTAssertNotEqual(result.outcome, .echo)
        XCTAssertTrue(fanOut(of: result).writes.contains { $0.member == builtIn })
    }

    func testBalancedBeginAndEndLeavesNoFanOutOpen() {
        var echo = Policy.SyncEcho()
        let first = echo.begin(leader: builtIn, followers: [desk])
        let second = echo.begin(leader: desk, followers: [builtIn])
        echo.end(first)
        XCTAssertTrue(echo.hasOpenFanOut)
        echo.end(second)
        XCTAssertFalse(echo.hasOpenFanOut)
    }

    func testAnUngroupedDisplayInFlightElsewhereDoesNotSuppressThisLeader() {
        var echo = Policy.SyncEcho()
        _ = echo.begin(leader: builtIn, followers: [side])
        let result = Policy.classify(write(0.6, on: desk), group: group(),
                                     state: Policy.GroupSyncState(), echo: echo)
        XCTAssertNotEqual(result.outcome, .echo)
    }

    // MARK: - Follower offset learning

    func testNudgingAFollowerAfterAFanOutRelearnsItsOffsetInsteadOfWriting() {
        let led = Policy.classify(write(0.6, on: builtIn), group: group(),
                                  state: Policy.GroupSyncState(), echo: Policy.SyncEcho())
        let corrected = Policy.classify(write(0.8, on: desk, at: epoch.addingTimeInterval(4)),
                                        group: led.group, state: led.state, echo: Policy.SyncEcho())
        XCTAssertEqual(learnedOffset(of: corrected), 0.2, accuracy: 0.0001)
        XCTAssertEqual(corrected.group.offset(for: desk), 0.2, accuracy: 0.0001)
    }

    func testARelearnedOffsetIsUsedByTheNextFanOut() {
        let led = Policy.classify(write(0.6, on: builtIn), group: group(),
                                  state: Policy.GroupSyncState(), echo: Policy.SyncEcho())
        let corrected = Policy.classify(write(0.8, on: desk, at: epoch.addingTimeInterval(4)),
                                        group: led.group, state: led.state, echo: Policy.SyncEcho())
        let again = Policy.classify(write(0.5, on: builtIn, at: epoch.addingTimeInterval(8)),
                                    group: corrected.group, state: corrected.state,
                                    echo: Policy.SyncEcho())
        assertWrites(fanOut(of: again), [desk: 0.7, side: 0.5])
    }

    func testACorrectionKeepsTheWindowOpenForTheNextNudge() {
        let led = Policy.classify(write(0.6, on: builtIn), group: group(),
                                  state: Policy.GroupSyncState(), echo: Policy.SyncEcho())
        let first = Policy.classify(write(0.7, on: desk, at: epoch.addingTimeInterval(25)),
                                    group: led.group, state: led.state, echo: Policy.SyncEcho())
        let second = Policy.classify(write(0.75, on: desk, at: epoch.addingTimeInterval(50)),
                                     group: first.group, state: first.state, echo: Policy.SyncEcho())
        XCTAssertEqual(learnedOffset(of: second), 0.15, accuracy: 0.0001)
    }

    func testAMoveOnAnotherMemberAfterTheWindowLeadsInsteadOfLearning() {
        let led = Policy.classify(write(0.6, on: builtIn), group: group(),
                                  state: Policy.GroupSyncState(), echo: Policy.SyncEcho())
        let later = epoch.addingTimeInterval(Policy.defaultCorrectionWindow + 1)
        let result = Policy.classify(write(0.8, on: desk, at: later), group: led.group,
                                     state: led.state, echo: Policy.SyncEcho())
        assertWrites(fanOut(of: result), [builtIn: 0.8, side: 0.8])
        XCTAssertEqual(result.state.leaderRecordID, desk)
    }

    func testMovingTheLeaderAgainInsideTheWindowStillLeads() {
        let led = Policy.classify(write(0.6, on: builtIn), group: group(),
                                  state: Policy.GroupSyncState(), echo: Policy.SyncEcho())
        let again = Policy.classify(write(0.7, on: builtIn, at: epoch.addingTimeInterval(2)),
                                    group: led.group, state: led.state, echo: Policy.SyncEcho())
        assertWrites(fanOut(of: again), [desk: 0.7, side: 0.7])
    }

    func testTheFirstWriteEverLeadsBecauseThereIsNoBaseLevelToCorrectAgainst() {
        let result = Policy.classify(write(0.8, on: desk), group: group(),
                                     state: Policy.GroupSyncState(), echo: Policy.SyncEcho())
        XCTAssertEqual(result.state.leaderRecordID, desk)
    }

    func testACorrectionAgainstALeaderThatLeftTheGroupLeadsInstead() {
        let led = Policy.classify(write(0.6, on: builtIn), group: group(),
                                  state: Policy.GroupSyncState(), echo: Policy.SyncEcho())
        let orphaned = DisplayGroupStore.removeMember(builtIn, from: led.group.id, in: [led.group])[0]
        let result = Policy.classify(write(0.8, on: desk, at: epoch.addingTimeInterval(4)),
                                     group: orphaned, state: led.state, echo: Policy.SyncEcho())
        XCTAssertEqual(result.state.leaderRecordID, desk)
    }

    func testALearnedOffsetIsClampedToTheLimit() {
        let led = Policy.classify(write(0.05, on: builtIn), group: group(),
                                  state: Policy.GroupSyncState(), echo: Policy.SyncEcho())
        var stretched = led.state
        stretched.leaderValue = -2  // a leader value the clamp must absorb
        let result = Policy.classify(write(0.9, on: desk, at: epoch.addingTimeInterval(1)),
                                     group: led.group, state: stretched, echo: Policy.SyncEcho())
        XCTAssertEqual(result.group.offset(for: desk), DisplayGroup.offsetLimit)
    }

    // MARK: - Contrast (flat mirror)

    func testContrastMirrorsTheLeadersValueWithoutApplyingBrightnessOffsets() {
        let mirrored = Policy.contrastFanOut(write(0.7, on: builtIn),
                                             group: group(offsets: [desk: 0.3], syncContrast: true),
                                             echo: Policy.SyncEcho())
        assertWrites(mirrored, [desk: 0.7, side: 0.7])
    }

    func testContrastIsSilentWhenTheGroupDoesNotSyncIt() {
        let mirrored = Policy.contrastFanOut(write(0.7, on: builtIn), group: group(),
                                             echo: Policy.SyncEcho())
        XCTAssertTrue(mirrored.isEmpty)
    }

    func testContrastSkipsAMemberWhosePanelHasNoContrastChannel() {
        let mirrored = Policy.contrastFanOut(
            write(0.7, on: builtIn, world: world(contrastCapable: [builtIn, desk])),
            group: group(syncContrast: true), echo: Policy.SyncEcho())
        assertWrites(mirrored, [desk: 0.7])
        XCTAssertEqual(mirrored.unsupported, [side])
    }

    func testContrastSkipsAbsentAndGovernedMembers() {
        let mirrored = Policy.contrastFanOut(
            write(0.7, on: builtIn, world: world(present: [builtIn, desk], governed: [desk])),
            group: group(syncContrast: true), echo: Policy.SyncEcho())
        XCTAssertTrue(mirrored.isEmpty)
        XCTAssertEqual(mirrored.absent, [side])
        XCTAssertEqual(mirrored.governed, [desk])
    }

    func testContrastIgnoresOurOwnEchoedWrite() {
        var echo = Policy.SyncEcho()
        let token = echo.begin(leader: builtIn, followers: [desk, side])
        let mirrored = Policy.contrastFanOut(write(0.7, on: desk, token: token),
                                             group: group(syncContrast: true), echo: echo)
        XCTAssertTrue(mirrored.isEmpty)
    }

    func testContrastLearnsNoOffsetSoRepeatedMirrorsStayFlat() {
        var syncingContrast = group(syncContrast: true)
        syncingContrast.setOffset(0.3, for: desk)
        let first = Policy.contrastFanOut(write(0.7, on: builtIn), group: syncingContrast,
                                          echo: Policy.SyncEcho())
        let second = Policy.contrastFanOut(write(0.7, on: desk, at: epoch.addingTimeInterval(4)),
                                           group: syncingContrast, echo: Policy.SyncEcho())
        assertWrites(first, [desk: 0.7, side: 0.7])
        assertWrites(second, [builtIn: 0.7, side: 0.7])
    }
}
