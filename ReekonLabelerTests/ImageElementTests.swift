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

    /// S8 (Codex review): the crop screen stops a sliver crop before the picture would print narrower than
    /// 2 mm on the label.
    @Test func sliverCropStopsAtMinimumWidth() throws {
        var picture = TestPictures.make(width: 100, height: 100) { _, _ in 0 }
        let document = LabelDocument(size: .small, orientation: .headNative, grid: .off, elements: [])
        let editor = LabelEditor(document: document, undoManager: nil, persistsWorkingLabel: false)
        let limit = editor.maximumPictureAspect(rotation: .none)

        picture.crop = CropHandle.left.adjust(CGRect(x: 0, y: 0, width: 1, height: 1), by: CGSize(width: 0.97, height: 0),
                                              pixelAspect: 1, maximumAspect: limit)
        #expect(picture.crop.width > PictureContent.minimumCropFraction)
        let element = TestPictures.element(picture, x: 1, y: 1, width: 48)
        let layout = LayoutEngine.layout(element, in: document.geometry)
        #expect(layout.contentSizeMM.width >= LabelElement.minimumWidthMM - 0.01)
    }
}
