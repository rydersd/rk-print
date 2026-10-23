import CoreGraphics
import Foundation
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
        editor.setSelecting(true)
        editor.tap(left.id)
        editor.tap(right.id)
        editor.group()
        editor.setSelecting(false)
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

    /// S5 regression: the block just typed in must not stay selected when Select starts, or tapping it
    /// to add it to the selection would remove it instead.
    @Test func selectModeStartsEmptyAfterTyping() {
        let editor = LabelEditor(document: LabelDocument(), undoManager: nil, persistsWorkingLabel: false)
        editor.addText()
        editor.addText()
        let first = editor.document.elements[0].id, second = editor.document.elements[1].id
        editor.setSelecting(true)
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
        editor.setSelecting(true)
        editor.tap(picture.id)
        editor.tap(text.id)
        editor.group()
        editor.setSelecting(false)
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
}
