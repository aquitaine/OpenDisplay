import AppKit
import ColorSync
import CoreGraphics
import Foundation

/// Read-only integration check: enumerate profiles and compare each active display with ColorSync.
@main
struct ColorProfileChecks {
    static func main() {
        _ = NSApplication.shared
        let profiles = ColorProfileService.availableProfiles()
        precondition(!profiles.isEmpty, "Installed RGB profiles must remain selectable")
        let urls = profiles.map { $0.url.standardizedFileURL }
        precondition(Set(urls).count == urls.count, "Profile files must not be listed twice")
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { preconditionFailure("Missing display identifier") }
            let displayID = number.uint32Value
            guard let profile = ColorSyncProfileCreateWithDisplayID(displayID)?.takeRetainedValue(),
                  let expected = ColorSyncProfileCopyDescriptionString(profile)?.takeRetainedValue() as String?
            else { continue }
            precondition(ColorProfileService.currentProfileName(for: displayID) == expected,
                         "The reported profile must match the active ColorSync profile")
        }
        print("PASS: RGB profile enumeration, unique files, and active display profile names")
    }
}
