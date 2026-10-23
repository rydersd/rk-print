import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import Labeler

struct LibraryTests {
    private func makeLibrary(undo: UndoManager? = nil) throws -> LabelLibrary {
        let container = try ModelContainer(for: LabelLibrary.schema,
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

    // MARK: S9 — every label lives in the library

    private func makeEditor(_ library: LabelLibrary, undo: UndoManager? = nil) -> LabelEditor {
        LabelEditor(undoManager: undo, persistsWorkingLabel: false, library: library)
    }

    /// S9: New Label is in the library before any edit; an edit reaches it after the debounce, without Save,
    /// and the name follows the first line of text.
    @Test func editsSaveWithoutSave() async throws {
        let library = try makeLibrary()
        let editor = makeEditor(library)
        editor.newLabel()
        let id = try #require(editor.libraryID)
        #expect(try library.load(id) == LabelDocument())

        editor.addText()
        editor.setText("SHELF A", for: try #require(editor.selectedID))
        try await Task.sleep(for: LabelEditor.persistDelay * 2)
        #expect(try library.load(id)?.elements.first?.textContent?.text == "SHELF A")
        #expect(try library.name(id) == "SHELF A")
    }

    /// S9: a label renamed in the library keeps its name when its text changes.
    @Test func renamedNameSurvivesEdits() throws {
        let library = try makeLibrary()
        let editor = makeEditor(library)
        editor.newLabel()
        editor.addText()
        let element = try #require(editor.selectedID)
        editor.setText("A", for: element)
        editor.saveNow()
        let id = try #require(editor.libraryID)

        try library.rename(id, to: "Bins")
        editor.setText("B", for: element)
        editor.saveNow()
        #expect(try library.name(id) == "Bins")
        #expect(try library.load(id)?.elements.first?.textContent?.text == "B")
    }

    /// S9 data-loss guard: undo after opening another label never writes the first label into the second.
    @Test func undoAfterOpeningNeverOverwritesOtherLabel() throws {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let library = try makeLibrary(undo: undo)
        let editor = makeEditor(library, undo: undo)
        editor.newLabel()
        editor.addText()
        editor.setText("ONE", for: try #require(editor.selectedID))
        let first = try #require(editor.libraryID)

        editor.newLabel()
        let second = try #require(editor.libraryID)
        if undo.canUndo { undo.undo() }
        editor.saveNow()
        #expect(try library.load(second)?.elements.isEmpty == true)
        #expect(try library.load(first)?.elements.first?.textContent?.text == "ONE")
    }

    // MARK: S10 — label folders

    private func undoable() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }

    @Test func dropOnLabelMakesFolder() throws {
        let library = try makeLibrary()
        let a = try library.create(twoBlockDocument).id
        let b = try library.create(LabelDocument()).id

        try library.drop(b, onLabel: a)

        let folders = try library.folders()
        let folder = try #require(folders.first)
        #expect(folders.count == 1)
        #expect(folder.name == "Folder")
        #expect(Set(try library.labels(inFolder: folder.id).map(\.id)) == [a, b])
        #expect(try library.labels(inFolder: nil).isEmpty)
    }

    @Test func deleteFolderKeepingLabelsIsUndoable() throws {
        let undo = undoable()
        let library = try makeLibrary(undo: undo)
        let a = try library.create(twoBlockDocument).id
        let b = try library.create(LabelDocument()).id
        try library.drop(b, onLabel: a)
        let folder = try #require(try library.folders().first).id

        let deleted = try library.deleteFolder(folder, keepingLabels: true)
        #expect(deleted.isEmpty)
        #expect(try library.folders().isEmpty)
        #expect(Set(try library.labels(inFolder: nil).map(\.id)) == [a, b])

        undo.undo()
        #expect(try library.folders().map(\.id) == [folder])
        #expect(Set(try library.labels(inFolder: folder).map(\.id)) == [a, b])
        #expect(try library.labels(inFolder: nil).isEmpty)
    }

    @Test func deleteFolderAndLabelsIsUndoable() throws {
        let undo = undoable()
        let library = try makeLibrary(undo: undo)
        let a = try library.create(twoBlockDocument).id
        let b = try library.create(LabelDocument()).id
        try library.drop(b, onLabel: a)
        let folder = try #require(try library.folders().first).id

        let deleted = try library.deleteFolder(folder, keepingLabels: false)
        #expect(deleted == [a, b])
        #expect(try library.folders().isEmpty)
        #expect(try library.load(a) == nil)
        #expect(try library.load(b) == nil)

        undo.undo()
        #expect(try library.folders().map(\.id) == [folder])
        #expect(Set(try library.labels(inFolder: folder).map(\.id)) == [a, b])
        #expect(try library.load(a) == twoBlockDocument)
    }

    // MARK: S11 — templates

    @Test func labelFromTemplateLeavesTemplateUnchanged() throws {
        let library = try makeLibrary()
        let template = try library.saveTemplate(twoBlockDocument, name: "Shelf")
        let before = try #require(try library.templates().first { $0.id == template }).documentJSON
        let editor = makeEditor(library)

        editor.newLabel(fromTemplate: template)
        let label = try #require(editor.libraryID)
        #expect(label != template)
        #expect(editor.libraryName == "Shelf")
        #expect(Set(editor.document.elements.map(\.id)).isDisjoint(with: twoBlockDocument.elements.map(\.id)))
        editor.setText("CHANGED", for: editor.document.elements[0].id)
        editor.saveNow()

        #expect(try library.templates().first { $0.id == template }?.documentJSON == before)
        #expect(try library.load(label)?.elements.first?.textContent?.text == "CHANGED")
        #expect(try library.labels(inFolder: nil).map(\.id) == [label])
    }

    @Test func templateDeleteIsUndoable() throws {
        let undo = undoable()
        let library = try makeLibrary(undo: undo)
        let template = try library.saveTemplate(twoBlockDocument, name: "Shelf")

        try library.delete(template)
        #expect(try library.templates().isEmpty)

        undo.undo()
        #expect(try library.templates().map(\.id) == [template])
        #expect(try library.load(template) == twoBlockDocument)
        #expect(try library.labels(inFolder: nil).isEmpty)
    }

    /// Codex review: an edit still waiting on the autosave names the template, not the label's old name.
    @Test func templateTakesNameOfUnsavedEdit() throws {
        let library = try makeLibrary()
        let editor = makeEditor(library)
        editor.newLabel()
        editor.addText()
        editor.setText("BINS", for: try #require(editor.selectedID))

        editor.saveAsTemplate()

        #expect(try library.templates().map(\.name) == ["BINS"])
    }

    // MARK: S16 — label stock colour

    @Test func stockColourRoundTrips() throws {
        let library = try makeLibrary()
        var yellow = twoBlockDocument
        yellow.stock = .yellow
        let id = try library.save(yellow, name: "Yellow")
        #expect(try library.load(id)?.stock == .yellow)

        // A label saved before S16 has no stock key.
        let s15JSON = """
        {"size":{"headMM":50,"feedMM":30,"feedDots":240},"orientation":"headNative","grid":1,"elements":[]}
        """
        let old = try JSONDecoder().decode(LabelDocument.self, from: Data(s15JSON.utf8))
        #expect(old.stock == .white)
    }
}
