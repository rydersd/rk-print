import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import Labeler

struct LibraryTests {
    private func makeLibrary(undo: UndoManager? = nil) throws -> LabelLibrary {
        let container = try ModelContainer(for: SavedLabel.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return LabelLibrary(context: ModelContext(container), undoManager: undo)
    }

    /// Stored, not computed: each element gets a fresh UUID, so the fixture must be built once.
    private let twoBlockDocument = LabelDocument(size: .large, orientation: .rotated, grid: .half, elements: [
        .text("SHELF A", originMM: CGPoint(x: 2, y: 3), widthMM: 40,
              font: FontSpec(family: FontCatalog.monoFamily, face: "Heavy"), pointSize: 22, alignment: .center),
        .text("M6 bolts\n40 mm", originMM: CGPoint(x: 10, y: 20), widthMM: 30, pointSize: 12, alignment: .right),
    ])

    @Test func saveThenReopenIsIdentical() throws {
        let library = try makeLibrary()
        let id = try library.save(twoBlockDocument, name: "Garage shelf")
        #expect(try library.load(id) == twoBlockDocument)
    }

    @Test func deleteIsUndoable() throws {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let library = try makeLibrary(undo: undo)
        let id = try library.save(twoBlockDocument, name: "Garage shelf")

        try library.delete(id)
        #expect(try library.load(id) == nil)

        undo.undo()
        #expect(try library.load(id) == twoBlockDocument)
    }

    /// S6: a label saved by the S4 build (text fields at the top level, no rotation or group) still opens.
    @Test func labelSavedBeforeRotationStillOpens() throws {
        let s4JSON = """
        {"size":{"headMM":50,"feedMM":30,"feedDots":240},"orientation":"headNative","grid":1,
         "blocks":[{"id":"8C1F2C4E-6B1D-4F0A-9C55-0E2B7D1A3F10","text":"BOLTS","originMM":[2,3],"widthMM":40,
                    "font":{"family":"System","face":"Bold"},"pointSize":22,"alignment":"center"}]}
        """
        let doc = try JSONDecoder().decode(LabelDocument.self, from: Data(s4JSON.utf8))
        let element = try #require(doc.elements.first)
        #expect(doc.elements.count == 1)
        #expect(element.textContent == TextContent(text: "BOLTS", font: FontSpec(family: "System", face: "Bold"),
                                                   pointSize: 22, alignment: .center))
        #expect(element.originMM == CGPoint(x: 2, y: 3))
        #expect(element.rotation == .none)
        #expect(element.groupID == nil)
    }

    /// S7: a picture and a text block save and reopen unchanged, pixels included.
    @Test func labelWithPictureRoundTrips() throws {
        let picture = TestPictures.make(width: 30, height: 20) { x, y in UInt8((x * 8 + y * 3) % 256) }
        var pictureElement = TestPictures.element(picture, x: 3, y: 4, width: 20)
        pictureElement.rotation = .half
        let doc = LabelDocument(elements: [pictureElement, twoBlockDocument.elements[0]])
        let library = try makeLibrary()
        let id = try library.save(doc, name: "With picture")

        let reopened = try #require(try library.load(id))
        #expect(reopened == doc)
        #expect(reopened.elements[0].picture?.pngData == picture.pngData)
    }
}
