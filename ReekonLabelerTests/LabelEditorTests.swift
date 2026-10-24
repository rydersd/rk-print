import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import Labeler

struct LabelEditorTests {
    private func makeUndo() -> UndoManager {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return undo
    }

    @Test func undoRestoresPositionAfterClampedDrag() throws {
        let undo = makeUndo()
        let editor = LabelEditor(document: LabelDocument(), undoManager: undo, persistsWorkingLabel: false)
        editor.addText()
        let id = try #require(editor.selectedID)
        editor.setText("BOLTS", for: id)
        editor.beginGesture()
        editor.resizeElement(id, deltaMM: -30)
        editor.endGesture(action: "Resize")
        let original = try #require(editor.document.element(id)).originMM

        editor.beginGesture()
        editor.moveSelection(grabbing: id, translationMM: CGSize(width: 100, height: 100))
        editor.endGesture(action: "Move")
        #expect(editor.document.element(id)!.originMM != original)

        undo.undo()
        #expect(editor.document.element(id)!.originMM == original)
    }

    @Test func addingBlocksKeepsEachInsideTheLabel() {
        let editor = LabelEditor(document: LabelDocument(), undoManager: nil, persistsWorkingLabel: false)
        for _ in 0..<6 { editor.addText() }
        let printable = editor.document.geometry.printableRect
        for element in editor.document.elements {
            let frame = editor.layouts[element.id]!.frameMM
            #expect(printable.contains(frame.insetBy(dx: 0.001, dy: 0.001)))
        }
    }

    /// Two 10 mm blocks with a 10 mm gap, grouped in Select mode.
    private func groupedPair(undo: UndoManager? = nil) -> (LabelEditor, LabelElement, LabelElement) {
        let left = LabelElement.text("A", originMM: CGPoint(x: 1, y: 2), widthMM: 10)
        let right = LabelElement.text("B", originMM: CGPoint(x: 21, y: 2), widthMM: 10)
        let editor = LabelEditor(document: LabelDocument(grid: .one, elements: [left, right]), undoManager: undo,
                                 persistsWorkingLabel: false)
        editor.setTool(.move)
        editor.tap(left.id)
        editor.tap(right.id)
        editor.group()
        editor.setTool(.type)
        return (editor, left, right)
    }

    /// S5: a group drags as one, keeps its spacing, and stops when its outer edge meets the printable edge.
    @Test func groupMovesAsOneAndStopsAtEdge() throws {
        let (editor, left, right) = groupedPair()
        editor.clearSelection()
        editor.tap(left.id)
        #expect(editor.selection == [left.id, right.id])

        editor.beginGesture()
        editor.moveSelection(grabbing: left.id, translationMM: CGSize(width: 100, height: 0))
        editor.endGesture(action: "Move")

        let movedLeft = try #require(editor.layouts[left.id]).frameMM
        let movedRight = try #require(editor.layouts[right.id]).frameMM
        #expect(movedRight.minX - movedLeft.maxX == 10)
        #expect(movedRight.maxX == editor.document.geometry.printableRect.maxX)
    }

    /// S5: deleting a group and undoing brings both members back, still grouped.
    @Test func deleteGroupIsUndoable() throws {
        let undo = makeUndo()
        let (editor, left, right) = groupedPair(undo: undo)
        let group = try #require(editor.document.element(left.id)?.groupID)
        editor.tap(right.id)
        editor.deleteSelected()
        #expect(editor.document.elements.isEmpty)

        undo.undo()
        #expect(editor.document.element(left.id)?.groupID == group)
        #expect(editor.document.element(right.id)?.groupID == group)
    }

    /// S8: undoing a re-crop restores the previous crop and frame.
    @Test func recropIsUndoable() throws {
        let undo = makeUndo()
        let picture = TestPictures.make(width: 40, height: 40) { x, _ in x < 20 ? 0 : 255 }
        let element = TestPictures.element(picture, x: 5, y: 2, width: 10)
        let editor = LabelEditor(document: LabelDocument(elements: [element]), undoManager: undo,
                                 persistsWorkingLabel: false)
        let frameBefore = try #require(editor.layouts[element.id]).frameMM

        editor.setCrop(CGRect(x: 0, y: 0, width: 0.5, height: 1), for: element.id)
        #expect(editor.layouts[element.id]?.frameMM != frameBefore)

        undo.undo()
        #expect(editor.document.element(element.id)?.picture?.crop == CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(editor.layouts[element.id]?.frameMM == frameBefore)
    }

    /// S5 regression: the block just typed in must not stay selected when Move starts, or tapping it
    /// to add it to the selection would remove it instead.
    @Test func selectModeStartsEmptyAfterTyping() {
        let editor = LabelEditor(document: LabelDocument(), undoManager: nil, persistsWorkingLabel: false)
        editor.addText()
        editor.setText("A", for: editor.document.elements[0].id)
        editor.addText()
        editor.setText("B", for: editor.document.elements[1].id)
        let first = editor.document.elements[0].id, second = editor.document.elements[1].id
        editor.setTool(.move)
        editor.tap(first)
        editor.tap(second)
        #expect(editor.selection == [first, second])
        #expect(editor.canGroup)
    }

    /// S8 (Codex review): a picture inside a group stays croppable. The first tap selects the group; a
    /// second tap on the picture shows that picture's own settings without leaving the group.
    @Test func secondTapOnGroupedPictureShowsItsSettings() throws {
        let picture = TestPictures.element(TestPictures.make(width: 20, height: 20) { _, _ in 0 }, x: 1, y: 2, width: 10)
        let text = LabelElement.text("A", originMM: CGPoint(x: 21, y: 2), widthMM: 10)
        let editor = LabelEditor(document: LabelDocument(grid: .one, elements: [picture, text]), undoManager: nil,
                                 persistsWorkingLabel: false)
        editor.setTool(.move)
        editor.tap(picture.id)
        editor.tap(text.id)
        editor.group()
        editor.setTool(.type)
        editor.clearSelection()

        editor.tap(picture.id)
        #expect(editor.selection == [picture.id, text.id])
        #expect(editor.inspectedElement == nil)
        editor.tap(picture.id)
        #expect(editor.selection == [picture.id, text.id])
        #expect(editor.inspectedElement?.id == picture.id)
    }

    // MARK: S12

    @Test func dragHandleFixesWidth() throws {
        let editor = LabelEditor(document: LabelDocument(), undoManager: nil, persistsWorkingLabel: false)
        editor.addText()
        let id = try #require(editor.selectedID)
        editor.setText("BOLTS", for: id)
        #expect(editor.document.element(id)?.textContent?.autoWidth == true)
        let autoWidth = try #require(editor.layouts[id]).contentSizeMM.width

        editor.beginGesture()
        editor.resizeElement(id, deltaMM: 10)
        editor.endGesture(action: "Resize Text")

        let element = try #require(editor.document.element(id))
        #expect(element.textContent?.autoWidth == false)
        #expect(abs(element.widthMM - (autoWidth + 10).rounded()) <= 1)
        #expect(abs(try #require(editor.layouts[id]).contentSizeMM.width - element.widthMM) < 0.001)
    }

    // MARK: S16 — label stock colour

    @Test func newLabelKeepsLastStockColour() {
        let undo = makeUndo()
        let editor = LabelEditor(document: LabelDocument(), undoManager: undo, persistsWorkingLabel: false)
        editor.setStock(.yellow)
        #expect(editor.document.stock == .yellow)

        editor.newLabel()
        #expect(editor.document.stock == .yellow)

        undo.removeAllActions()
        editor.setStock(.white)
        editor.setStock(.yellow)
        undo.undo()
        #expect(editor.document.stock == .white)
    }

    // MARK: S13 — Input and Adjust tools

    @Test func typeToolTapOnEmptyAddsTextThere() throws {
        let undo = makeUndo()
        let editor = LabelEditor(document: LabelDocument(), undoManager: undo, persistsWorkingLabel: false)
        #expect(editor.tool == .type)

        editor.tapLabel(atMM: CGPoint(x: 10, y: 8))

        let added = try #require(editor.document.elements.first)
        #expect(editor.document.elements.count == 1)
        #expect(added.originMM == CGPoint(x: 10, y: 8))
        #expect(added.textContent?.autoWidth == true)
        #expect(editor.editingID == added.id)
        undo.undo()
        #expect(editor.document.elements.isEmpty)
    }

    @Test func moveToolNeverEdits() throws {
        let block = LabelElement.text("BOLTS", originMM: CGPoint(x: 2, y: 2), widthMM: 20)
        let editor = LabelEditor(document: LabelDocument(elements: [block]), undoManager: nil,
                                 persistsWorkingLabel: false)
        editor.setTool(.move)

        editor.tap(block.id)
        #expect(editor.selection == [block.id])
        #expect(editor.editingID == nil)
        editor.tap(block.id)
        #expect(editor.editingID == nil)
        editor.tapLabel(atMM: CGPoint(x: 20, y: 20))
        #expect(editor.document.elements.count == 1)
        #expect(editor.selection.isEmpty)
    }

    @Test func scaleDragGrowsText() throws {
        let undo = makeUndo()
        let block = LabelElement.text("BOLTS", originMM: CGPoint(x: 2, y: 2), widthMM: 20, pointSize: 14)
        let editor = LabelEditor(document: LabelDocument(elements: [block]), undoManager: undo,
                                 persistsWorkingLabel: false)
        editor.setTool(.scale)

        editor.beginGesture()
        editor.scaleSelection(grabbing: block.id, translationMM: CGSize(width: 10, height: 0))
        editor.endGesture(action: "Scale")

        let scaled = try #require(editor.document.element(block.id))
        #expect(editor.selection == [block.id])
        #expect(try #require(scaled.textContent).pointSize > 14)
        let frame = try #require(editor.layouts[block.id]).frameMM
        #expect(editor.document.geometry.printableRect.contains(frame))
        undo.undo()
        #expect(editor.document.element(block.id)?.textContent?.pointSize == 14)
    }

    // MARK: S15 — insert a template

    private func libraryWithTemplate() throws -> (LabelLibrary, UUID, LabelDocument) {
        let container = try ModelContainer(for: LabelLibrary.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let library = LabelLibrary(context: ModelContext(container))
        let template = LabelDocument(elements: [
            .text("SHELF", originMM: CGPoint(x: 2, y: 2), widthMM: 20),
            .text("A", originMM: CGPoint(x: 2, y: 10), widthMM: 10),
        ])
        return (library, try library.saveTemplate(template, name: "Shelf"), template)
    }

    @Test func insertTemplateAddsGroupedCopy() throws {
        let (library, templateID, template) = try libraryWithTemplate()
        let existing = LabelElement.text("BOLTS", originMM: CGPoint(x: 25, y: 2), widthMM: 15)
        let editor = LabelEditor(document: LabelDocument(elements: [existing]), undoManager: nil,
                                 persistsWorkingLabel: false, library: library)

        editor.insertTemplate(templateID)

        let inserted = editor.document.elements.filter { $0.id != existing.id }
        #expect(inserted.count == 2)
        #expect(Set(inserted.map(\.id)).isDisjoint(with: template.elements.map(\.id)))
        #expect(inserted.map(\.textContent?.text) == ["SHELF", "A"])
        let group = try #require(inserted.first?.groupID)
        #expect(inserted.allSatisfy { $0.groupID == group })
        #expect(editor.selection == Set(inserted.map(\.id)))
        #expect(editor.document.element(existing.id)?.groupID == nil)
        #expect(try library.load(templateID) == template)
    }

    @Test func insertTemplateIsUndoable() throws {
        let (library, templateID, _) = try libraryWithTemplate()
        let undo = makeUndo()
        let editor = LabelEditor(document: LabelDocument(), undoManager: undo, persistsWorkingLabel: false,
                                 library: library)

        editor.insertTemplate(templateID)
        #expect(editor.document.elements.count == 2)
        undo.undo()
        #expect(editor.document.elements.isEmpty)
        #expect(editor.selection.isEmpty)
    }

    /// A template from a taller label lands on a short one moved as a whole, not squashed edge by edge.
    @Test func insertTemplateFromBiggerLabelKeepsSpacing() throws {
        let container = try ModelContainer(for: LabelLibrary.schema,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let library = LabelLibrary(context: ModelContext(container))
        let template = LabelDocument(size: .large, elements: [
            .text("SHELF", originMM: CGPoint(x: 2, y: 40), widthMM: 20),
            .text("A", originMM: CGPoint(x: 2, y: 52), widthMM: 10),
        ])
        let templateID = try library.saveTemplate(template, name: "Tall")
        let editor = LabelEditor(document: LabelDocument(size: .small), undoManager: nil,
                                 persistsWorkingLabel: false, library: library)

        editor.insertTemplate(templateID)

        let ys = editor.document.elements.map(\.originMM.y)
        #expect(ys.count == 2)
        #expect(abs(ys[1] - ys[0] - 12) < 0.01)
        let printable = editor.document.geometry.printableRect
        #expect(editor.document.elements.allSatisfy { printable.contains(editor.layouts[$0.id]!.frameMM) })
    }

    // MARK: S20 — tables

    @Test func addTableHasTitleAndTwoRows() throws {
        let undo = makeUndo()
        let editor = LabelEditor(document: LabelDocument(), undoManager: undo, persistsWorkingLabel: false)
        editor.addTable()
        let id = try #require(editor.selectedID)
        let table = try #require(editor.document.element(id)?.table)
        #expect(table.title.isEmpty)
        #expect(table.rows == [TableRow(), TableRow()])
        let printable = editor.document.geometry.printableRect
        #expect(printable.contains(try #require(editor.layouts[id]).frameMM.insetBy(dx: 0.001, dy: 0.001)))

        undo.undo()
        #expect(editor.document.elements.isEmpty)
    }

    @Test func addTableRowIsUndoable() throws {
        let undo = makeUndo()
        let editor = LabelEditor(document: LabelDocument(), undoManager: undo, persistsWorkingLabel: false)
        editor.addTable()
        let id = try #require(editor.selectedID)
        editor.setTableCell(.value(1), to: "14 1/2\"", for: id)

        editor.addTableRow(to: id)
        let table = try #require(editor.document.element(id)?.table)
        #expect(table.rows.count == 3)
        #expect(table.rows[1].value == "14 1/2\"")

        undo.undo()
        #expect(editor.document.element(id)?.table?.rows.count == 2)
        #expect(editor.document.element(id)?.table?.rows[1].value == "14 1/2\"")
    }

    /// Codex review of S20: rows added past the label's height ran off the print.
    @Test func addTableRowStopsAtLabelEdge() throws {
        let editor = LabelEditor(document: LabelDocument(), undoManager: makeUndo(), persistsWorkingLabel: false)
        editor.addTable()
        let id = try #require(editor.selectedID)
        for _ in 0..<100 { editor.addTableRow(to: id) }

        let element = try #require(editor.document.element(id))
        let table = try #require(element.table)
        let printable = editor.document.geometry.printableRect
        #expect(table.rows.count < 100)
        #expect(!editor.canAddTableRow(to: id))
        let layout = LayoutEngine.layout(element, in: editor.document.geometry)
        #expect(TableLayout.heightMM(table, pointSize: layout.effectivePointSize) <= printable.height)
        #expect(printable.contains(layout.frameMM.insetBy(dx: 0.01, dy: 0.01)))
    }
}
