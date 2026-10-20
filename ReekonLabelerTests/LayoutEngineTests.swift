import CoreGraphics
import Testing
@testable import Labeler

struct LayoutEngineTests {
    private let small = LabelGeometry(size: .small, orientation: .headNative)

    private func block(x: Double = 1, y: Double = 0, width: Double = 20, text: String = "BOLTS",
                       size: Double = 14) -> LabelElement {
        .text(text, originMM: CGPoint(x: x, y: y), widthMM: width, pointSize: size)
    }

    private func frame(_ element: LabelElement) -> CGRect { LayoutEngine.layout(element, in: small).frameMM }

    @Test func dragPastEdgeStopsAtPrintableEdge() {
        let b = block()
        let delta = LayoutEngine.movedDelta(of: [frame(b)], by: CGSize(width: 100, height: 0), grid: .one, in: small)
        // Right edge lands exactly on the printable edge: 1 mm margin + 48 mm.
        #expect(b.originMM.x + delta.width + b.widthMM == 49)
        #expect(small.printableRect.maxX == 49)
    }

    @Test func snappedDragLandsOnGridLine() {
        let b = block(x: 3, y: 2)
        let delta = LayoutEngine.movedDelta(of: [frame(b)], by: CGSize(width: 2.3, height: 1.4), grid: .one, in: small)
        #expect(delta == CGSize(width: 2, height: 1))
    }

    @Test func overflowingTextShrinksToFit() {
        let b = block(width: 20, text: "SHELF A BOLTS NUTS WASHERS SCREWS", size: 24)
        let layout = LayoutEngine.layout(b, in: small)
        #expect(layout.effectivePointSize < 24)
        #expect(layout.frameMM.maxY <= small.printableRect.maxY + 0.001)
        #expect(small.printableRect.contains(layout.frameMM.insetBy(dx: 0.001, dy: 0.001)))
    }

    @Test func emptyTextHasLineHeight() {
        #expect(frame(block(text: "")).height > 1)
    }

    @Test func normalizeAfterSizeChangeKeepsBlocksInside() {
        var doc = LabelDocument(size: .large, orientation: .headNative)
        doc.elements = [block(x: 10, y: 70, width: 45, text: "LOW ON THE LABEL")]
        doc.size = .small
        let normalized = LayoutEngine.normalized(doc)
        let layout = LayoutEngine.layout(normalized.elements[0], in: normalized.geometry)
        #expect(normalized.geometry.printableRect.contains(layout.frameMM.insetBy(dx: 0.001, dy: 0.001)))
    }

    /// S6: a wide block against the right edge, turned 90°, still has its footprint inside.
    @Test func rotatingNearEdgeStaysInside() throws {
        let wide = block(x: 9, y: 4, width: 40, text: "SHELF A")
        let editor = LabelEditor(document: LabelDocument(elements: [wide]), persistsWorkingLabel: false)
        editor.tap(wide.id)
        editor.rotateSelection()

        let layout = try #require(editor.layouts[wide.id])
        #expect(editor.document.element(wide.id)?.rotation == .quarter)
        #expect(layout.frameMM.height > layout.frameMM.width)
        #expect(small.printableRect.contains(layout.frameMM.insetBy(dx: 0.001, dy: 0.001)))
    }

    /// S7: a 2:1 picture scaled past the right edge stops at the printable edge and stays 2:1.
    @Test func pictureKeepsAspectWhenClamped() {
        let picture = TestPictures.make(width: 200, height: 100) { _, _ in 0 }
        let layout = LayoutEngine.layout(TestPictures.element(picture, x: 20, y: 0, width: 100), in: small)
        #expect(layout.frameMM.maxX == small.printableRect.maxX)
        #expect(abs(layout.frameMM.width / layout.frameMM.height - 2) < 0.0001)
    }
}
