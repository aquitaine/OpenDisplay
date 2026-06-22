import XCTest
@testable import DisplayDomain

final class StateMachineTests: XCTestCase {
    func testLegalReachabilityPath() {
        XCTAssertTrue(Reachability.active.canTransition(to: .disconnecting))
        XCTAssertTrue(Reachability.disconnecting.canTransition(to: .managedOffline))
        XCTAssertTrue(Reachability.managedOffline.canTransition(to: .reconnecting))
        XCTAssertTrue(Reachability.reconnecting.canTransition(to: .active))
    }

    func testRollbackPathIsLegal() {
        // disconnecting → active is the rollback edge.
        XCTAssertTrue(Reachability.disconnecting.canTransition(to: .active))
    }

    func testIllegalReachabilityTransitionsRejected() {
        XCTAssertFalse(Reachability.active.canTransition(to: .reconnecting))
        XCTAssertFalse(Reachability.systemAbsent.canTransition(to: .managedOffline))
        XCTAssertFalse(Reachability.managedOffline.canTransition(to: .active))
    }

    func testIdempotentReachabilityIsLegal() {
        for state in [Reachability.active, .managedOffline, .systemAbsent] {
            XCTAssertTrue(state.canTransition(to: state))
        }
    }

    func testTransactionHappyPath() {
        let path: [TransactionState] = [.idle, .resolving, .preflight, .checkpointed, .applying,
                                        .observing, .verifying, .committed]
        for (current, next) in zip(path, path.dropFirst()) {
            XCTAssertTrue(current.canTransition(to: next), "\(current) → \(next) should be legal")
        }
        XCTAssertTrue(TransactionState.committed.isTerminal)
    }

    func testTransactionRollbackPath() {
        XCTAssertTrue(TransactionState.applying.canTransition(to: .rollingBack))
        XCTAssertTrue(TransactionState.verifying.canTransition(to: .rollingBack))
        XCTAssertTrue(TransactionState.rollingBack.canTransition(to: .recovered))
        XCTAssertTrue(TransactionState.rollingBack.canTransition(to: .degraded))
        XCTAssertTrue(TransactionState.degraded.isTerminal)
        XCTAssertTrue(TransactionState.recovered.isTerminal)
    }

    func testTransactionIllegalTransitionsRejected() {
        XCTAssertFalse(TransactionState.idle.canTransition(to: .committed))
        XCTAssertFalse(TransactionState.committed.canTransition(to: .applying))
        XCTAssertFalse(TransactionState.preflight.canTransition(to: .committed))
    }

    func testTopologyGenerationOrdering() {
        let g0 = TopologyGeneration.initial
        let g1 = g0.next()
        XCTAssertLessThan(g0, g1)
        XCTAssertEqual(g1.value, 1)
    }
}
