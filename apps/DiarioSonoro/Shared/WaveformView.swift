import SwiftUI
import SonoroCore

/// Rounded vertical bars from a stored waveform (0…255 values).
/// Bars before `progress` use `played`, the others `color`.
struct WaveformView: View {
    let samples: [UInt8]
    var color: Color
    var played: Color? = nil
    var progress: Double = 0
    var barCount: Int? = nil
    var spacing: CGFloat = 2
    var minimumHeight: CGFloat = 0.08

    var body: some View {
        GeometryReader { geo in
            let values = bars(for: geo.size.width)
            let playedBars = Waveform.playedBars(progress: progress, bars: values.count)
            let barWidth = max(1, (geo.size.width - spacing * CGFloat(max(0, values.count - 1))) / CGFloat(max(1, values.count)))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(values.indices, id: \.self) { i in
                    Capsule(style: .continuous)
                        .fill(i < playedBars ? (played ?? color) : color)
                        .frame(width: barWidth, height: max(barWidth, geo.size.height * CGFloat(max(minimumHeight, Double(values[i])))))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .accessibilityHidden(true)
    }

    private func bars(for width: CGFloat) -> [Float] {
        let count = barCount ?? max(8, Int(width / 5))
        let base = samples.isEmpty ? [UInt8](repeating: 30, count: 8) : samples
        return Waveform.resample(Waveform.dequantize(base), to: count)
    }
}
