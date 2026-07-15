// Decode the extracted mono/8kHz WAV into a flat Float sample buffer for
// rendering. AVAudioFile handles WAV natively — no hand-rolled RIFF parsing.

import AVFoundation

struct WaveformAudio {
    let samples: [Float] // mono, [-1, 1]
    let sampleRate: Double
    var duration: Double { sampleRate > 0 ? Double(samples.count) / sampleRate : 0 }

    static func load(_ url: URL) throws -> WaveformAudio {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try file.read(into: buffer)
        let frameCount = Int(buffer.frameLength)
        guard let channelData = buffer.floatChannelData else {
            return WaveformAudio(samples: [], sampleRate: format.sampleRate)
        }
        // Already mono from extraction, but average channels defensively if not.
        let channels = Int(format.channelCount)
        var mono = [Float](repeating: 0, count: frameCount)
        if channels == 1 {
            mono.withUnsafeMutableBufferPointer { dst in
                dst.baseAddress!.update(from: channelData[0], count: frameCount)
            }
        } else {
            for i in 0..<frameCount {
                var sum: Float = 0
                for c in 0..<channels { sum += channelData[c][i] }
                mono[i] = sum / Float(channels)
            }
        }
        return WaveformAudio(samples: mono, sampleRate: format.sampleRate)
    }
}
