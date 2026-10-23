import CoreGraphics
import Foundation
import Testing
@testable import Labeler

/// S14: finger scribbles.
struct ScribbleTests {
    private func makeEditor(undo: UndoManager? = nil) -> LabelEditor {
        LabelEditor(document: LabelDocument(size: .large, grid: .off), undoManager: undo, persistsWorkingLabel: false)
    }

    private var scribbles: (LabelEditor) -> [LabelElement] {
        { editor in editor.document.elements.filter { $0.scribble != nil } }
    }

    @Test func strokesWithinPauseJoinOneScribble() throws {
        let undo = UndoManager()
        undo.groupsByEvent = false
        let editor = makeEditor(undo: undo)
        editor.setTool(.draw)

        editor.addStroke([CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 15)], startedAt: 0, endedAt: 0.3)
        editor.addStroke([CGPoint(x: 12, y: 20), CGPoint(x: 22, y: 25)], startedAt: 0.8, endedAt: 1.1)
        #expect(scribbles(editor).count == 1)
        #expect(scribbles(editor).first?.scribble?.strokes.count == 2)

        editor.addStroke([CGPoint(x: 30, y: 10), CGPoint(x: 40, y: 12)], startedAt: 3.1, endedAt: 3.4)
        #expect(scribbles(editor).count == 2)

        // Undo removes the last stroke only.
        undo.undo()
        undo.undo()
        #expect(scribbles(editor).count == 1)
        #expect(scribbles(editor).first?.scribble?.strokes.count == 1)
    }

    @Test func scribbleBoxFitsStrokes() throws {
        let editor = makeEditor()
        editor.setTool(.draw)
        editor.addStroke([CGPoint(x: 10, y: 10), CGPoint(x: 25, y: 18), CGPoint(x: 18, y: 22)],
                         startedAt: 0, endedAt: 0.5)

        let element = try #require(scribbles(editor).first)
        let pen = try #require(element.scribble).penWidthMM
        let frame = try #require(editor.layouts[element.id]).frameMM
        let expected = CGRect(x: 10, y: 10, width: 15, height: 12).insetBy(dx: -pen / 2, dy: -pen / 2)
        #expect(abs(frame.minX - expected.minX) < 0.01)
        #expect(abs(frame.minY - expected.minY) < 0.01)
        #expect(abs(frame.width - expected.width) < 0.01)
        #expect(abs(frame.height - expected.height) < 0.01)

        let geometry = editor.document.geometry
        let all = editor.bitmap.inkCount(inDots: CGRect(x: 0, y: 0, width: editor.bitmap.width,
                                                        height: editor.bitmap.height))
        #expect(all > 0)
        #expect(editor.bitmap.inkCount(inDots: geometry.dotRect(forMM: frame.insetBy(dx: -0.25, dy: -0.25))) == all)
    }
}
