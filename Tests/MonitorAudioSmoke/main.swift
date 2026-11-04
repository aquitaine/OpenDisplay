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
    precondition(processor.healthy(after: 10))
    processor.stop(); processor.stop()
}
let processor = MonitorAudioProcessor()
let stereo = Buffers(channels: [2], frames: 4, fill: 1)
let mismatch = Buffers(channels: [1], frames: 4, fill: 5)
processor.render(input: UnsafePointer(stereo.pointer), output: mismatch.pointer)
precondition(!processor.healthy(after: 0))
near(mismatch.samples[0][0], 0)
precondition(!MonitorAudioProcessor().healthy(after: 10))
precondition(MonitorAudioRoutePolicy.shouldFallback(enabled: true, missingUID: "monitor", currentUID: nil))
precondition(MonitorAudioRoutePolicy.shouldFallback(enabled: true, missingUID: "monitor", currentUID: "monitor"))
for current in ["headphones", "usb", "bluetooth", "other-monitor", "speakers"] {
    precondition(!MonitorAudioRoutePolicy.shouldFallback(enabled: true, missingUID: "monitor", currentUID: current))
}
precondition(!MonitorAudioRoutePolicy.shouldFallback(enabled: false, missingUID: "monitor", currentUID: nil))
print("PASS: interleaved/planar stereo, gain ramp, mute, finite gain, no boost, invalid layout, callback watchdog, route policy, repeated teardown")
