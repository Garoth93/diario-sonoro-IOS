import Foundation

/// Waveform helpers: the recorder samples the input level every ~50 ms,
/// the clip stores `defaultBins` peaks quantised to bytes.
public enum Waveform {
    public static let defaultBins = 48

    /// Converts an average power in dBFS to a 0…1 level (`floor` dB → 0).
    public static func level(decibels db: Float, floor: Float = -50) -> Float {
        guard db.isFinite else { return 0 }
        if db <= floor { return 0 }
        if db >= 0 { return 1 }
        let linear = (db - floor) / -floor
        // Slight curve: quiet ambiences still show some movement.
        return Float(pow(Double(linear), 1.4))
    }

    /// Resamples to `count` values: the peak of each bucket when shrinking,
    /// linear interpolation when stretching.
    public static func resample(_ values: [Float], to count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard !values.isEmpty else { return Array(repeating: 0, count: count) }
        if values.count == count { return values }
        if values.count > count {
            return (0..<count).map { i in
                let a = i * values.count / count
                let b = max(a + 1, (i + 1) * values.count / count)
                return values[a..<min(b, values.count)].max() ?? 0
            }
        }
        if values.count == 1 { return Array(repeating: values[0], count: count) }
        return (0..<count).map { i in
            let x = Double(i) * Double(values.count - 1) / Double(count - 1)
            let lo = Int(x), hi = min(lo + 1, values.count - 1)
            let t = Float(x - Double(lo))
            return values[lo] * (1 - t) + values[hi] * t
        }
    }

    /// Scales so that the loudest value is 1 (silence stays silence).
    public static func normalize(_ values: [Float]) -> [Float] {
        guard let peak = values.max(), peak > 0.0001 else { return values.map { _ in 0 } }
        return values.map { min(1, max(0, $0 / peak)) }
    }

    public static func quantize(_ values: [Float]) -> [UInt8] {
        values.map { UInt8((min(1, max(0, $0)) * 255).rounded()) }
    }

    public static func dequantize(_ values: [UInt8]) -> [Float] {
        values.map { Float($0) / 255 }
    }

    /// Stored waveform of a clip from the raw meter samples.
    public static func clipWaveform(levels: [Float], bins: Int = defaultBins) -> [UInt8] {
        quantize(normalize(resample(levels, to: bins)))
    }

    /// Joins several waveforms, each taking space proportional to its duration.
    public static func concat(_ parts: [([Float], Double)], bins: Int) -> [Float] {
        let total = parts.reduce(0) { $0 + max(0, $1.1) }
        guard total > 0, bins > 0 else { return Array(repeating: 0, count: max(0, bins)) }
        var out: [Float] = []
        var used = 0
        for (i, part) in parts.enumerated() {
            let share = i == parts.count - 1
                ? bins - used
                : Int((Double(bins) * max(0, part.1) / total).rounded())
            let n = max(0, min(share, bins - used))
            out += resample(part.0, to: n)
            used += n
        }
        if out.count < bins { out += Array(repeating: 0, count: bins - out.count) }
        return out
    }

    /// Fraction of the waveform bars already played.
    public static func playedBars(progress: Double, bars: Int) -> Int {
        Int((min(1, max(0, progress)) * Double(bars)).rounded(.down))
    }
}
