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

    /// Stored, not computed: each `TextBlock` gets a fresh UUID, so the fixture must be built once.
    private let twoBlockDocument: LabelDocument = {
        var doc = LabelDocument(size: .large, orientation: .rotated, grid: .half)
        doc.blocks = [
            TextBlock(text: "SHELF A", originMM: CGPoint(x: 2, y: 3), widthMM: 40,
                      font: FontSpec(family: FontCatalog.monoFamily, face: "Heavy"), pointSize: 22, alignment: .center),
            TextBlock(text: "M6 bolts\n40 mm", originMM: CGPoint(x: 10, y: 20), widthMM: 30, pointSize: 12, alignment: .right),
        ]
        return doc
    }()

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
}
