import XCTest
@testable import TopologyCore

final class AutoDisconnectBuiltInPolicyTests: XCTestCase {
    func testFiresOnFirstExternalArrivalWhenEnabled() {
        var policy = AutoDisconnectBuiltInPolicy()
        XCTAssertTrue(policy.onTopologyChange(enabled: true, externalPresent: true))
    }

    func testDoesNotFireWhenDisabled() {
        var policy = AutoDisconnectBuiltInPolicy()
        XCTAssertFalse(policy.onTopologyChange(enabled: false, externalPresent: true))
        // ...and after later enabling, a *steady* external (no new edge) still doesn't fire.
        XCTAssertFalse(policy.onTopologyChange(enabled: true, externalPresent: true))
    }

    func testSecondExternalDoesNotReTrigger() {
        var policy = AutoDisconnectBuiltInPolicy()
        XCTAssertTrue(policy.onTopologyChange(enabled: true, externalPresent: true))   // first arrives → fire
        // A second external: presence is still "some" → no new rising edge.
        XCTAssertFalse(policy.onTopologyChange(enabled: true, externalPresent: true))
    }

    func testDisconnectingBuiltInDoesNotReTrigger() {
        // After firing, turning the built-in off raises another topology change, but the external is
        // still present (presence stays true) so the policy must not fire again.
        var policy = AutoDisconnectBuiltInPolicy()
        XCTAssertTrue(policy.onTopologyChange(enabled: true, externalPresent: true))
        XCTAssertFalse(policy.onTopologyChange(enabled: true, externalPresent: true))
    }

    func testReArmsAfterAllExternalsLeave() {
        var policy = AutoDisconnectBuiltInPolicy()
        XCTAssertTrue(policy.onTopologyChange(enabled: true, externalPresent: true))    // arrive → fire
        XCTAssertFalse(policy.onTopologyChange(enabled: true, externalPresent: false))  // all leave
        XCTAssertTrue(policy.onTopologyChange(enabled: true, externalPresent: true))    // new arrival → fire again
    }

    func testSeedSuppressesPreexistingExternalAsArrival() {
        // Launch with an external already attached: seed so the first observed change isn't an "edge".
        var policy = AutoDisconnectBuiltInPolicy()
        policy.seed(externalPresent: true)
        XCTAssertFalse(policy.onTopologyChange(enabled: true, externalPresent: true))
        // A genuine unplug+replug still fires.
        XCTAssertFalse(policy.onTopologyChange(enabled: true, externalPresent: false))
        XCTAssertTrue(policy.onTopologyChange(enabled: true, externalPresent: true))
    }

    func testArrivalWhileDisabledIsTrackedSoLaterEnableDoesNotFireOnSteadyState() {
        var policy = AutoDisconnectBuiltInPolicy()
        // External arrives while the policy is off — tracked but not fired.
        XCTAssertFalse(policy.onTopologyChange(enabled: false, externalPresent: true))
        // Now enabled, but the external didn't *just* arrive → no fire.
        XCTAssertFalse(policy.onTopologyChange(enabled: true, externalPresent: true))
        // It leaves and comes back while enabled → fires.
        XCTAssertFalse(policy.onTopologyChange(enabled: true, externalPresent: false))
        XCTAssertTrue(policy.onTopologyChange(enabled: true, externalPresent: true))
    }

    func testNoExternalNeverFires() {
        var policy = AutoDisconnectBuiltInPolicy()
        XCTAssertFalse(policy.onTopologyChange(enabled: true, externalPresent: false))
        XCTAssertFalse(policy.onTopologyChange(enabled: true, externalPresent: false))
    }
}
