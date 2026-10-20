import CoreGraphics
import Foundation
import Observation
import os

/// The label being edited. Every change goes through here so it is kept inside the label, re-rendered,
/// and undoable as a whole-document snapshot.
@Observable
final class LabelEditor {
    private(set) var document: LabelDocument
    var selectedID: UUID?
    /// The block whose inline text field has focus.
    var editingID: UUID?
    private(set) var layouts: [UUID: BlockLayout] = [:]
    private(set) var bitmap: Bitmap
    private(set) var image: CGImage?
    /// Set when the label was opened from (or saved to) the library.
    var libraryID: UUID?
    var libraryName: String?

    @ObservationIgnored var undoManager: UndoManager?
    @ObservationIgnored private var gestureStart: LabelDocument?
    @ObservationIgnored private let persistsWorkingLabel: Bool

    private static let workingLabelKey = "workingLabel"
    private static let log = Logger(subsystem: "tools.reekon.labeler", category: "editor")

    init(document: LabelDocument? = nil, undoManager: UndoManager? = nil, persistsWorkingLabel: Bool = true) {
        self.persistsWorkingLabel = persistsWorkingLabel
        let start = document ?? (persistsWorkingLabel ? Self.restoredWorkingLabel() : nil) ?? LabelDocument()
        self.document = LayoutEngine.normalized(start)
        self.undoManager = undoManager
        self.bitmap = Bitmap(width: 0, height: 0)
        refresh()
    }

    var selectedBlock: TextBlock? { selectedID.flatMap { document.block($0) } }

    // MARK: Blocks

    func addBlock() {
        var doc = document
        let printable = doc.geometry.printableRect
        let below = doc.blocks.compactMap { layouts[$0.id]?.frameMM.maxY }.max() ?? printable.minY
        let y = LayoutEngine.snap(below, doc.grid)
        let block = TextBlock(originMM: CGPoint(x: printable.minX, y: y), widthMM: printable.width,
                              font: selectedBlock?.font ?? .standard, pointSize: selectedBlock?.pointSize ?? 14)
        doc.blocks.append(block)
        commit(doc, action: "Add Text")
        selectedID = block.id
        editingID = block.id
    }

    func deleteSelected() {
        guard let id = selectedID else { return }
        var doc = document
        doc.blocks.removeAll { $0.id == id }
        selectedID = nil
        editingID = nil
        commit(doc, action: "Delete Text")
    }

    func setText(_ text: String, for id: UUID) {
        guard document.block(id)?.text != text else { return }
        updateBlock(id, action: "Typing") { $0.text = text }
    }

    func updateBlock(_ id: UUID, action: String, _ change: (inout TextBlock) -> Void) {
        guard let index = document.index(of: id) else { return }
        var doc = document
        change(&doc.blocks[index])
        commit(doc, action: action)
    }

    func select(_ id: UUID?) {
        selectedID = id
        editingID = id
    }

    // MARK: Gestures

    /// Starts a drag, resize or pinch. Changes until `endGesture` are one undo step, measured from here.
    func beginGesture() {
        if gestureStart == nil { gestureStart = document }
    }

    func moveBlock(_ id: UUID, translationMM: CGSize) {
        let base = gestureStart ?? document
        guard let start = base.block(id), let index = document.index(of: id) else { return }
        var doc = document
        doc.blocks[index].originMM = LayoutEngine.moved(doc.blocks[index], from: start.originMM, by: translationMM,
                                                        grid: base.grid, in: doc.geometry)
        commit(doc, action: nil)
    }

    func resizeBlock(_ id: UUID, deltaMM: Double) {
        let base = gestureStart ?? document
        guard let start = base.block(id), let index = document.index(of: id) else { return }
        var doc = document
        doc.blocks[index].widthMM = LayoutEngine.resizedWidth(doc.blocks[index], from: start.widthMM, by: deltaMM,
                                                              grid: base.grid, in: doc.geometry)
        commit(doc, action: nil)
    }

    func scaleBlock(_ id: UUID, by factor: Double) {
        let base = gestureStart ?? document
        guard let start = base.block(id), let index = document.index(of: id) else { return }
        var doc = document
        let size = (start.pointSize * factor * 2).rounded() / 2
        doc.blocks[index].pointSize = min(max(size, TextBlock.minimumPointSize), TextBlock.maximumPointSize)
        commit(doc, action: nil)
    }

    func endGesture(action: String) {
        guard let start = gestureStart else { return }
        gestureStart = nil
        if start != document { registerUndo(restoring: start, action: action) }
    }

    // MARK: Label settings

    func setSize(_ size: LabelSize) {
        var doc = document
        doc.size = size
        commit(doc, action: "Label Size")
    }

    func setOrientation(_ orientation: Orientation) {
        var doc = document
        doc.orientation = orientation
        commit(doc, action: "Rotate Label")
    }

    func setGrid(_ grid: GridStep) {
        var doc = document
        doc.grid = grid
        commit(doc, action: nil)
    }

    /// Replaces the label, for example when opening one from the library. Undoable.
    func load(_ doc: LabelDocument, libraryID: UUID?, name: String?) {
        select(nil)
        commit(doc, action: "Open Label")
        self.libraryID = libraryID
        libraryName = name
    }

    func newLabel() {
        load(LabelDocument(size: document.size, orientation: document.orientation, grid: document.grid),
             libraryID: nil, name: nil)
    }

    // MARK: Internals

    private func commit(_ newDocument: LabelDocument, action: String?) {
        let normalized = LayoutEngine.normalized(newDocument)
        guard normalized != document else { return }
        let previous = document
        document = normalized
        refresh()
        if let action, gestureStart == nil { registerUndo(restoring: previous, action: action) }
    }

    private func registerUndo(restoring previous: LabelDocument, action: String) {
        guard let undoManager else { return }
        // Outside an event loop (tests, scripted edits) there is no automatic group: make one per action.
        let ownGroup = !undoManager.groupsByEvent && undoManager.groupingLevel == 0
        if ownGroup { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { editor in
            MainActor.assumeIsolated { editor.restore(previous, action: action) }
        }
        undoManager.setActionName(action)
        if ownGroup { undoManager.endUndoGrouping() }
    }

    /// Undo and redo: swap in the snapshot and register the reverse.
    private func restore(_ snapshot: LabelDocument, action: String) {
        let current = document
        document = snapshot
        if let id = selectedID, snapshot.block(id) == nil { select(nil) }
        refresh()
        registerUndo(restoring: current, action: action)
    }

    private func refresh() {
        let start = ContinuousClock.now
        let geometry = document.geometry
        layouts = Dictionary(uniqueKeysWithValues: document.blocks.map { ($0.id, LayoutEngine.layout($0, in: geometry)) })
        bitmap = LabelRenderer.render(document, layouts: layouts)
        image = bitmap.cgImage()
        let elapsed = ContinuousClock.now - start
        if elapsed > .milliseconds(30) {
            Self.log.warning("Render took \(elapsed.formatted(.units(allowed: [.milliseconds])), privacy: .public)")
        }
        if persistsWorkingLabel, let data = try? JSONEncoder().encode(document) {
            UserDefaults.standard.set(data, forKey: Self.workingLabelKey)
        }
    }

    private static func restoredWorkingLabel() -> LabelDocument? {
        guard let data = UserDefaults.standard.data(forKey: workingLabelKey) else { return nil }
        return try? JSONDecoder().decode(LabelDocument.self, from: data)
    }
}
