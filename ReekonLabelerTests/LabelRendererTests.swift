import CoreGraphics
import Testing
@testable import Labeler

struct LabelRendererTests {
    private func allDots(_ bitmap: Bitmap) -> CGRect { CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height) }

    /// The smallest rect, in dots, holding every black dot.
    private func inkBounds(_ bitmap: Bitmap) -> CGRect? {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width where bitmap[x, y] {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        return maxX < 0 ? nil : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    @Test func blockAtMillimetreOriginLandsOnExpectedDots() {
        let doc = LabelDocument(size: .small, orientation: .headNative, grid: .off, elements: [
            .text("BOLTS", originMM: CGPoint(x: 5, y: 3), widthMM: 30, pointSize: 18),
        ])
        let layout = LayoutEngine.layout(doc.elements[0], in: doc.geometry)
        let bitmap = LabelRenderer.render(doc)

        #expect(bitmap.width == 384)
        #expect(bitmap.height == 240)

        let frame = doc.geometry.dotRect(forMM: layout.frameMM)
        #expect(frame.origin == CGPoint(x: 32, y: 24))

        let inside = bitmap.inkCount(inDots: frame)
        #expect(inside > 0)
        #expect(inside == bitmap.inkCount(inDots: allDots(bitmap)))
    }

    /// S6: one line of text at 90° prints as a tall, narrow run of ink inside its footprint.
    @Test func rotatedBlockPrintsSideways() throws {
        var element = LabelElement.text("BOLTS", originMM: CGPoint(x: 10, y: 1), widthMM: 25, pointSize: 18)
        element.rotation = .quarter
        let doc = LabelDocument(size: .small, orientation: .headNative, grid: .off, elements: [element])
        let bitmap = LabelRenderer.render(doc)
        let footprint = doc.geometry.dotRect(forMM: LayoutEngine.layout(element, in: doc.geometry).frameMM)

        let ink = try #require(inkBounds(bitmap))
        #expect(ink.height > ink.width)
        #expect(bitmap.inkCount(inDots: footprint) == bitmap.inkCount(inDots: allDots(bitmap)))
    }

    /// S7: a flat 60 % grey picture dithers to part ink, and line art cuts it to paper.
    @Test func ditheredGreyIsPartInk() throws {
        var picture = TestPictures.make(width: 100, height: 50) { _, _ in 153 }
        let element = TestPictures.element(picture, x: 5, y: 2, width: 40)
        let doc = LabelDocument(size: .small, orientation: .headNative, grid: .off, elements: [element])
        let frame = doc.geometry.dotRect(forMM: LayoutEngine.layout(element, in: doc.geometry).frameMM)
        let frameDots = Double(Int(frame.width) * Int(frame.height))

        let dithered = Double(LabelRenderer.render(doc).inkCount(inDots: frame)) / frameDots
        #expect(dithered >= 0.25 && dithered <= 0.55, "dithered ink \(dithered)")

        picture.lineArt = true
        var lineArt = doc
        lineArt.elements[0].picture = picture
        #expect(LabelRenderer.render(lineArt).inkCount(inDots: frame) == 0)
    }
}
