import DisplayDomain
import XCTest
@testable import TopologyCore

final class DisplayGroupStoreTests: XCTestCase {
    private let builtIn = DisplayRecordID(rawValue: "cgid:1")
    private let desk = DisplayRecordID(rawValue: "cgid:2")
    private let side = DisplayRecordID(rawValue: "cgid:3")

    private func group(_ name: String, _ members: [DisplayRecordID],
                       id: UUID = UUID()) -> DisplayGroup {
        DisplayGroup(id: id, name: name, memberRecordIDs: members)
    }

    // MARK: - Membership + the one-group-per-display invariant

    func testAddMemberJoinsTheNamedGroup() {
        let work = group("Work", [builtIn])
        let updated = DisplayGroupStore.addMember(desk, to: work.id, in: [work])
        XCTAssertEqual(updated[0].memberRecordIDs, [builtIn, desk])
    }

    func testAddingToASecondGroupRemovesTheDisplayFromTheFirst() {
        let work = group("Work", [builtIn, desk])
        let gaming = group("Gaming", [])
        let updated = DisplayGroupStore.addMember(desk, to: gaming.id, in: [work, gaming])
        XCTAssertEqual(updated[0].memberRecordIDs, [builtIn])
        XCTAssertEqual(updated[1].memberRecordIDs, [desk])
    }

    func testAddingAMemberTwiceIsIdempotent() {
        let work = group("Work", [builtIn, desk])
        let updated = DisplayGroupStore.addMember(desk, to: work.id, in: [work])
        XCTAssertEqual(updated[0].memberRecordIDs, [builtIn, desk])
    }

    func testRemoveMemberDropsTheDisplayAndItsLearnedOffset() {
        var work = group("Work", [builtIn, desk])
        work.setOffset(0.2, for: desk)
        let updated = DisplayGroupStore.removeMember(desk, from: work.id, in: [work])
        XCTAssertEqual(updated[0].memberRecordIDs, [builtIn])
        XCTAssertNil(updated[0].offsetByMember[desk.rawValue])
    }

    func testRemoveMemberLeavesOtherGroupsAlone() {
        let work = group("Work", [builtIn])
        let gaming = group("Gaming", [desk])
        let updated = DisplayGroupStore.removeMember(desk, from: work.id, in: [work, gaming])
        XCTAssertEqual(updated[1].memberRecordIDs, [desk])
    }

    func testUpdateReclaimsMembersFromEveryOtherGroup() {
        let work = group("Work", [builtIn, desk])
        var gaming = group("Gaming", [])
        gaming.memberRecordIDs = [desk, side]
        let updated = DisplayGroupStore.update(gaming, in: [work, gaming])
        XCTAssertEqual(updated[0].memberRecordIDs, [builtIn])
        XCTAssertEqual(updated[1].memberRecordIDs, [desk, side])
    }

    func testUpdateIgnoresAnUnknownGroup() {
        let work = group("Work", [builtIn])
        let stranger = group("Stranger", [builtIn])
        XCTAssertEqual(DisplayGroupStore.update(stranger, in: [work]), [work])
    }

    // MARK: - Lifecycle

    func testCreateAppendsATrimmedGroup() {
        let created = DisplayGroupStore.create(named: "  Desk  ", in: [])
        XCTAssertEqual(created?.count, 1)
        XCTAssertEqual(created?.first?.name, "Desk")
        XCTAssertTrue(created?.first?.syncBrightness == true)
        XCTAssertTrue(created?.first?.syncContrast == false)
    }

    func testCreateRejectsADuplicateNameRegardlessOfCase() {
        let existing = group("Desk", [])
        XCTAssertNil(DisplayGroupStore.create(named: "desk", in: [existing]))
    }

    func testCreateRejectsABlankName() {
        XCTAssertNil(DisplayGroupStore.create(named: "   ", in: []))
    }

    func testDeleteRemovesOnlyTheNamedGroup() {
        let work = group("Work", [builtIn])
        let gaming = group("Gaming", [desk])
        XCTAssertEqual(DisplayGroupStore.delete(id: work.id, from: [work, gaming]), [gaming])
    }

    // MARK: - Lookup

    func testGroupContainingFindsTheOwningGroup() {
        let work = group("Work", [builtIn])
        let gaming = group("Gaming", [desk])
        XCTAssertEqual(DisplayGroupStore.group(containing: desk, in: [work, gaming])?.name, "Gaming")
        XCTAssertNil(DisplayGroupStore.group(containing: side, in: [work, gaming]))
    }

    func testGroupNamedIsCaseInsensitive() {
        let work = group("Desk", [builtIn])
        XCTAssertEqual(DisplayGroupStore.group(named: "DESK", in: [work])?.id, work.id)
        XCTAssertNil(DisplayGroupStore.group(named: "other", in: [work]))
    }

    // MARK: - Adaptive exclusion

    func testAGroupedDisplayIsExcludedFromAdaptiveTargeting() {
        let work = group("Work", [builtIn, desk])
        XCTAssertTrue(DisplayGroupStore.isGroupGoverned(desk, in: [work]))
        XCTAssertFalse(DisplayGroupStore.isGroupGoverned(side, in: [work]))
    }

    func testAGroupWithBrightnessSyncOffDoesNotExcludeItsMembersFromAdaptive() {
        var work = group("Work", [builtIn, desk])
        work.syncBrightness = false
        XCTAssertFalse(DisplayGroupStore.isGroupGoverned(desk, in: [work]))
    }

    // MARK: - Offsets

    func testOffsetDefaultsToZeroForAFreshMember() {
        XCTAssertEqual(group("Work", [desk]).offset(for: desk), 0)
    }

    func testSetOffsetClampsToTheLimit() {
        var work = group("Work", [desk])
        work.setOffset(3, for: desk)
        XCTAssertEqual(work.offset(for: desk), DisplayGroup.offsetLimit)
        work.setOffset(-3, for: desk)
        XCTAssertEqual(work.offset(for: desk), -DisplayGroup.offsetLimit)
    }
}
