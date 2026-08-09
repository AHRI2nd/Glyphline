// Spectrogram: an alternative view of the same decoded audio WaveformAudio
// already holds, showing frequency content over time instead of amplitude —
// finds a word's onset under background music/noise far more precisely than
// the waveform can, since a spoken transient stands out as a bright vertical
// edge across frequencies even when it's invisible in the amplitude trace.
//
// Computed with Accelerate's vDSP FFT (Apple's own numerically-vetted
// implementation — not hand-rolled) as a Short-Time Fourier Transform: the
// signal is cut into overlapping, Hann-windowed frames, each FFT'd to a
// magnitude spectrum, log-scaled to dB, and the whole grid rendered ONCE to a
// bitmap. That bitmap is then drawn scaled into the current zoom/scroll
// viewport like a texture (WaveformDrawView), rather than re-running the FFT
// on every scroll or zoom change — the audio itself doesn't change, so
// there's nothing to recompute.

import Accelerate
import AppKit

enum SpectrogramRenderer {
    /// Time resolution the bitmap is rendered at — independent of the
    /// waveform's live px/s zoom, which the CGImage is simply stretched to
    /// fit. 100px/s gives a smooth image at any zoom level actually used.
    static let renderPxPerSec: Double = 100
    static let imageHeight = 256

    private static let fftSize = 1024 // frequency resolution (513 output bins)
    private static let hopSize = 256  // 4x overlap between frames

    /// Renders the full spectrogram for `audio` as a bitmap `imageHeight`
    /// pixels tall and `duration × renderPxPerSec` pixels wide (low frequency
    /// at the bottom, matching how a waveform's amplitude reads bottom-up).
    /// Runs the FFT off the main actor; call with `await` from a Task.
    static func render(_ audio: WaveformAudio) -> CGImage? {
        guard audio.sampleRate > 0, !audio.samples.isEmpty else { return nil }
        let width = max(1, Int(audio.duration * renderPxPerSec))
        let samplesPerColumn = audio.sampleRate / renderPxPerSec

        let log2n = vDSP_Length(log2(Double(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        var pixels = [UInt8](repeating: 0, count: width * imageHeight * 4) // RGBA
        let binCount = fftSize / 2

        var realp = [Float](repeating: 0, count: binCount)
        var imagp = [Float](repeating: 0, count: binCount)
        var magnitudes = [Float](repeating: 0, count: binCount)

        for col in 0..<width {
            let centerSample = Int(Double(col) * samplesPerColumn)
            let start = centerSample - fftSize / 2
            var frame = [Float](repeating: 0, count: fftSize)
            for i in 0..<fftSize {
                let s = start + i
                guard s >= 0, s < audio.samples.count else { continue }
                frame[i] = audio.samples[s] * window[i]
            }

            realp.withUnsafeMutableBufferPointer { rp in
                imagp.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    frame.withUnsafeBufferPointer { fp in
                        fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: binCount) { complexPtr in
                            vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(binCount))
                        }
                    }
                    vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                    vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(binCount))
                }
            }

            // dB scale, clamped to a fixed floor so silence renders as flat
            // black rather than amplifying FFT noise into visible speckle.
            var dbFloor: Float = -80
            var one: Float = 1
            vDSP_vdbcon(magnitudes, 1, &one, &magnitudes, 1, vDSP_Length(binCount), 1)
            vDSP_vclip(magnitudes, 1, &dbFloor, [Float(0)], &magnitudes, 1, vDSP_Length(binCount))

            for row in 0..<imageHeight {
                // row 0 = bottom = low frequency, matching the waveform's
                // bottom-up amplitude convention.
                let bin = min(binCount - 1, row * binCount / imageHeight)
                let db = magnitudes[bin]
                let t = max(0, min(1, (db - dbFloor) / -dbFloor))
                let color = heatColor(t)
                let y = imageHeight - 1 - row
                let idx = (y * width + col) * 4
                pixels[idx] = color.r; pixels[idx + 1] = color.g; pixels[idx + 2] = color.b; pixels[idx + 3] = 255
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width, height: imageHeight, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    /// Dark→amber heat gradient matching the app's signal color, rather than
    /// a generic rainbow — quiet stays near-black, loud reads as the same
    /// amber the rest of the timing UI already uses for "this is the thing to
    /// look at."
    private static func heatColor(_ t: Float) -> (r: UInt8, g: UInt8, b: UInt8) {
        let stops: [(Float, r: Float, g: Float, b: Float)] = [
            (0.0, 0.04, 0.04, 0.07),
            (0.4, 0.15, 0.08, 0.25),
            (0.7, 0.75, 0.35, 0.05),
            (1.0, 1.0, 0.85, 0.4),
        ]
        var lo = stops[0]
        var hi = stops[stops.count - 1]
        for i in 0..<stops.count - 1 where t >= stops[i].0 && t <= stops[i + 1].0 {
            lo = stops[i]; hi = stops[i + 1]
            break
        }
        let span = hi.0 - lo.0
        let localT = span > 0 ? (t - lo.0) / span : 0
        func lerp(_ a: Float, _ b: Float) -> UInt8 { UInt8(max(0, min(255, (a + (b - a) * localT) * 255))) }
        return (lerp(lo.r, hi.r), lerp(lo.g, hi.g), lerp(lo.b, hi.b))
    }
}
