#if os(macOS)
import Foundation
import IOKit.pwr_mgt
import TopologyCore

/// Real `PowerAssertionControlling` backed by IOKit power management. A
/// `kIOPMAssertionTypePreventUserIdleDisplaySleep` assertion keeps the displays from idle-dimming and
/// sleeping (it does **not** block system sleep, the lid, or a manual sleep) for as long as it's held.
///
/// Best-effort by contract: if the OS refuses the assertion, `create` returns `nil` and
/// `DisplaySleepGuard` simply holds nothing — no crash, no retry storm. The assertion is process-bound,
/// so it's also dropped automatically if the app exits without releasing it.
struct IOKitPowerAssertions: PowerAssertionControlling {
    func createPreventDisplaySleepAssertion(named name: String) -> UInt32? {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name as CFString,
            &id
        )
        return result == kIOReturnSuccess ? id : nil
    }

    func releaseAssertion(_ handle: UInt32) {
        IOPMAssertionRelease(handle)
    }
}
#endif
