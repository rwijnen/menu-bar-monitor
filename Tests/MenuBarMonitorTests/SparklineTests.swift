import CoreGraphics
import Testing

@testable import MenuBarMonitor

@Suite("Sparkline geometry")
struct SparklineTests {

    private let rect = CGRect(x: 0, y: 0, width: 100, height: 20)

    private func path(_ values: [Double], capacity: Int = 11, closed: Bool = false) -> CGRect {
        SparklineShape(values: values, maxValue: 100, capacity: capacity, lineWidth: 0,
                       closed: closed)
            .path(in: rect)
            .boundingRect
    }

    @Test("nothing is drawn until there are two readings")
    func needsTwoReadings() {
        let shape = { (values: [Double]) in
            SparklineShape(values: values, maxValue: 100, capacity: 11, lineWidth: 0,
                           closed: false).path(in: rect)
        }
        #expect(shape([]).isEmpty)
        #expect(shape([42]).isEmpty)
        #expect(!shape([42, 43]).isEmpty)
    }

    /// A graph that is still filling up grows leftwards from the right edge, so
    /// the newest reading is always in the same place.
    @Test("the newest reading sits on the right edge")
    func newestOnTheRight() {
        let bounds = path([10, 20, 30])
        #expect(bounds.maxX == 100)
        #expect(bounds.minX == 80)
    }

    @Test("a full history spans the whole width")
    func fullHistory() {
        let bounds = path(Array(repeating: 50, count: 11))
        #expect(bounds.minX == 0)
        #expect(bounds.maxX == 100)
    }

    @Test("values outside the scale are drawn at its edges")
    func clamped() {
        let bounds = path([-50, 500])
        #expect(bounds.minY == 0)
        #expect(bounds.maxY == 20)
    }

    @Test("the filled area closes down to the bottom edge")
    func filledAreaReachesBottom() {
        #expect(path([90, 95], closed: false).maxY < 20)
        #expect(path([90, 95], closed: true).maxY == 20)
    }
}
