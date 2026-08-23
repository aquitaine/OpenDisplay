#if os(macOS)
import Foundation
import IOKit.ps
import TopologyCore

/// Watches the two things `XDRPowerAutomation` needs to know about the machine's power state: which
/// source it is running on (IOKit power sources) and whether Low Power Mode is on (`ProcessInfo`).
/// The thin macOS wiring for a decision that is made entirely in the pure policy — this type reads
/// and reports, and never decides anything.
///
/// Held only while it is earning its keep. `AppModel` starts it when XDR Brightness is on AND at
/// least one battery-family rule is enabled, and stops it otherwise: a run-loop source and a
/// notification observer are cheap but not free, and there is no reason to watch the battery for a
/// user who has asked for nothing about it. (The auto-off timer needs no power monitoring at all.)
///
/// Desktop Macs have no internal battery source, so `currentSnapshot` reports `onBattery: false,
/// batteryPercent: nil` — under which every battery-family rule is inert, with no special-casing
/// anywhere above.
@MainActor
final class PowerSourceMonitor {
    /// Called on every power-source or Low Power Mode change with a freshly read snapshot. Not
    /// called by `start()` — the caller reads `currentSnapshot()` itself so setup and evaluation
    /// stay separate calls (a callback fired from inside `start` would re-enter the reconcile that
    /// started it).
    private var onChange: ((XDRPowerAutomation.PowerSnapshot) -> Void)?
    private var powerSourceSource: CFRunLoopSource?
    private var lowPowerModeObserver: NSObjectProtocol?

    /// True while the IOKit source and the Low Power Mode observer are installed.
    var isRunning: Bool { powerSourceSource != nil }

    /// Begins watching, reporting each change to `onChange`. Idempotent: starting while running only
    /// swaps the callback, so a reconcile that runs on every settings change can call it freely.
    func start(onChange: @escaping (XDRPowerAutomation.PowerSnapshot) -> Void) {
        self.onChange = onChange
        guard !isRunning else { return }
        // The IOKit callback is a C function pointer and so can capture nothing; `self` travels
        // through the context pointer instead, unretained — safe only because the monitor outlives
        // its own run-loop source: `stop()` is the one thing that takes the source off (see its
        // contract below), and the owner must call it before letting the monitor go.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerSourceMonitor>.fromOpaque(context).takeUnretainedValue()
            // The source is scheduled on the main run loop, so this callback arrives on the main
            // thread — the isolation `MainActor.assumeIsolated` asserts here.
            MainActor.assumeIsolated { monitor.emitCurrentSnapshot() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSourceSource = source
        }
        // Low Power Mode is not a power *source* change, so IOKit never reports it — it arrives as
        // its own ProcessInfo notification, on an arbitrary queue.
        lowPowerModeObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.emitCurrentSnapshot() }
        }
    }

    /// Removes both observers. Idempotent, and safe to call from teardown.
    ///
    /// This is the ONLY way the run-loop source comes off: a `@MainActor` type can't take its own
    /// state apart from a nonisolated `deinit`, so there is no last-resort cleanup here. The
    /// contract is therefore that the owner outlives the source — `AppModel` holds the monitor in a
    /// `let` for the whole process and stops it on `willTerminate`. An owner that drops the monitor
    /// without stopping it first would leave IOKit calling into freed memory.
    func stop() {
        if let source = powerSourceSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSourceSource = nil
        }
        if let observer = lowPowerModeObserver {
            NotificationCenter.default.removeObserver(observer)
            lowPowerModeObserver = nil
        }
        onChange = nil
    }

    private func emitCurrentSnapshot() {
        onChange?(Self.currentSnapshot())
    }

    /// Reads the machine's power state right now. Total: anything unreadable degrades to "on wall
    /// power, charge unknown", which is the state under which no battery rule fires — the app must
    /// never dim someone's screen because IOKit declined to answer.
    static func currentSnapshot() -> XDRPowerAutomation.PowerSnapshot {
        let lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return XDRPowerAutomation.PowerSnapshot(lowPowerMode: lowPowerMode)
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                    .takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            // "Battery Power" vs "AC Power" — the state the OS itself reports, rather than an
            // inference from whether an adapter is attached (a connected-but-not-charging adapter
            // still counts as wall power, and the user experiences it that way).
            let onBattery = description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
            var percent: Int?
            if let current = description[kIOPSCurrentCapacityKey] as? Int,
               let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 {
                percent = min(max(Int((Double(current) / Double(maximum) * 100).rounded()), 0), 100)
            }
            return XDRPowerAutomation.PowerSnapshot(
                onBattery: onBattery, batteryPercent: percent, lowPowerMode: lowPowerMode)
        }
        return XDRPowerAutomation.PowerSnapshot(lowPowerMode: lowPowerMode)  // no battery: a desktop
    }
}
#endif
