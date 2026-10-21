import SwiftUI

/// A ring that fills clockwise from the top, made of one or more coloured segments,
/// with its value written inside. Drawn with shapes, not `Canvas` (see Sparkline).
struct RingGauge: View {
    struct Segment {
        var fraction: Double
        var color: Color
    }

    var segments: [Segment]
    var value: String
    var unit: String?
    var caption: String
    var diameter: CGFloat = 62
    var lineWidth: CGFloat = 6

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: lineWidth)
                ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
                    Circle()
                        .trim(from: arc.start, to: arc.end)
                        .stroke(arc.color, style: StrokeStyle(lineWidth: lineWidth))
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 0) {
                    Text(value)
                        .font(.system(size: diameter > 70 ? 17 : 13, weight: .semibold)
                            .monospacedDigit())
                    if let unit {
                        Text(unit).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: diameter, height: diameter)
            Text(caption)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption): \(value) \(unit ?? "")")
    }

    /// The segments laid end to end, never past a full turn.
    private var arcs: [(start: Double, end: Double, color: Color)] {
        var start = 0.0
        return segments.map { segment in
            let end = min(start + max(segment.fraction, 0), 1)
            defer { start = end }
            return (start, end, segment.color)
        }
    }
}

/// One bar per core, coloured by kind of core, slowest first.
struct CoreBars: View {
    var cores: [Double]
    var groups: [CoreGroup]

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(cores.indices, id: \.self) { index in
                let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
                shape
                    .fill(Color.primary.opacity(0.08))
                    .overlay(alignment: .bottom) {
                        GeometryReader { proxy in
                            Rectangle()
                                .fill(color(forCore: index))
                                .frame(height: proxy.size.height
                                       * min(max(cores[index] / 100, 0), 1))
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                    .clipShape(shape)
            }
        }
        .frame(height: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Usage of each of \(cores.count) cores")
    }

    private func color(forCore index: Int) -> Color {
        let group = groups.firstIndex { $0.range.contains(index) } ?? 0
        return Palette.coreGroup(group)
    }
}
