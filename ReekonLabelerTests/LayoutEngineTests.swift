import CoreGraphics
import Testing
@testable import Labeler

struct LayoutEngineTests {
    private let small = LabelGeometry(size: .small, orientation: .headNative)

    private func block(x: Double = 1, y: Double = 0, width: Double = 20, text: String = "BOLTS", size: Double = 14) -> TextBlock {
        TextBlock(text: text, originMM: CGPoint(x: x, y: y), widthMM: width, pointSize: size)
    }

    @Test func dragPastEdgeStopsAtPrintableEdge() {
        let b = block()
        let origin = LayoutEngine.moved(b, from: b.originMM, by: CGSize(width: 100, height: 0), grid: .one, in: small)
        // Right edge lands exactly on the printable edge: 1 mm margin + 48 mm.
        #expect(origin.x + b.widthMM == 49)
        #expect(small.printableRect.maxX == 49)
    }

    @Test func snappedDragLandsOnGridLine() {
        let b = block(x: 3, y: 2)
        let origin = LayoutEngine.moved(b, from: b.originMM, by: CGSize(width: 2.3, height: 1.4), grid: .one, in: small)
        #expect(origin == CGPoint(x: 5, y: 3))
    }

    @Test func overflowingTextShrinksToFit() {
        let b = block(width: 20, text: "SHELF A BOLTS NUTS WASHERS SCREWS", size: 24)
        let layout = LayoutEngine.layout(b, in: small)
        #expect(layout.effectivePointSize < 24)
        #expect(layout.frameMM.maxY <= small.printableRect.maxY + 0.001)
        #expect(small.printableRect.contains(layout.frameMM.insetBy(dx: 0.001, dy: 0.001)))
    }

    @Test func emptyTextHasLineHeight() {
        let layout = LayoutEngine.layout(block(text: ""), in: small)
        #expect(layout.frameMM.height > 1)
    }

    @Test func normalizeAfterSizeChangeKeepsBlocksInside() {
        var doc = LabelDocument(size: .large, orientation: .headNative)
        doc.blocks = [block(x: 10, y: 70, width: 45, text: "LOW ON THE LABEL")]
        doc.size = .small
        let normalized = LayoutEngine.normalized(doc)
        let layout = LayoutEngine.layout(normalized.blocks[0], in: normalized.geometry)
        #expect(normalized.geometry.printableRect.contains(layout.frameMM.insetBy(dx: 0.001, dy: 0.001)))
    }
}
