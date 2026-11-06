#if os(macOS)
import ApplicationServices
import CoreGraphics
import Foundation

/// An installed ICC display profile the user can assign.
struct ICCProfile: Identifiable, Hashable {
    let id: String   // file path — stable across launches
    let name: String
    let url: URL
}

/// Per-display ICC colour-profile control via **public ColorSync** (App-Store-safe). Displays are
/// targeted by their persistent ColorSync device UUID (= the CG display UUID), never by index, so a
/// profile change only ever touches the intended display.
///
/// ColorSync's `k…` key constants are imported as non-`Sendable` mutable globals (strict concurrency
/// rejects referencing them), so we use their documented string values directly.
enum ColorProfileService {
    // Computed (not stored) so there's no non-Sendable static state; values are the documented
    // ColorSync constant strings, recovered from the live framework.
    private static var displayClass: CFString { "mntr" as CFString }
    private static var defaultProfileID: CFString { "DeviceDefaultProfileID" as CFString }

    static func deviceUUID(for displayID: CGDirectDisplayID) -> CFUUID? {
        CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
    }

    /// True when ColorSync exposes a device for this display (so writes can target it safely).
    static func isControllable(_ displayID: CGDirectDisplayID) -> Bool {
        guard let uuid = deviceUUID(for: displayID) else { return false }
        return ColorSyncDeviceCopyDeviceInfo(displayClass, uuid)?.takeRetainedValue() != nil
    }

    /// Installed display (RGB) ICC profiles, de-duplicated by file URL and sorted.
    static func availableProfiles() -> [ICCProfile] {
        var collected: [ICCProfile] = []
        withUnsafeMutablePointer(to: &collected) { pointer in
            let callback: ColorSyncProfileIterateCallback = { dict, context in
                guard let context, let info = dict as NSDictionary? else { return true }
                let list = context.assumingMemoryBound(to: [ICCProfile].self)
                guard let url = info["com.apple.ColorSync.ProfileURL"] as? URL,
                      let name = info["com.apple.ColorSync.ProfileDescription"] as? String
                else { return true }
                if let space = info["com.apple.ColorSync.ProfileColorSpace"] as? String,
                   space.trimmingCharacters(in: .whitespacesAndNewlines) != "RGB" {
                    return true
                }
                list.pointee.append(ICCProfile(id: url.path, name: name, url: url))
                return true
            }
            ColorSyncIterateInstalledProfilesWithOptions(
                callback, nil, pointer,
                ["com.apple.ColorSync.WaitForCacheReply": true] as CFDictionary, nil)
        }
        var seen = Set<URL>()
        return collected
            .filter { seen.insert($0.url.standardizedFileURL).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The display's current profile name (a custom override if set, else its factory default).
    static func currentProfileName(for displayID: CGDirectDisplayID) -> String? {
        // The active profile is authoritative. CustomProfiles can contain overrides for other
        // display modes; FactoryProfiles contains nested dictionaries, not direct URL values.
        guard let active = ColorSyncProfileCreateWithDisplayID(displayID)?.takeRetainedValue(),
              let name = ColorSyncProfileCopyDescriptionString(active)?.takeRetainedValue() as String?
        else { return nil }
        return name
    }

    /// Assigns an ICC profile to a display after validating it opens + verifies. Returns success.
    @discardableResult
    static func setProfile(_ profile: ICCProfile, for displayID: CGDirectDisplayID) -> Bool {
        guard let uuid = deviceUUID(for: displayID),
              let cgProfile = ColorSyncProfileCreateWithURL(profile.url as CFURL, nil)?.takeRetainedValue(),
              ColorSyncProfileVerify(cgProfile, nil, nil)
        else { return false }
        let map: [CFString: Any] = [defaultProfileID: profile.url]
        return ColorSyncDeviceSetCustomProfiles(displayClass, uuid, map as CFDictionary)
    }

    /// Removes any custom profile, reverting the display to its factory profile.
    @discardableResult
    static func resetToFactory(for displayID: CGDirectDisplayID) -> Bool {
        guard let uuid = deviceUUID(for: displayID) else { return false }
        let map: [CFString: Any] = [defaultProfileID: kCFNull as Any]
        return ColorSyncDeviceSetCustomProfiles(displayClass, uuid, map as CFDictionary)
    }
}
#endif
