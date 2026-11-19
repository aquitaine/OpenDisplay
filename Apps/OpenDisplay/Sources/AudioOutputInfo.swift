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
        let id: AudioDeviceID
        let uid: String
        let name: String
        let transport: AudioOutputTransport
    }

    /// The current default output device, or nil if CoreAudio has none / the query fails.
    static func currentDefaultOutput() -> Snapshot? {
        guard let deviceID = defaultOutputDeviceID() else { return nil }
        return snapshot(deviceID)
    }

    static func snapshot(_ id: AudioDeviceID) -> Snapshot? {
        guard let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) else { return nil }
        return Snapshot(id: id, uid: uid, name: deviceName(id) ?? "", transport: transportType(id))
    }

    static func devices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size > 0 else { return [] }
        var result = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = result.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, $0.baseAddress!)
        }
        return status == noErr ? result : []
    }

    static func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    /// Never select a headphone jack or a device inferred from the display's name.
    static func builtInSpeakers() -> AudioDeviceID? {
        devices().first { id in
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var transport: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) == noErr,
                  transport == kAudioDeviceTransportTypeBuiltIn,
                  let name = deviceName(id)?.lowercased(), name.contains("speaker") else { return false }
            address.mSelector = kAudioDevicePropertyJackIsConnected
            address.mScope = kAudioDevicePropertyScopeOutput
            var connected: UInt32 = 0
            if AudioObjectHasProperty(id, &address),
               AudioObjectGetPropertyData(id, &address, 0, nil, &size, &connected) == noErr,
               connected != 0 { return false }
            return true
        }
    }

    @discardableResult
    static func selectOutput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var target = id
        guard AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &target) == noErr else { return false }
        return defaultOutputDeviceID() == id
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
