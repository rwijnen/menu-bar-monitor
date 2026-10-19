import SwiftUI

/// A line graph whose newest value sits on the right edge. Until `capacity`
/// readings exist, the line starts part-way across and grows leftwards.
///
/// Built from shapes rather than `Canvas`: Canvas brings up Metal rendering,
/// which costs about 75 MB of GPU memory for a menu bar item.
struct Sparkline: View {
    var values: [Double]
    var maxValue: Double
    var capacity: Int
    var color: Color
    var lineWidth: CGFloat = 1.5
    var filled = true

    var body: some View {
        let series = Array(values.suffix(capacity))
        ZStack {
            if filled {
                SparklineShape(values: series, maxValue: maxValue, capacity: capacity,
                               lineWidth: lineWidth, closed: true)
                    .fill(color.opacity(0.18))
            }
            SparklineShape(values: series, maxValue: maxValue, capacity: capacity,
                           lineWidth: lineWidth, closed: false)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round,
                                                  lineJoin: .round))
        }
    }
}

struct SparklineShape: Shape {
    let values: [Double]
    let maxValue: Double
    let capacity: Int
    let lineWidth: CGFloat
    /// Closes the line down to the bottom edge, for the filled area.
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1, maxValue > 0 else { return path }
        let step = rect.width / CGFloat(max(capacity - 1, 1))
        let usableHeight = rect.height - lineWidth
        let points = values.enumerated().map { index, value in
            CGPoint(x: rect.maxX - CGFloat(values.count - 1 - index) * step,
                    y: rect.maxY - lineWidth / 2
                        - CGFloat(min(max(value / maxValue, 0), 1)) * usableHeight)
        }
        path.addLines(points)
        if closed, let first = points.first, let last = points.last {
            path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
            path.addLine(to: CGPoint(x: first.x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

/// A vertical level meter that fills from the bottom.
struct MiniBar: View {
    var fraction: Double
    var color: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        shape
            .fill(Color.primary.opacity(0.2))
            .overlay(alignment: .bottom) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(color)
                        .frame(height: proxy.size.height * min(max(fraction, 0), 1))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .clipShape(shape)
            .frame(width: 6, height: 16)
    }
}

/// A horizontal usage bar, used for memory in the dropdown.
struct UsageBar: View {
    var fraction: Double
    var color: Color

    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(0.12))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 6)
    }
}
