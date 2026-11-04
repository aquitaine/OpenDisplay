#if os(macOS)
import AppKit
import Combine
import CoreAudio
import Foundation
import TopologyCore
import os

enum MonitorAudioRoutePolicy {
    static func shouldFallback(enabled: Bool, missingUID: String, currentUID: String?) -> Bool {
        enabled && (currentUID == nil || currentUID == missingUID)
    }
}

/// Device identity must settle before recreating the tap. Failed starts use bounded backoff.
struct MonitorAudioRecoveryPolicy {
    private var observedID: AudioDeviceID?
    private var stableSince: TimeInterval = 0
    private var retryAt: TimeInterval = 0
    private(set) var failures = 0

    mutating func ready(deviceID: AudioDeviceID?, now: TimeInterval) -> Bool {
        if deviceID != observedID {
            observedID = deviceID
            stableSince = now
            failures = 0
            retryAt = 0
            return false
        }
        return deviceID != nil && now - stableSince >= 1 && now >= retryAt && failures < 5
    }
    mutating func failed(now: TimeInterval) {
        failures += 1
        retryAt = now + min(8, pow(2, Double(failures - 1)))
    }
    mutating func recovered() { failures = 0; retryAt = 0 }
}

/// An explicitly enabled, session-only stereo gain path. No virtual driver or recording.
@MainActor
final class MonitorAudioController: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var active = false
    @Published private(set) var level: Float = 1
    @Published private(set) var status = "Choose an HDMI or DisplayPort sound output, then enable software volume."
    @Published var fallbackEnabled = UserDefaults.standard.bool(forKey: "MonitorAudioSpeakerFallback") {
        didSet { UserDefaults.standard.set(fallbackEnabled, forKey: "MonitorAudioSpeakerFallback") }
    }
    private var processor: MonitorAudioProcessor?
    private var selected: AudioOutputInfo.Snapshot?
    private var lastExternal: AudioOutputInfo.Snapshot?
    private var timer: Timer?
    private var priorMuteLevel: Float = 1
    private var startedAt: TimeInterval = 0
    private var recovery = MonitorAudioRecoveryPolicy()
    private var managedWasAvailable = false
    private var speakerReturnUID: String?
    private var speakerReturnDeadline: TimeInterval?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkRoute() }
        }
    }

    func setEnabled(_ value: Bool) {
        stop()
        guard value else { status = "Software volume is off. Normal audio restored."; return }
        guard #available(macOS 14.2, *) else { status = "Software volume requires macOS 14.2 or later."; return }
        guard let output = AudioOutputInfo.currentDefaultOutput(),
              output.transport == .hdmi || output.transport == .displayPort else {
            status = "Select the monitor in macOS Sound Output first."
            return
        }
        do {
            let candidate = MonitorAudioProcessor()
            try candidate.start(output: output, initialGain: 1)
            processor = candidate
            selected = output
            lastExternal = output
            level = 1
            priorMuteLevel = 1
            enabled = true
            active = true
            managedWasAvailable = true
            startedAt = ProcessInfo.processInfo.systemUptime
            status = "Software volume active: \(output.name). Audio stays on this Mac."
        } catch {
            status = "Software volume could not start: \(error.localizedDescription) Normal audio restored."
        }
    }

    func stop() {
        suspend()
        selected = nil
        enabled = false
        recovery = MonitorAudioRecoveryPolicy()
        speakerReturnUID = nil
        speakerReturnDeadline = nil
        managedWasAvailable = false
    }

    private func suspend() {
        processor?.stop()
        processor = nil
        active = false
    }

    func setLevel(_ value: Float) {
        guard enabled, value.isFinite else { return }
        level = min(1, max(0, value))
        processor?.setGain(level)
    }

    func handle(_ action: MediaKeyAction, fineStep: Bool) -> Bool {
        guard action.isVolume, active, processor != nil,
              AudioOutputInfo.currentDefaultOutput()?.uid == selected?.uid else { return false }
        switch action {
        case .volumeUp, .volumeDown: setLevel(level + action.signedDelta(fineStep: fineStep))
        case .muteToggle:
            if level > 0 { priorMuteLevel = level; setLevel(0) }
            else { setLevel(priorMuteLevel > 0 ? priorMuteLevel : 0.5) }
        default: return false
        }
        return true
    }

    private func checkRoute() {
        let current = AudioOutputInfo.currentDefaultOutput()
        let devices = AudioOutputInfo.devices()
        if let previous = lastExternal, !devices.contains(where: { AudioOutputInfo.snapshot($0)?.uid == previous.uid }) {
            // A valid new route may be an explicit user choice. Never steal it from headphones/USB.
            if MonitorAudioRoutePolicy.shouldFallback(enabled: fallbackEnabled, missingUID: previous.uid,
                currentUID: current?.uid),
               MonitorAudioRoutePolicy.shouldFallback(enabled: fallbackEnabled, missingUID: previous.uid,
                currentUID: AudioOutputInfo.currentDefaultOutput()?.uid),
               let speakers = AudioOutputInfo.builtInSpeakers() {
                _ = AudioOutputInfo.selectOutput(speakers)
            }
            lastExternal = nil
        }
        if let current, current.transport == .hdmi || current.transport == .displayPort {
            lastExternal = current
        } else if current != nil { lastExternal = nil }
        guard enabled, let selected else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let endpoint = devices.compactMap { AudioOutputInfo.snapshot($0) }.first { $0.uid == selected.uid }
        let ready = recovery.ready(deviceID: endpoint?.id, now: now)
        let actual = AudioOutputInfo.currentDefaultOutput()
        if endpoint == nil, managedWasAvailable { speakerReturnDeadline = now + 3 }
        if let deadline = speakerReturnDeadline, now <= deadline, let actual {
            if AudioOutputInfo.builtInSpeakers() == actual.id { speakerReturnUID = actual.uid }
            else if actual.uid != selected.uid { speakerReturnUID = nil; speakerReturnDeadline = nil }
        }
        guard let endpoint else {
            suspend()
            if let actual, actual.uid != speakerReturnUID { speakerReturnUID = nil }
            managedWasAvailable = false
            status = "Monitor disconnected. Software volume will resume for the same monitor after reconnect."
            return
        }
        managedWasAvailable = true
        guard actual?.uid == selected.uid else {
            suspend()
            if ready, let speakerReturnUID, actual?.uid == speakerReturnUID {
                // Return only from the built-in route observed at unplug, never from headphones/USB.
                if AudioOutputInfo.currentDefaultOutput()?.uid == speakerReturnUID {
                    _ = AudioOutputInfo.selectOutput(endpoint.id)
                }
            } else if let actual, actual.uid != speakerReturnUID { speakerReturnUID = nil }
            status = "Waiting for \(selected.name) to be selected as Sound Output. Previous volume is remembered."
            return
        }
        if endpoint.id != selected.id { suspend() }
        if let processor, !processor.healthy(after: now - startedAt) {
            suspend()
            recovery.failed(now: now)
            status = "Audio stream changed. Rebuilding the monitor audio route…"
            return
        }
        if active, now - startedAt >= 5 { recovery.recovered() }
        guard processor == nil, ready, #available(macOS 14.2, *) else { return }
        do {
            let candidate = MonitorAudioProcessor()
            try candidate.start(output: endpoint, initialGain: level)
            processor = candidate
            self.selected = endpoint
            active = true
            startedAt = ProcessInfo.processInfo.systemUptime
            speakerReturnUID = nil
            speakerReturnDeadline = nil
            status = "Software volume restored: \(endpoint.name). Previous volume and mute preserved."
        } catch {
            recovery.failed(now: now)
            status = recovery.failures >= 5
                ? "Could not restore monitor audio. Turn software volume off/on to retry. Normal audio restored."
                : "Waiting for monitor audio to settle: \(error.localizedDescription) Retrying…"
        }
    }
}

/// Only the IO callback touches lastGain. Control state uses a nonblocking read on the audio thread.
final class MonitorAudioProcessor: @unchecked Sendable {
    private struct Control {
        var gain: Float = 1
        var callbacks: UInt64 = 0
        var invalid = false
        var lastObservedCallbacks: UInt64 = 0
        var lastProgress: TimeInterval = 0
    }
    private let control = OSAllocatedUnfairLock(initialState: Control())
    private var lastGain: Float = 1
    private var tap: AudioObjectID = 0
    private var aggregate: AudioDeviceID = 0
    private var io: AudioDeviceIOProcID?

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func setGain(_ value: Float) {
        guard value.isFinite else { return }
        control.withLock { $0.gain = min(1, max(0, value)) }
    }
    func healthy(after seconds: TimeInterval) -> Bool {
        control.withLock {
            if $0.callbacks != $0.lastObservedCallbacks {
                $0.lastObservedCallbacks = $0.callbacks
                $0.lastProgress = seconds
            }
            return !$0.invalid && (seconds < 3 || seconds - $0.lastProgress < 2)
        }
    }

    @available(macOS 14.2, *)
    func start(output: AudioOutputInfo.Snapshot, initialGain: Float) throws {
        do {
            setGain(initialGain)
            lastGain = min(1, max(0, initialGain))
            let hardwareFormat = try format(output.id, scope: kAudioDevicePropertyScopeOutput)
            guard streamIDs(output.id, scope: kAudioDevicePropertyScopeInput).isEmpty else {
                throw Failure(message: "This device also has input streams and is not supported.")
            }
            guard supported(hardwareFormat) else {
                throw Failure(message: "Only stereo 32-bit floating-point PCM outputs are supported.")
            }
            var pid = getpid()
            var process: AudioObjectID = 0
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &process), "Identify the audio process")
            guard process != 0 else { throw Failure(message: "The playback process could not be excluded.") }
            let description = CATapDescription(__excludingProcesses: [NSNumber(value: process)],
                andDeviceUID: output.uid, withStream: 0)
            description.name = "OpenDisplay monitor volume"
            description.isPrivate = true
            description.muteBehavior = CATapMuteBehavior(rawValue: 2)! // muted only while actively tapped
            try check(AudioHardwareCreateProcessTap(description, &tap), "Create audio tap (check System Audio Recording permission)")
            let specification: [String: Any] = [
                kAudioAggregateDeviceNameKey: "OpenDisplay monitor volume",
                kAudioAggregateDeviceUIDKey: "dev.opendisplay.audio.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceMainSubDeviceKey: output.uid,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output.uid]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                                  kAudioSubTapDriftCompensationKey: true]],
                kAudioAggregateDeviceTapAutoStartKey: true
            ]
            try check(AudioHardwareCreateAggregateDevice(specification as CFDictionary, &aggregate), "Create private audio route")
            let input = try format(aggregate, scope: kAudioDevicePropertyScopeInput)
            let outputFormat = try format(aggregate, scope: kAudioDevicePropertyScopeOutput)
            guard supported(input), supported(outputFormat), input.mSampleRate == outputFormat.mSampleRate,
                  input.mFormatFlags == outputFormat.mFormatFlags,
                  input.mBytesPerFrame == outputFormat.mBytesPerFrame else {
                throw Failure(message: "The monitor's input and output stream layouts do not match.")
            }
            try check(AudioDeviceCreateIOProcIDWithBlock(&io, aggregate, nil) { [self] _, input, _, output, _ in
                render(input: input, output: output)
            }, "Create audio processor")
            try check(AudioDeviceStart(aggregate, io), "Start audio processor")
        } catch { stop(); throw error }
    }

    func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let destination = UnsafeMutableAudioBufferListPointer(output)
        var valid = source.count == destination.count && (destination.count == 1 || destination.count == 2)
        var channelCount: UInt32 = 0
        for i in destination.indices {
            let dst = destination[i]
            channelCount += dst.mNumberChannels
            if let data = dst.mData { memset(data, 0, Int(dst.mDataByteSize)) }
            if i >= source.count || source[i].mNumberChannels != dst.mNumberChannels ||
                source[i].mDataByteSize != dst.mDataByteSize || dst.mDataByteSize % 4 != 0 ||
                dst.mNumberChannels == 0 || dst.mNumberChannels > 2 ||
                source[i].mData == nil || dst.mData == nil { valid = false }
            if dst.mNumberChannels > 0, dst.mNumberChannels <= 2,
               dst.mDataByteSize % (4 * dst.mNumberChannels) != 0 { valid = false }
        }
        valid = valid && channelCount == 2
        let validLayout = valid
        let target = control.withLockIfAvailable { state in
            state.callbacks &+= 1
            if !validLayout { state.invalid = true }
            return state.gain
        } ?? lastGain
        guard valid else { return }
        for i in destination.indices {
            let count = Int(destination[i].mDataByteSize) / MemoryLayout<Float>.size
            let channels = max(1, Int(destination[i].mNumberChannels))
            let frames = max(1, count / channels)
            let src = source[i].mData!.assumingMemoryBound(to: Float.self)
            let dst = destination[i].mData!.assumingMemoryBound(to: Float.self)
            for sample in 0..<count {
                let fraction = Float(sample / channels + 1) / Float(frames)
                dst[sample] = src[sample] * (lastGain + (target - lastGain) * fraction)
            }
        }
        lastGain = target
    }

    func stop() {
        if aggregate != 0 {
            if let io { AudioDeviceStop(aggregate, io); AudioDeviceDestroyIOProcID(aggregate, io) }
            io = nil
            AudioHardwareDestroyAggregateDevice(aggregate)
            aggregate = 0
        }
        if #available(macOS 14.2, *), tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
    }
    deinit { stop() }

    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw Failure(message: "\(operation) failed (\(status)).") }
    }
    private func supported(_ format: AudioStreamBasicDescription) -> Bool {
        format.mFormatID == kAudioFormatLinearPCM && format.mChannelsPerFrame == 2 &&
        format.mBitsPerChannel == 32 && format.mFormatFlags & kAudioFormatFlagIsFloat != 0 &&
        format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0 &&
        format.mFormatFlags & kAudioFormatFlagIsPacked != 0 && format.mSampleRate > 0 &&
        format.mBytesPerFrame == (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 ? 4 : 8)
    }
    private func streamIDs(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> [AudioStreamID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
            mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var streams = [AudioStreamID](repeating: 0, count: Int(size) / MemoryLayout<AudioStreamID>.size)
        let status = streams.withUnsafeMutableBytes { AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0.baseAddress!) }
        return status == noErr ? streams : []
    }
    private func format(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) throws -> AudioStreamBasicDescription {
        let streams = streamIDs(device, scope: scope)
        guard streams.count == 1 else { throw Failure(message: "Exactly one stereo stream is required.") }
        var address = AudioObjectPropertyAddress(mSelector: kAudioStreamPropertyVirtualFormat,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(AudioObjectGetPropertyData(streams[0], &address, 0, nil, &size, &format), "Read audio format")
        return format
    }
}
#endif
