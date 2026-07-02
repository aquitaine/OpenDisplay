#if os(macOS)
import AutomationSchema
import DisplayDomain
import Foundation

/// Publishes OSD events to other processes (Batch-3 #6) so an external/notch HUD app can render
/// OpenDisplay's brightness/volume changes. Uses `DistributedNotificationCenter` with the stable,
/// versioned `OSDBroadcast` payload. Opt-in (gated by the caller on `publishOSDEventsEnabled`).
enum OSDBroadcaster {
    static func publish(kind: OSDContent.Kind, value: Double, displayID: String,
                        displayName: String?, source: String, now: Date = Date()) {
        let broadcast = OSDBroadcast(
            kind: broadcastKind(kind), value: value, displayID: displayID, displayName: displayName,
            source: source, timestamp: now.timeIntervalSince1970)
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(OSDBroadcast.notificationName),
            object: nil, userInfo: broadcast.userInfo, deliverImmediately: true)
    }

    private static func broadcastKind(_ kind: OSDContent.Kind) -> OSDBroadcast.Kind {
        switch kind {
        case .brightness: return .brightness
        case .volume: return .volume
        case .mute: return .mute
        }
    }
}
#endif
