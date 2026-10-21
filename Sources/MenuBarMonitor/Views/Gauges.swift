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

/// Memory pressure as a dial: green, amber and red bands across a half circle, and a
/// needle in the band macOS reports.
struct PressureGauge: View {
    var pressure: MemoryPressure
    var width: CGFloat = 88
    var lineWidth: CGFloat = 7

    private static let bands: [(from: Double, to: Double, color: Color)] = [
        (0, 1.0 / 3, Palette.normal),
        (1.0 / 3, 2.0 / 3, Palette.warning),
        (2.0 / 3, 1, Palette.critical),
    ]

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                ForEach(Array(Self.bands.enumerated()), id: \.offset) { _, band in
                    // A circle's trim runs clockwise from three o'clock, so its top half
                    // is 0.5 to 1, left to right.
                    // Inset by half the line, so the band stays inside the clipped frame.
                    Circle()
                        .inset(by: lineWidth / 2)
                        .trim(from: 0.5 + band.from / 2, to: 0.5 + band.to / 2)
                        .stroke(band.color, style: StrokeStyle(lineWidth: lineWidth))
                }
                Needle(fraction: pressure.gaugeFraction)
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                Circle()
                    .fill(Color.primary)
                    .frame(width: 7, height: 7)
            }
            .frame(width: width, height: width)
            // Only the top half is drawn; the lower half's space is given back.
            .frame(height: width / 2 + lineWidth, alignment: .top)
            .clipped()

            Text(pressure.title)
                .font(.system(size: 13, weight: .semibold))
            Text("Pressure")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Memory pressure: \(pressure.title)")
    }

    private struct Needle: Shape {
        var fraction: Double

        func path(in rect: CGRect) -> Path {
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            let length = rect.width / 2 * 0.72
            // 0 points left, 1 points right, through the top; screen y grows downwards.
            let angle = Double.pi * (1 - min(max(fraction, 0), 1))
            var path = Path()
            path.move(to: centre)
            path.addLine(to: CGPoint(x: centre.x + length * cos(angle),
                                     y: centre.y - length * sin(angle)))
            return path
        }
    }
}

/// Parts of a whole side by side in one bar, the rest left as the track.
struct StackedBar: View {
    struct Part {
        var fraction: Double
        var color: Color
    }

    var parts: [Part]

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Rectangle()
                        .fill(part.color)
                        .frame(width: proxy.size.width * min(max(part.fraction, 0), 1))
                }
                Spacer(minLength: 0)
            }
        }
        .background(Color.primary.opacity(0.12))
        .clipShape(Capsule())
        .frame(height: 8)
    }
}

/// Upload above the line and download below it, each scaled to its own peak, with the
/// peaks written in the corners — so a large download does not flatten the upload.
struct MirroredGraph: View {
    var up: [Double]
    var down: [Double]
    var capacity: Int

    var body: some View {
        let upPeak = up.suffix(capacity).max() ?? 0
        let downPeak = down.suffix(capacity).max() ?? 0
        VStack(spacing: 0) {
            Sparkline(values: up, maxValue: max(upPeak, 10_000) * 1.1, capacity: capacity,
                      color: Palette.upload, lineWidth: 1.2)
            Rectangle().fill(Color.primary.opacity(0.2)).frame(height: 0.5)
            Sparkline(values: down, maxValue: max(downPeak, 10_000) * 1.1, capacity: capacity,
                      color: Palette.download, lineWidth: 1.2)
                .scaleEffect(x: 1, y: -1)
        }
        .overlay(alignment: .topLeading) { peakLabel(upPeak) }
        .overlay(alignment: .bottomLeading) { peakLabel(downPeak) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Network history: upload above, download below")
    }

    private func peakLabel(_ bytesPerSecond: Double) -> some View {
        Text(Format.rate(bytesPerSecond))
            .font(.system(size: 9).monospacedDigit())
            .foregroundStyle(.secondary)
    }
}

/// One square per reading, newest last: green when macOS had a connection, red when it
/// had none, grey before the first reading.
struct ConnectivityGrid: View {
    var entries: [Bool]
    var capacity: Int
    var rows = 3

    var body: some View {
        let columns = capacity / rows
        let offset = capacity - entries.count
        VStack(spacing: 2) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column - offset
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(index < 0 ? Color.primary.opacity(0.1)
                                  : entries[index] ? Palette.normal : Palette.critical)
                            .frame(height: 7)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Connected at \(entries.filter { $0 }.count) of the last "
                            + "\(entries.count) readings")
    }
}
