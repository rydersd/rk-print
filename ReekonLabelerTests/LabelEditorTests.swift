import CoreGraphics
import Foundation
import Testing
@testable import Labeler

struct LabelEditorTests {
    @Test func undoRestoresPositionAfterClampedDrag() throws {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let editor = LabelEditor(document: LabelDocument(), undoManager: undo, persistsWorkingLabel: false)
        editor.addBlock()
        let id = try #require(editor.selectedID)
        editor.setText("BOLTS", for: id)
        editor.beginGesture()
        editor.resizeBlock(id, deltaMM: -30)
        editor.endGesture(action: "Resize")
        let original = try #require(editor.document.block(id)).originMM

        editor.beginGesture()
        editor.moveBlock(id, translationMM: CGSize(width: 100, height: 100))
        editor.endGesture(action: "Move")
        #expect(editor.document.block(id)!.originMM != original)

        undo.undo()
        #expect(editor.document.block(id)!.originMM == original)
    }

    @Test func addingBlocksKeepsEachInsideTheLabel() {
        let editor = LabelEditor(document: LabelDocument(), undoManager: nil, persistsWorkingLabel: false)
        for _ in 0..<6 { editor.addBlock() }
        let printable = editor.document.geometry.printableRect
        for block in editor.document.blocks {
            let frame = editor.layouts[block.id]!.frameMM
            #expect(printable.contains(frame.insetBy(dx: 0.001, dy: 0.001)))
        }
    }
}
