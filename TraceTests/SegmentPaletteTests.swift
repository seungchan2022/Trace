import XCTest
@testable import Trace

final class SegmentPaletteTests: XCTestCase {
    func testColorsCycleThroughPalette() {
        let paletteSize = 6
        let first = SegmentPalette.color(at: 0)
        let wrapped = SegmentPalette.color(at: paletteSize)
        XCTAssertEqual(first, wrapped, "팔레트 크기만큼 지나면 순환되어야 함")
    }

    func testDifferentIndicesGiveDifferentColorsWithinOneCycle() {
        let a = SegmentPalette.color(at: 0)
        let b = SegmentPalette.color(at: 1)
        XCTAssertNotEqual(a, b)
    }
}
