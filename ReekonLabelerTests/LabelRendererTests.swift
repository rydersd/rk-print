import CoreGraphics
import Testing
@testable import Labeler

struct LabelRendererTests {
    @Test func blockAtMillimetreOriginLandsOnExpectedDots() {
        var doc = LabelDocument(size: .small, orientation: .headNative, grid: .off)
        doc.blocks = [TextBlock(text: "BOLTS", originMM: CGPoint(x: 5, y: 3), widthMM: 30, pointSize: 18)]
        let layout = LayoutEngine.layout(doc.blocks[0], in: doc.geometry)
        let bitmap = LabelRenderer.render(doc)

        #expect(bitmap.width == 384)
        #expect(bitmap.height == 240)

        let frame = doc.geometry.dotRect(forMM: layout.frameMM)
        #expect(frame.origin == CGPoint(x: 32, y: 24))

        let inside = bitmap.inkCount(inDots: frame)
        #expect(inside > 0)
        #expect(inside == bitmap.inkCount(inDots: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height)))
    }
}
