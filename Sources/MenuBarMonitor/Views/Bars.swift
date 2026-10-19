import SwiftUI

/// One thin bar per core, in tones of the CPU's colour by kind of core, slowest first.
struct CoreBars: View {
    var cores: [Double]
    var groups: [CoreGroup]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(cores.indices, id: \.self) { index in
                let shape = RoundedRectangle(cornerRadius: 1.5, style: .continuous)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Usage of each of \(cores.count) cores")
    }

    private func color(forCore index: Int) -> Color {
        let group = groups.firstIndex { $0.range.contains(index) } ?? 0
        return Palette.coreGroup(group)
    }
}

/// Parts of a whole side by side in one thin bar, the rest left as the track.
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
        .frame(height: 6)
    }
}

/// One square per reading in three rows, read like text: oldest top left, newest bottom
/// right. Quiet while macOS had a connection, red when it had none, fainter still
/// before the first reading.
struct ConnectionGrid: View {
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
                            .fill(index < 0 ? Color.primary.opacity(0.06)
                                  : entries[index] ? Color.primary.opacity(0.22)
                                  : Palette.critical)
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
