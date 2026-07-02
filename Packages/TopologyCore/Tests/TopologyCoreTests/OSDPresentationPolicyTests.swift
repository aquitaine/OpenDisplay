import XCTest
@testable import DisplayDomain
@testable import TopologyCore

final class OSDPresentationPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testShowSchedulesAutoHide() {
        let policy = OSDPresentationPolicy(autoHide: 1.2)
        let content = OSDContent(kind: .brightness, value: 0.5)
        guard case let .show(shown, hideAt) = policy.decide(event: content, previous: nil, now: now) else {
            return XCTFail("expected show")
        }
        XCTAssertEqual(shown, content)
        XCTAssertEqual(hideAt.timeIntervalSince1970, now.timeIntervalSince1970 + 1.2, accuracy: 1e-6)
    }

    func testRapidChangesPushHideDeadlineForward() {
        let policy = OSDPresentationPolicy(autoHide: 1.0)
        let later = now.addingTimeInterval(0.3)
        guard case let .show(_, hideAt) = policy.decide(
            event: OSDContent(kind: .brightness, value: 0.6), previous: nil, now: later)
        else { return XCTFail("expected show") }
        // Coalesce: a later event extends the visible window relative to that event's time.
        XCTAssertEqual(hideAt.timeIntervalSince1970, later.timeIntervalSince1970 + 1.0, accuracy: 1e-6)
    }

    func testSuppressUnchangedIgnoresIdenticalContent() {
        let policy = OSDPresentationPolicy(autoHide: 1, suppressUnchanged: true)
        let content = OSDContent(kind: .brightness, value: 0.5)
        XCTAssertEqual(policy.decide(event: content, previous: content, now: now), .ignore)
    }

    func testSuppressUnchangedStillShowsChangedContent() {
        let policy = OSDPresentationPolicy(autoHide: 1, suppressUnchanged: true)
        let prev = OSDContent(kind: .brightness, value: 0.5)
        let next = OSDContent(kind: .brightness, value: 0.6)
        if case .ignore = policy.decide(event: next, previous: prev, now: now) {
            XCTFail("changed content must show")
        }
    }

    func testWithoutSuppressionIdenticalStillShows() {
        let policy = OSDPresentationPolicy(autoHide: 1, suppressUnchanged: false)
        let content = OSDContent(kind: .volume, value: 1)
        if case .ignore = policy.decide(event: content, previous: content, now: now) {
            XCTFail("default policy shows even at the rails (matches native HUD)")
        }
    }

    func testShouldHide() {
        let policy = OSDPresentationPolicy(autoHide: 1)
        let hideAt = now.addingTimeInterval(1)
        XCTAssertFalse(policy.shouldHide(now: now, hideAt: hideAt))
        XCTAssertTrue(policy.shouldHide(now: hideAt, hideAt: hideAt))
        XCTAssertTrue(policy.shouldHide(now: now.addingTimeInterval(2), hideAt: hideAt))
    }
}
