#if os(macOS)
import CoreAudio
import Foundation
import TopologyCore

/// Reads the system's current default audio output device from CoreAudio (media-key volume fix).
///
/// Volume keys must follow whatever the sound is *actually* playing on, not whichever display the
/// brightness target mode picks. This queries the default output device at keypress time — plain
/// single-property reads on `kAudioObjectSystemObject` that cost microseconds, so no listener or cache
/// is needed. The raw name + transport are handed to the pure `AudioOutputDisplayMatcher` in the core,
/// which decides whether they map to a DDC-capable monitor.
enum AudioOutputInfo {
    /// A snapshot of the default output device: its CoreAudio name and physical transport.
    struct Snapshot {
        let name: String
        let transport: AudioOutputTransport
    }

    /// The current default output device, or nil if CoreAudio has none / the query fails.
    static func currentDefaultOutput() -> Snapshot? {
        guard let deviceID = defaultOutputDeviceID() else { return nil }
        return Snapshot(name: deviceName(deviceID) ?? "", transport: transportType(deviceID))
    }

    private static func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private static func deviceName(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    private static func transportType(_ id: AudioDeviceID) -> AudioOutputTransport {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport)
        guard status == noErr else { return .other }
        switch transport {
        case kAudioDeviceTransportTypeHDMI: return .hdmi
        case kAudioDeviceTransportTypeDisplayPort: return .displayPort
        default: return .other
        }
    }
}
#endif
