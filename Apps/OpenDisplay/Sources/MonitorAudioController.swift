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

/// A pending physical attach survives delayed default-route changes and HAL enumeration.
struct MonitorAudioAttachPolicy {
    private(set) var pendingUID: String?
    private var detectedAt: TimeInterval = 0

    mutating func update(previous: Set<String>, available: Set<String>, preferred: String?,
                         currentUID: String?, currentIsBuiltIn: Bool, now: TimeInterval) -> String? {
        let arrivals = available.subtracting(previous)
        if let preferred, arrivals.contains(preferred) { pendingUID = preferred; detectedAt = now }
        else if arrivals.count == 1 { pendingUID = arrivals.first; detectedAt = now }
        guard let pendingUID else { return nil }
        guard available.contains(pendingUID) else { self.pendingUID = nil; return nil }
        if currentUID == pendingUID { self.pendingUID = nil; return nil }
        if currentUID != nil && !currentIsBuiltIn { self.pendingUID = nil; return nil }
        return currentIsBuiltIn && now - detectedAt >= 1 ? pendingUID : nil
    }
    mutating func selected() { pendingUID = nil }
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
    private var reconnectRequested = false
    private var reconnecting = false
    private var reconnectRetryAt: TimeInterval = 0
    private var logicalDisplayID: String?
    private var logicalOutput: AudioOutputInfo.Snapshot?
    private var attachPolicy = MonitorAudioAttachPolicy()
    private var previousMonitorUIDs: Set<String> = []
    private var preferredMonitorUID: String?
    private var processor: MonitorAudioProcessor?
    private var selected: AudioOutputInfo.Snapshot?
    private var lastExternal: AudioOutputInfo.Snapshot?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var routeListener: AudioObjectPropertyListenerBlock?
    private var lastUserRetry: TimeInterval = -.infinity
    private var priorMuteLevel: Float = 1
    private var startedAt: TimeInterval = 0
    private var recovery = MonitorAudioRecoveryPolicy()
    private var managedWasAvailable = false
    private var speakerReturnUID: String?
    private var speakerReturnDeadline: TimeInterval?

    init() {
        previousMonitorUIDs = Set(AudioOutputInfo.devices().compactMap { AudioOutputInfo.snapshot($0) }
            .filter { $0.transport == .hdmi || $0.transport == .displayPort }.map(\.uid))
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkRoute() }
        }
        self.timer = timer
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.checkRoute() }
        }
        routeListener = listener
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        // Continue recovery while a menu or slider is tracking the pointer.
        RunLoop.main.add(timer, forMode: .common)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.enabled else { return }
                    self.suspend()
                    self.recovery = MonitorAudioRecoveryPolicy()
                    self.checkRoute()
                }
            }
    }

    func setEnabled(_ value: Bool) {
        stop()
        guard processor == nil else {
            status = "Core Audio could not stop the previous session. Quit and reopen OpenDisplay before retrying."
            return
        }
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
        logicalDisplayID = nil
        logicalOutput = nil
        reconnectRequested = false
    }

    /// Quiesce and drain the output while its display link is still alive.
    func prepareLogicalDisconnect(output: AudioOutputInfo.Snapshot, displayID: String) async -> Bool {
        logicalDisplayID = displayID
        logicalOutput = output
        processor?.silence()
        // Require actual silent callbacks, rather than assuming a fixed delay drained HAL.
        if let processor {
            for _ in 0..<50 {
                if processor.hasDrained { break }
                try? await Task.sleep(for: .milliseconds(10))
            }
            guard processor.hasDrained else {
                suspend()
                logicalDisplayID = nil
                logicalOutput = nil
                status = "Display kept on: audio did not acknowledge silent buffers. Retry after pausing playback."
                return false
            }
        }
        lastExternal = nil
        if AudioOutputInfo.currentDefaultOutput()?.uid == output.uid,
           let speakers = AudioOutputInfo.builtInSpeakers(), AudioOutputInfo.selectOutput(speakers) {
            speakerReturnUID = AudioOutputInfo.snapshot(speakers)?.uid
        }
        if let processor, !processor.stop() {
            logicalDisplayID = nil
            logicalOutput = nil
            status = "Display kept on: Core Audio could not retire the old output safely."
            return false
        }
        suspend()
        recovery = MonitorAudioRecoveryPolicy()
        status = "Display audio paused. Using built-in speakers until the monitor returns."
        return true
    }

    func finishLogicalDisconnect(committed: Bool) async {
        if !committed, let id = logicalDisplayID { await logicalDisplayReconnected(displayID: id) }
    }

    func logicalDisplayReconnected(displayID: String) async {
        guard logicalDisplayID == displayID, let saved = logicalOutput, !reconnecting else { return }
        reconnectRequested = true
        reconnecting = true
        defer { reconnecting = false; reconnectRetryAt = ProcessInfo.processInfo.systemUptime + 2 }
        // Keep polling recovery blocked throughout link settling and silent priming.
        for _ in 0..<10 {
            if let endpoint = AudioOutputInfo.devices().compactMap({ AudioOutputInfo.snapshot($0) }).first(where: { $0.uid == saved.uid }) {
                let current = AudioOutputInfo.currentDefaultOutput()
                let speakers = AudioOutputInfo.builtInSpeakers()
                guard current?.uid == saved.uid || current?.uid == speakerReturnUID || (speakers != nil && current?.id == speakers) else {
                    logicalDisplayID = nil; logicalOutput = nil
                    status = "Monitor reconnected. Preserving your other sound output."
                    return
                }
                if enabled, #available(macOS 14.2, *) {
                    suspend()
                    guard processor == nil else { return }
                    let primer = MonitorAudioProcessor()
                    primer.silence()
                    do {
                        // Start a new zero-output stream on the re-created link while music
                        // remains on the Mac. This replaces queued hardware PCM before routing.
                        try primer.start(output: endpoint, initialGain: 0)
                        for _ in 0..<50 {
                            if primer.hasDrained { break }
                            try? await Task.sleep(for: .milliseconds(10))
                        }
                        let drained = primer.hasDrained
                        let stopped = primer.stop()
                        if !stopped { processor = primer }
                        guard stopped, drained else {
                            status = "Monitor audio could not be cleared. Keeping sound on the Mac; retry reconnect."
                            return
                        }
                    } catch {
                        status = "Monitor audio could not restart: \(error.localizedDescription)"
                        return
                    }
                }
                // Recheck after awaits so a manual headphone selection is never overwritten.
                guard logicalDisplayID == displayID else { return }
                let actual = AudioOutputInfo.currentDefaultOutput()
                if actual?.uid == saved.uid || actual?.uid == speakerReturnUID || (speakers != nil && actual?.id == speakers) {
                    guard AudioOutputInfo.selectOutput(endpoint.id) else {
                        status = "Could not select the reconnected monitor audio output."
                        return
                    }
                }
                logicalDisplayID = nil; logicalOutput = nil
                recovery = MonitorAudioRecoveryPolicy()
                lastExternal = endpoint
                checkRoute()
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        status = "Monitor display returned, but its audio endpoint is not ready. Retry reconnect."
    }

    private func suspend() {
        active = false
        if let processor, !processor.stop() {
            // Keep ownership of a failed HAL teardown; never orphan it or start a second route.
            status = "Core Audio could not retire the audio session. Retrying teardown."
            return
        }
        processor = nil
    }

    var managesCurrentOutput: Bool {
        enabled && selected != nil && AudioOutputInfo.currentDefaultOutput()?.uid == selected?.uid
    }

    func setLevel(_ value: Float) {
        guard enabled, value.isFinite else { return }
        level = min(1, max(0, value))
        processor?.setGain(level)
        // Sliders and keys share recovery, including after the automatic retry budget is exhausted.
        checkRoute(userInitiated: true)
    }

    func handle(_ action: MediaKeyAction, fineStep: Bool) -> Bool {
        guard action.isVolume else { return false }
        // Validate at every key press. Explicitly disabled processing remains disabled.
        guard managesCurrentOutput else { checkRoute(); return false }
        switch action {
        case .volumeUp, .volumeDown: setLevel(level + action.signedDelta(fineStep: fineStep))
        case .muteToggle:
            if level > 0 { priorMuteLevel = level; setLevel(0) }
            else { setLevel(priorMuteLevel > 0 ? priorMuteLevel : 0.5) }
        default: return false
        }
        return true
    }

    private func checkRoute(userInitiated: Bool = false) {
        let current = AudioOutputInfo.currentDefaultOutput()
        let devices = AudioOutputInfo.devices()
        let monitors = devices.compactMap { AudioOutputInfo.snapshot($0) }
            .filter { $0.transport == .hdmi || $0.transport == .displayPort }
        let availableUIDs = Set(monitors.map(\.uid))
        if let current, current.transport == .hdmi || current.transport == .displayPort {
            preferredMonitorUID = current.uid
        }
        if logicalDisplayID == nil,
           let uid = attachPolicy.update(previous: previousMonitorUIDs, available: availableUIDs,
                preferred: preferredMonitorUID, currentUID: current?.uid,
                currentIsBuiltIn: current?.id == AudioOutputInfo.builtInSpeakers() && current != nil,
                now: ProcessInfo.processInfo.systemUptime),
           let endpoint = monitors.first(where: { $0.uid == uid }),
           let actual = AudioOutputInfo.currentDefaultOutput(), actual.id == AudioOutputInfo.builtInSpeakers(),
           AudioOutputInfo.selectOutput(endpoint.id) {
            attachPolicy.selected()
        }
        previousMonitorUIDs = availableUIDs
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
        if let id = logicalDisplayID {
            if reconnectRequested, !reconnecting, ProcessInfo.processInfo.systemUptime >= reconnectRetryAt {
                Task { @MainActor [weak self] in await self?.logicalDisplayReconnected(displayID: id) }
            }
            return
        }
        guard enabled, let selected else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let endpoint = devices.compactMap { AudioOutputInfo.snapshot($0) }.first { $0.uid == selected.uid }
        if userInitiated, processor == nil, now - lastUserRetry >= 1 {
            // A deliberate volume action can re-arm bounded retries without resetting gain/mute.
            recovery.recovered()
            lastUserRetry = now
        }
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
            if ready, let speakerReturnUID, actual?.uid == speakerReturnUID,
               AudioOutputInfo.currentDefaultOutput()?.uid == speakerReturnUID {
                _ = AudioOutputInfo.selectOutput(endpoint.id)
            } else if let actual, actual.uid != speakerReturnUID {
                speakerReturnUID = nil
                speakerReturnDeadline = nil
            }
            status = "Waiting for \(selected.name) to be selected as Sound Output. Previous volume is remembered."
            return
        }
        if endpoint.id != selected.id { suspend() }
        if let processor, !processor.healthy(requireRunning: userInitiated) {
            suspend()
            recovery.failed(now: now)
            status = "Audio stream changed. Rebuilding the monitor audio route…"
            // Continue below so a stable endpoint can recover during this same interaction.
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
                ? "Could not restore monitor audio. Press a volume key or move the volume slider to retry. Normal audio restored."
                : "Waiting for monitor audio to settle: \(error.localizedDescription) Retrying…"
        }
    }
}

/// Only the IO callback touches lastGain. Control state uses a nonblocking read on the audio thread.
final class MonitorAudioProcessor: @unchecked Sendable {
    private struct Control {
        var gain: Float = 1
        var invalid = false
        var stopped = false
        var silentCallbacks = 0
    }
    private let control = OSAllocatedUnfairLock(initialState: Control())
    private var lastInputSampleTime: Float64?
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
    func healthy(requireRunning: Bool = false) -> Bool {
        guard control.withLock({ !$0.invalid && !$0.stopped }) else { return false }
        // A silent/idle tap may legitimately deliver no callbacks. Never destroy it on a
        // callback deadline: doing so repeatedly unmutes the original full-level route.
        // Idle HAL routes can also stop their engine. Check running state when the user
        // requests volume, rather than tearing down an idle route on every timer tick.
        guard aggregate != 0 else { return true } // renderer-only tests have no HAL route
        return deviceFlag(kAudioDevicePropertyDeviceIsAlive) &&
            (!requireRunning || deviceFlag(kAudioDevicePropertyDeviceIsRunning))
    }

    private func deviceFlag(_ selector: AudioObjectPropertySelector) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(aggregate, &address, 0, nil, &size, &value) == noErr && value != 0
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
            try check(AudioDeviceCreateIOProcIDWithBlock(&io, aggregate, nil) { [self] _, input, inputTime, output, _ in
                let timestamp = inputTime.pointee
                render(input: input, output: output,
                       sampleTime: timestamp.mFlags.contains(.sampleTimeValid) ? timestamp.mSampleTime : nil)
            }, "Create audio processor")
            try check(AudioDeviceStart(aggregate, io), "Start audio processor")
        } catch { stop(); throw error }
    }

    func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>,
                sampleTime: Float64? = nil) {
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
        // Silence while retiring a route, or if HAL replays a stale callback after hotplug.
        let state = control.withLockIfAvailable { state -> (Float, Bool) in
            if !validLayout { state.invalid = true }
            if state.stopped { state.silentCallbacks += 1 }
            return (state.gain, state.stopped)
        }
        guard let (target, stopped) = state, !stopped, valid else { return }
        if let sampleTime {
            guard sampleTime.isFinite else { return }
            let previous = lastInputSampleTime
            lastInputSampleTime = sampleTime
            if let previous, sampleTime <= previous { return }
        }
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

    var hasDrained: Bool { control.withLock { $0.silentCallbacks >= 8 } }

    func silence() {
        control.withLock { $0.stopped = true; $0.silentCallbacks = 0 }
    }

    @discardableResult
    func stop() -> Bool {
        // Any in-flight callback must output silence before HAL teardown starts.
        control.withLock { $0.stopped = true }
        if aggregate != 0 {
            if let io {
                guard AudioDeviceStop(aggregate, io) == noErr else { return false }
                guard AudioDeviceDestroyIOProcID(aggregate, io) == noErr else { return false }
            }
            io = nil
            guard AudioHardwareDestroyAggregateDevice(aggregate) == noErr else { return false }
            aggregate = 0
        }
        if #available(macOS 14.2, *), tap != 0 {
            guard AudioHardwareDestroyProcessTap(tap) == noErr else { return false }
            tap = 0
        }
        return true
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
