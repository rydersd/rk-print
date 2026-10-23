import CoreGraphics
import Testing
@testable import Labeler

struct LabelGeometryTests {
    @Test func smallHeadNativeMatchesSDKDots() {
        let g = LabelGeometry(size: .small, orientation: .headNative)
        #expect(g.labelSizeMM == CGSize(width: 50, height: 30))
        #expect(g.printableRect == CGRect(x: 1, y: 0, width: 48, height: 30))
        #expect(g.bitmapWidth == 384)
        #expect(g.bitmapHeight == 240)
    }

    @Test func largeRotatedSwapsAxes() {
        let g = LabelGeometry(size: .large, orientation: .rotated)
        #expect(g.labelSizeMM == CGSize(width: 80, height: 50))
        #expect(g.printableRect == CGRect(x: 0, y: 1, width: 78, height: 48))
        #expect(g.bitmapWidth == 624)
        #expect(g.bitmapHeight == 384)
    }
}
