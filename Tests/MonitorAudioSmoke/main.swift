import CoreAudio
import Foundation

final class Buffers {
    let raw: UnsafeMutableRawPointer
    let pointer: UnsafeMutablePointer<AudioBufferList>
    let samples: [UnsafeMutablePointer<Float>]
    let sampleCount: Int
    init(channels: [UInt32], frames: Int, fill: Float) {
        sampleCount = frames
        raw = .allocate(byteCount: MemoryLayout<AudioBufferList>.size + (channels.count - 1) * MemoryLayout<AudioBuffer>.size,
                        alignment: MemoryLayout<AudioBufferList>.alignment)
        pointer = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        pointer.pointee.mNumberBuffers = UInt32(channels.count)
        samples = channels.map { channel in
            let p = UnsafeMutablePointer<Float>.allocate(capacity: frames * Int(channel))
            p.initialize(repeating: fill, count: frames * Int(channel))
            return p
        }
        let list = UnsafeMutableAudioBufferListPointer(pointer)
        for i in channels.indices {
            list[i] = AudioBuffer(mNumberChannels: channels[i], mDataByteSize: UInt32(frames * Int(channels[i]) * 4), mData: samples[i])
        }
    }
    deinit { samples.forEach { $0.deallocate() }; raw.deallocate() }
}

func near(_ a: Float, _ b: Float) { precondition(abs(a - b) < 0.00001, "\(a) != \(b)") }
for channels: [UInt32] in [[2], [1, 1]] {
    let processor = MonitorAudioProcessor()
    let input = Buffers(channels: channels, frames: 4, fill: 1)
    let output = Buffers(channels: channels, frames: 4, fill: -1)
    processor.setGain(0.5)
    processor.render(input: UnsafePointer(input.pointer), output: output.pointer)
    for b in channels.indices {
        for frame in 0..<4 { for channel in 0..<Int(channels[b]) {
            near(output.samples[b][frame * Int(channels[b]) + channel], 1 - Float(frame + 1) * 0.125)
        }}
    }
    processor.render(input: UnsafePointer(input.pointer), output: output.pointer)
    near(output.samples[0][0], 0.5)
    processor.setGain(0)
    processor.render(input: UnsafePointer(input.pointer), output: output.pointer)
    near(output.samples[0][3 * Int(channels[0])], 0)
    processor.setGain(.nan) // ignored, never contaminates PCM
    processor.render(input: UnsafePointer(input.pointer), output: output.pointer)
    near(output.samples[0][0], 0)
    processor.setGain(8) // never amplifies
    processor.render(input: UnsafePointer(input.pointer), output: output.pointer)
    near(output.samples[0][3 * Int(channels[0])], 1)
    precondition(processor.healthy())
    processor.stop(); processor.stop()
}
let processor = MonitorAudioProcessor()
let stereo = Buffers(channels: [2], frames: 4, fill: 1)
let mismatch = Buffers(channels: [1], frames: 4, fill: 5)
processor.render(input: UnsafePointer(stereo.pointer), output: mismatch.pointer)
precondition(!processor.healthy())
near(mismatch.samples[0][0], 0)
// No callback is normal while idle; it must not tear down the audio route.
precondition(MonitorAudioProcessor().healthy())
var recovery = MonitorAudioRecoveryPolicy()
precondition(!recovery.ready(deviceID: 12, now: 0))
precondition(recovery.ready(deviceID: 12, now: 1))
for i in 0..<5 { recovery.failed(now: Double(i + 2)) }
precondition(!recovery.ready(deviceID: 12, now: 100))
recovery.recovered() // explicit volume action re-arms an exhausted retry budget
precondition(recovery.ready(deviceID: 12, now: 101))
precondition(!recovery.ready(deviceID: nil, now: 102))
precondition(!recovery.ready(deviceID: 13, now: 103))
precondition(recovery.ready(deviceID: 13, now: 104))
precondition(MonitorAudioRoutePolicy.shouldFallback(enabled: true, missingUID: "monitor", currentUID: nil))
precondition(MonitorAudioRoutePolicy.shouldFallback(enabled: true, missingUID: "monitor", currentUID: "monitor"))
for current in ["headphones", "usb", "bluetooth", "other-monitor", "speakers"] {
    precondition(!MonitorAudioRoutePolicy.shouldFallback(enabled: true, missingUID: "monitor", currentUID: current))
}
precondition(!MonitorAudioRoutePolicy.shouldFallback(enabled: false, missingUID: "monitor", currentUID: nil))
print("PASS: interleaved/planar stereo, gain ramp, mute, finite gain, no boost, invalid layout, idle without callbacks, invalid-layout detection, retry rearming, reconnect, route policy, repeated teardown")

let staleProcessor = MonitorAudioProcessor()
let staleInput = Buffers(channels: [2], frames: 4, fill: 1)
let staleOutput = Buffers(channels: [2], frames: 4, fill: -1)
staleProcessor.render(input: UnsafePointer(staleInput.pointer), output: staleOutput.pointer, sampleTime: 100)
near(staleOutput.samples[0][0], 1)
staleProcessor.render(input: UnsafePointer(staleInput.pointer), output: staleOutput.pointer, sampleTime: 100)
near(staleOutput.samples[0][0], 0)
staleProcessor.render(input: UnsafePointer(staleInput.pointer), output: staleOutput.pointer, sampleTime: 104)
near(staleOutput.samples[0][0], 1)
staleProcessor.stop()
staleProcessor.render(input: UnsafePointer(staleInput.pointer), output: staleOutput.pointer, sampleTime: 108)
near(staleOutput.samples[0][0], 0)
print("PASS: duplicate input timestamp is silenced; retired routes cannot replay audio")

let draining = MonitorAudioProcessor()
draining.render(input: UnsafePointer(staleInput.pointer), output: staleOutput.pointer)
near(staleOutput.samples[0][0], 1)
draining.silence() // drain HAL before removing the display, without waiting for teardown
precondition(!draining.hasDrained)
for index in 0..<8 {
    draining.render(input: UnsafePointer(staleInput.pointer), output: staleOutput.pointer)
    near(staleOutput.samples[0][0], 0)
    precondition(draining.hasDrained == (index == 7))
}
precondition(!draining.healthy())
draining.stop()
print("PASS: quiescing clears queued output before device teardown")

var attach = MonitorAudioAttachPolicy()
precondition(attach.update(previous: [], available: ["monitor"], preferred: nil, currentUID: nil, currentIsBuiltIn: false, now: 0) == nil)
precondition(attach.update(previous: ["monitor"], available: ["monitor"], preferred: nil, currentUID: "speakers", currentIsBuiltIn: true, now: 4) == "monitor")
attach.selected()
precondition(attach.pendingUID == nil)
_ = attach.update(previous: [], available: ["monitor"], preferred: nil, currentUID: "headphones", currentIsBuiltIn: false, now: 5)
precondition(attach.pendingUID == nil)
precondition(attach.update(previous: [], available: ["a", "b"], preferred: nil, currentUID: "speakers", currentIsBuiltIn: true, now: 8) == nil)
print("PASS: delayed speaker fallback, manual headphone preservation, ambiguous attach, successful return")
