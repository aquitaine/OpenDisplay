/// Decides when a cached DDC controller's IOAVService binding has gone stale and must be rebuilt.
///
/// Why this exists: the app binds one `IOAVService` per external display and keeps it, but macOS
/// does not keep the thing it is bound to. During sleep/DarkWake cycles it can tear down and
/// re-create the display's `DCPAVServiceProxy` (seen live on an LG over HDMI: registry entry
/// 0x10000147d replaced by 0x10003d0ea) while the display itself never leaves the topology — so
/// nothing that watches the display list notices. The old handle keeps answering promptly, every
/// write goes nowhere, and brightness keys and sliders silently stop working until a relaunch.
///
/// Two independent signals, either one sufficient:
/// - the bound proxy is no longer in the IOService plane — a terminated service is detached, so
///   this is the direct, unambiguous "the handle is dead" test;
/// - a run of `failureLimit` consecutive I2C call failures — the net for a dead handle whose
///   service somehow still looks attached. The limit is above 1 on purpose: a panel that's busy
///   (waking scaler, another host on the bus) NAKs a call or two and then recovers, and rebinding
///   on every hiccup would churn bindings and reset probe knowledge for nothing. A dead handle
///   produces nothing *but* failures, so it crosses any small limit almost immediately.
///
/// Pure so `make test` covers it; `ExternalDisplayDDC` reports the inputs, the app acts on them.
public enum DDCBindingPolicy {
    /// Why a binding was rebuilt. The raw value is what the display event timeline records.
    public enum Reason: String, Sendable, Equatable {
        /// The bound `DCPAVServiceProxy` was terminated / detached from the service plane.
        case serviceGone
        /// Too many consecutive I2C call failures on a binding that still looks attached.
        case ioFailures
        /// The Mac (or its displays) woke: every binding is dropped pre-emptively.
        case wake
    }

    /// Consecutive I2C call failures that condemn a binding. Three, because a transiently busy
    /// panel was observed producing one or two and then answering normally.
    public static let defaultFailureLimit = 3

    /// The reason to rebind now, or nil to keep the binding. A dead service outranks a failure run:
    /// it's the more specific diagnosis, and it's what the diagnostics timeline should say.
    public static func rebindReason(serviceInPlane: Bool, consecutiveIOFailures: Int,
                                    failureLimit: Int = defaultFailureLimit) -> Reason? {
        if !serviceInPlane { return .serviceGone }
        if consecutiveIOFailures >= max(failureLimit, 1) { return .ioFailures }
        return nil
    }

    /// Convenience over `rebindReason` for callers that only need the verdict.
    public static func shouldRebind(serviceInPlane: Bool, consecutiveIOFailures: Int,
                                    failureLimit: Int = defaultFailureLimit) -> Bool {
        rebindReason(serviceInPlane: serviceInPlane, consecutiveIOFailures: consecutiveIOFailures,
                     failureLimit: failureLimit) != nil
    }

    /// Whether a rebuild actually landed on a different proxy than the one it replaced.
    ///
    /// A failure-run rebind that finds the SAME registry entry wasn't a stale handle at all — it was
    /// the panel (no DDC, wedged scaler, busy bus). That case must stay quiet: no timeline line, no
    /// probe-cache reset, no brightness re-probe — otherwise a DDC-less external would log and
    /// re-probe on every refresh, defeating the probe tracker that exists to stop exactly that.
    /// A `previousEntryID` of nil (nothing was bound before) always counts as new.
    public static func isNewBinding(previousEntryID: UInt64?, currentEntryID: UInt64) -> Bool {
        previousEntryID != currentEntryID
    }
}
