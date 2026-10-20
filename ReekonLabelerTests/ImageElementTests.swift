import CoreGraphics
import Testing
@testable import Labeler

struct ImageElementTests {
    /// S8: cropping a half-black, half-white square to its black half prints solid black, twice as tall as wide.
    @Test func cropPrintsOnlyCroppedPart() throws {
        var picture = TestPictures.make(width: 100, height: 100) { x, _ in x < 50 ? 0 : 255 }
        let uncropped = TestPictures.element(picture, x: 5, y: 2, width: 10)
        let geometry = LabelGeometry(size: .small, orientation: .headNative)
        let uncroppedFrame = LayoutEngine.layout(uncropped, in: geometry).frameMM

        picture.crop = CGRect(x: 0, y: 0, width: 0.5, height: 1)
        var cropped = uncropped
        cropped.picture = picture
        let doc = LabelDocument(size: .small, orientation: .headNative, grid: .off, elements: [cropped])
        let frameMM = LayoutEngine.layout(cropped, in: geometry).frameMM
        #expect(frameMM.height / frameMM.width == 2 * uncroppedFrame.height / uncroppedFrame.width)

        let frame = geometry.dotRect(forMM: frameMM)
        let bitmap = LabelRenderer.render(doc)
        #expect(bitmap.inkCount(inDots: frame) == Int(frame.width) * Int(frame.height))
    }
}
