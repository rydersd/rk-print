import CoreGraphics
import Foundation
import Observation
import os

/// What a finger does on the canvas (S13). Type and Draw make things; Move and Scale select and arrange.
enum EditorTool: CaseIterable {
    case type, draw, move, scale

    /// Move and Scale: taps add or remove elements from the selection and never start typing.
    var selects: Bool { self == .move || self == .scale }
}

/// The label being edited. Every change goes through here so it is kept inside the label, re-rendered,
/// and undoable as a whole-document snapshot.
@Observable
final class LabelEditor {
    private(set) var document: LabelDocument
    /// The selected elements. Selecting a grouped element selects its whole group (S5).
    private(set) var selection: Set<UUID> = []
    private(set) var tool = EditorTool.type
    /// The text element whose inline text field has focus.
    var editingID: UUID?
    /// The member of the selected group that a second tap picked out.
    private var focusedMemberID: UUID?
    private(set) var layouts: [UUID: ElementLayout] = [:]
    private(set) var bitmap: Bitmap
    private(set) var image: CGImage?
    /// The library entry this label saves to (S9). Nil only until the first edit of a label that is not in the
    /// library yet: a fresh install, or after the open label was deleted from the library.
    private(set) var libraryID: UUID?
    private(set) var libraryName: String?

    @ObservationIgnored var undoManager: UndoManager?
    @ObservationIgnored private var gestureStart: LabelDocument?
    @ObservationIgnored private let library: LabelLibrary?
    /// Remembers the open label across launches; off for tests.
    @ObservationIgnored private let persistsWorkingLabel: Bool
    @ObservationIgnored private var persistTask: Task<Void, Never>?
    /// The copy last written to the library, so opening a label does not rewrite it or bump its date.
    @ObservationIgnored private var savedDocument: LabelDocument?
    /// The stock colour chosen last, which new labels start with (S16).
    @ObservationIgnored private var lastStock = LabelStock.white
    /// The scribble the last stroke went into and when that stroke ended (S14).
    @ObservationIgnored private var lastStroke: (scribbleID: UUID, endedAt: TimeInterval)?

    /// The working label kept in UserDefaults before S9; moved into the library on first launch.
    private static let legacyWorkingLabelKey = "workingLabel"
    private static let openLabelKey = "openLabelID"
    private static let lastStockKey = "lastStock"
    /// Typing and drags change the label many times a second; the library copy is written after a pause.
    static let persistDelay = Duration.milliseconds(500)
    private static let log = Logger(subsystem: "tools.reekon.labeler", category: "editor")

    init(document: LabelDocument? = nil, undoManager: UndoManager? = nil, persistsWorkingLabel: Bool = true,
         library: LabelLibrary? = nil) {
        self.persistsWorkingLabel = persistsWorkingLabel
        self.library = library
        self.document = LayoutEngine.normalized(document ?? LabelDocument())
        self.undoManager = undoManager
        self.bitmap = Bitmap(width: 0, height: 0)
        if persistsWorkingLabel {
            lastStock = UserDefaults.standard.string(forKey: Self.lastStockKey).flatMap(LabelStock.init) ?? .white
        }
        if document == nil, persistsWorkingLabel { reopenLastLabel() }
        // What the editor starts with is not an edit: a blank label joins the library on its first change.
        if savedDocument == nil { savedDocument = self.document }
        refresh()
    }

    // MARK: Selection

    /// The selected element when exactly one is selected.
    var selectedID: UUID? { selection.count == 1 ? selection.first : nil }
    var selectedElement: LabelElement? { selectedID.flatMap { document.element($0) } }
    /// The element whose own settings the inspector shows: the single selected element, or the group member
    /// chosen by a second tap, so a picture in a group can still be cropped (S8).
    var inspectedElement: LabelElement? {
        selectedElement ?? focusedMemberID.flatMap { selection.contains($0) ? document.element($0) : nil }
    }
    /// Selected elements, back to front.
    var selectedElements: [LabelElement] { document.elements.filter { selection.contains($0.id) } }

    /// True when the selection is exactly one whole group.
    var selectionIsGroup: Bool {
        guard let group = selectedElements.first?.groupID else { return false }
        return selectedElements.allSatisfy { $0.groupID == group }
            && selection == document.groupMembers(of: selectedElements[0].id)
    }

    var canGroup: Bool { selection.count >= 2 && !selectionIsGroup }

    /// Taps on an element. In Move or Scale this adds or removes its group. Otherwise it selects its group and,
    /// for ungrouped text, starts typing; tapping a member of the already-selected group types into that
    /// member, so a double tap edits it without single taps waiting to rule out a double.
    func tap(_ id: UUID) {
        let members = document.groupMembers(of: id)
        guard !members.isEmpty else { return }
        let isText = document.element(id)?.isText == true
        if tool.selects {
            if members.isSubset(of: selection) { selection.subtract(members) } else { selection.formUnion(members) }
            editingID = nil
            focusedMemberID = nil
        } else if members.count > 1 {
            let isSecondTap = selection == members
            editingID = isSecondTap && isText ? id : nil
            focusedMemberID = isSecondTap ? id : nil
            selection = members
        } else {
            selection = members
            editingID = isText ? id : nil
            focusedMemberID = nil
        }
    }

    func clearSelection() {
        selection = []
        editingID = nil
    }

    /// Taps on the label where no element is. Type adds a text block there (S13); the other tools deselect.
    func tapLabel(atMM point: CGPoint) {
        guard tool == .type else { return clearSelection() }
        addText(atMM: point)
    }

    /// Moving to Move or Scale starts with nothing selected, so the block just typed in is not toggled off
    /// by the first tap meant to add it (S5).
    func setTool(_ newTool: EditorTool) {
        // Draw has nothing selected, so the inspector does not cover the label while drawing (S14).
        if (newTool.selects && !tool.selects) || newTool == .draw { selection = [] }
        tool = newTool
        editingID = nil
    }

    // MARK: Adding and removing

    /// Adds a text block at `point`, or below the existing elements, styled like the selected text. A block
    /// left empty is dropped in the same step, so tapping around in Type does not pile up invisible blocks.
    func addText(atMM point: CGPoint? = nil) {
        var doc = document
        let printable = doc.geometry.printableRect
        let style = selectedElements.compactMap(\.textContent).last
        if let id = editingID, doc.element(id)?.textContent?.text.isEmpty == true {
            doc.elements.removeAll { $0.id == id }
        }
        let origin = point.map { CGPoint(x: LayoutEngine.snap($0.x, doc.grid), y: LayoutEngine.snap($0.y, doc.grid)) }
            ?? CGPoint(x: printable.minX, y: nextFreeY(in: doc))
        let element = LabelElement.text(originMM: origin, widthMM: printable.maxX - origin.x,
                                        font: style?.font ?? .standard, pointSize: style?.pointSize ?? 14,
                                        autoWidth: true)
        doc.elements.append(element)
        commit(doc, action: "Add Text")
        selection = [element.id]
        editingID = tool.selects ? nil : element.id
    }

    /// Adds a picture below the existing elements, as wide as the printable area allows (S7).
    func addPicture(_ picture: PictureContent) {
        var doc = document
        let printable = doc.geometry.printableRect
        let element = LabelElement(originMM: CGPoint(x: printable.minX, y: nextFreeY(in: doc)),
                                   widthMM: printable.width, content: .picture(picture))
        doc.elements.append(element)
        commit(doc, action: "Add Picture")
        selection = [element.id]
        editingID = nil
    }

    /// A stroke drawn in Draw (S14), as points in label mm. It joins the last stroke's scribble when it
    /// starts within `strokeJoinInterval` of that stroke ending; otherwise it starts a new scribble. Times
    /// are seconds on any one clock. Each stroke is one undo step.
    func addStroke(_ pointsMM: [CGPoint], startedAt start: TimeInterval, endedAt end: TimeInterval) {
        let printable = document.geometry.printableRect
        let pen = ScribbleContent.penWidthMM
        // Kept on the label: points stay a half pen inside the printable area.
        let inside = printable.insetBy(dx: pen / 2, dy: pen / 2)
        let stroke = pointsMM.map { CGPoint(x: LayoutEngine.clamp($0.x, inside.minX, inside.maxX),
                                            y: LayoutEngine.clamp($0.y, inside.minY, inside.maxY)) }
        guard !stroke.isEmpty else { return }
        var doc = document
        var strokes = [stroke], penWidth = pen, id = UUID(), groupID: UUID?
        if let last = lastStroke, start - last.endedAt <= Self.strokeJoinInterval,
           let index = doc.index(of: last.scribbleID), let joined = doc.elements[index].scribble,
           doc.elements[index].rotation == .none {
            // Back to label mm at the scribble's current place and size, then refit around every stroke.
            let element = doc.elements[index]
            let scale = element.widthMM / joined.sizeMM.width
            strokes = joined.strokes.map { $0.map { CGPoint(x: element.originMM.x + $0.x * scale,
                                                             y: element.originMM.y + $0.y * scale) } } + strokes
            penWidth = joined.penWidthMM * scale
            id = element.id
            groupID = element.groupID
            doc.elements.remove(at: index)
        }
        guard let fitted = ScribbleContent.fitting(strokes, penWidthMM: penWidth) else { return }
        doc.elements.append(LabelElement(id: id, originMM: fitted.originMM, widthMM: fitted.content.sizeMM.width,
                                         groupID: groupID, content: .scribble(fitted.content)))
        commit(doc, action: "Draw")
        lastStroke = (id, end)
    }

    static let strokeJoinInterval: TimeInterval = 1

    func deleteSelected() {
        guard !selection.isEmpty else { return }
        var doc = document
        doc.elements.removeAll { selection.contains($0.id) }
        clearSelection()
        commit(doc, action: "Delete")
    }

    private func nextFreeY(in doc: LabelDocument) -> Double {
        let below = doc.elements.compactMap { layouts[$0.id]?.frameMM.maxY }.max() ?? doc.geometry.printableRect.minY
        return LayoutEngine.snap(below, doc.grid)
    }

    // MARK: Grouping

    func group() {
        guard canGroup else { return }
        let group = UUID()
        updateSelected(action: "Group") { $0.groupID = group }
    }

    func ungroup() {
        guard selectedElements.contains(where: { $0.groupID != nil }) else { return }
        updateSelected(action: "Ungroup") { $0.groupID = nil }
    }

    // MARK: Changing elements

    func setText(_ text: String, for id: UUID) {
        guard let current = document.element(id)?.textContent, current.text != text else { return }
        updateElement(id, action: "Typing") { $0.textContent?.text = text }
    }

    func updateElement(_ id: UUID, action: String, _ change: (inout LabelElement) -> Void) {
        guard let index = document.index(of: id) else { return }
        var doc = document
        change(&doc.elements[index])
        commit(doc, action: action)
    }

    /// Applies `change` to every selected element as one undo step (inspector font, size, alignment…).
    func updateSelected(action: String, _ change: (inout LabelElement) -> Void) {
        guard !selection.isEmpty else { return }
        var doc = document
        for index in doc.elements.indices where selection.contains(doc.elements[index].id) {
            change(&doc.elements[index])
        }
        commit(doc, action: action)
    }

    /// The tallest crop (height ÷ width) a picture turned by `rotation` can have and still print at least
    /// `LabelElement.minimumWidthMM` wide here: taller pictures narrow to fit the label's cross span.
    func maximumPictureAspect(rotation: QuarterTurn) -> Double {
        let printable = document.geometry.printableRect
        let crossSpan = rotation.isSideways ? printable.width : printable.height
        return crossSpan / LabelElement.minimumWidthMM
    }

    /// Re-crops a picture from its full original, keeping its width on the label (S8).
    func setCrop(_ crop: CGRect, for id: UUID) {
        guard document.element(id)?.picture?.crop != crop else { return }
        updateElement(id, action: "Crop") { $0.picture?.crop = crop }
    }

    /// Turns the selection a quarter turn clockwise about the centre of its footprints, then nudges it back
    /// inside the printable area (S6).
    func rotateSelection() {
        let frames = selectedElements.compactMap { element in layouts[element.id].map { (element.id, $0.frameMM) } }
        guard let first = frames.first?.1 else { return }
        let centre = frames.dropFirst().reduce(first) { $0.union($1.1) }
        var doc = document
        var turned: [UUID: CGRect] = [:]
        for (id, frame) in frames {
            guard let index = doc.index(of: id) else { continue }
            // Clockwise on the label (y down): an offset (dx, dy) from the centre becomes (−dy, dx).
            let dx = frame.midX - centre.midX, dy = frame.midY - centre.midY
            let size = CGSize(width: frame.height, height: frame.width)
            let origin = CGPoint(x: centre.midX - dy - size.width / 2, y: centre.midY + dx - size.height / 2)
            turned[id] = CGRect(origin: origin, size: size)
            doc.elements[index].rotation = doc.elements[index].rotation.next
            doc.elements[index].originMM = origin
        }
        let shift = LayoutEngine.movedDelta(of: Array(turned.values), by: .zero, grid: .off, in: doc.geometry)
        for index in doc.elements.indices where turned[doc.elements[index].id] != nil {
            doc.elements[index].originMM.x += shift.width
            doc.elements[index].originMM.y += shift.height
        }
        commit(doc, action: "Rotate")
    }

    // MARK: Gestures

    /// Starts a drag, resize or pinch. Changes until `endGesture` are one undo step, measured from here.
    func beginGesture() {
        if gestureStart == nil { gestureStart = document }
    }

    /// Drags the selection (selecting `id`'s group first if it is not selected) by `translationMM` from
    /// where the gesture began. Members keep their spacing; the drag stops at the printable edge.
    func moveSelection(grabbing id: UUID, translationMM: CGSize) {
        if !selection.contains(id) { selection = document.groupMembers(of: id) }
        let base = gestureStart ?? document
        let geometry = base.geometry
        let moving = base.elements.filter { selection.contains($0.id) }
        let frames = moving.map { LayoutEngine.layout($0, in: geometry).frameMM }
        let delta = LayoutEngine.movedDelta(of: frames, by: translationMM, grid: base.grid, in: geometry)
        var doc = document
        for (element, frame) in zip(moving, frames) {
            guard let index = doc.index(of: element.id) else { continue }
            doc.elements[index].originMM = CGPoint(x: frame.minX + delta.width, y: frame.minY + delta.height)
        }
        commit(doc, action: nil)
    }

    /// Drags an element's width handle (right edge, or bottom edge when sideways).
    func resizeElement(_ id: UUID, deltaMM: Double) {
        let base = gestureStart ?? document
        guard let start = base.element(id), let index = document.index(of: id) else { return }
        var doc = document
        // Dragging the handle fixes a text block's width from here on (S12).
        doc.elements[index].textContent?.autoWidth = false
        doc.elements[index].widthMM = LayoutEngine.resizedWidth(doc.elements[index], from: start.widthMM,
                                                                by: deltaMM, grid: base.grid, in: doc.geometry)
        commit(doc, action: nil)
    }

    /// Scale tool drag on element `id` (S13): dragging along its lines by the box's own length doubles the
    /// selection, in proportion, measured from the gesture's start.
    func scaleSelection(grabbing id: UUID, translationMM: CGSize) {
        if !selection.contains(id) { selection = document.groupMembers(of: id) }
        let base = gestureStart ?? document
        guard let start = base.element(id) else { return }
        let frame = LayoutEngine.layout(start, in: base.geometry).frameMM
        let sideways = start.rotation.isSideways
        let span = max(sideways ? frame.height : frame.width, LabelElement.minimumWidthMM)
        let along = sideways ? translationMM.height : translationMM.width
        scaleSelection(by: max(0.1, (span + along) / span))
    }

    /// Pinch or Scale drag: text changes point size (and a fixed width with it, so lines break the same),
    /// pictures and scribbles change width, measured from the gesture's start.
    func scaleSelection(by factor: Double) {
        let base = gestureStart ?? document
        var doc = document
        for start in base.elements where selection.contains(start.id) {
            guard let index = doc.index(of: start.id) else { continue }
            switch start.content {
            case .text(let text):
                let size = (text.pointSize * factor * 2).rounded() / 2
                doc.elements[index].textContent?.pointSize = min(max(size, TextContent.minimumPointSize),
                                                                 TextContent.maximumPointSize)
                if !text.autoWidth {
                    doc.elements[index].widthMM = max(LabelElement.minimumWidthMM,
                                                      LayoutEngine.snap(start.widthMM * factor, base.grid))
                }
            case .picture, .scribble:
                doc.elements[index].widthMM = max(LabelElement.minimumWidthMM,
                                                  LayoutEngine.snap(start.widthMM * factor, base.grid))
            }
        }
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

    /// Sets this label's stock colour, and the colour new labels start with (S16).
    func setStock(_ stock: LabelStock) {
        lastStock = stock
        if persistsWorkingLabel { UserDefaults.standard.set(stock.rawValue, forKey: Self.lastStockKey) }
        var doc = document
        doc.stock = stock
        commit(doc, action: "Label Colour")
    }

    func setGrid(_ grid: GridStep) {
        var doc = document
        doc.grid = grid
        commit(doc, action: nil)
    }

    /// Opens a library label. Saves the current one first, and starts a fresh undo history: undoing past
    /// the open would put the old label's content into the new label's library entry.
    func load(_ doc: LabelDocument, libraryID: UUID?, name: String?) {
        saveNow()
        clearSelection()
        undoManager?.removeAllActions(withTarget: self)
        document = LayoutEngine.normalized(doc)
        savedDocument = document
        self.libraryID = libraryID
        libraryName = name
        rememberOpenLabel()
        refresh()
    }

    /// A blank label with the current size and grid and the last stock colour, added to the library at once (S9).
    func newLabel() {
        let blank = LabelDocument(size: document.size, orientation: document.orientation, grid: document.grid,
                                  stock: lastStock)
        do {
            guard let library else { return load(blank, libraryID: nil, name: nil) }
            saveNow()
            let created = try library.create(blank)
            load(blank, libraryID: created.id, name: created.name)
        } catch {
            Self.log.error("New label failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A new library label copied from template `id`, opened in place of the current label (S11).
    func newLabel(fromTemplate id: UUID) {
        guard let library else { return }
        saveNow()
        do {
            guard let created = try library.createLabel(fromTemplate: id) else {
                Self.log.error("Template is missing from the library")
                return
            }
            load(created.document, libraryID: created.id, name: created.name)
        } catch {
            Self.log.error("Label from template failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Adds template `id`'s items to this label as one selected group, with fresh ids, kept on the label
    /// (S15). One undo step.
    func insertTemplate(_ id: UUID) {
        guard let library else { return }
        do {
            guard let template = try library.load(id) else {
                Self.log.error("Template is missing from the library")
                return
            }
            var items = template.withFreshIDs().elements
            guard !items.isEmpty else { return }
            if items.count > 1 {
                let group = UUID()
                for index in items.indices { items[index].groupID = group }
            }
            // A template from a bigger label: move the items together onto this one before `commit` clamps
            // each on its own, which would squash their spacing against the edge. Measured on the template's
            // own label, since layout on this one would already have clamped them.
            let printable = document.geometry.printableRect
            let union = items.map { LayoutEngine.layout($0, in: template.geometry).frameMM }
                .reduce(CGRect.null) { $0.union($1) }
            let dx = Self.shiftInto(union.minX...union.maxX, printable.minX...printable.maxX)
            let dy = Self.shiftInto(union.minY...union.maxY, printable.minY...printable.maxY)
            for index in items.indices {
                items[index].originMM.x += dx
                items[index].originMM.y += dy
            }
            var doc = document
            doc.elements += items
            commit(doc, action: "Insert Template")
            selection = Set(items.map(\.id))
            editingID = nil
            focusedMemberID = nil
        } catch {
            Self.log.error("Insert template failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// How far to move `span` so it lies inside `room`; a span too big for the room starts at its start.
    private static func shiftInto(_ span: ClosedRange<Double>, _ room: ClosedRange<Double>) -> Double {
        if span.lowerBound < room.lowerBound || span.upperBound - span.lowerBound > room.upperBound - room.lowerBound {
            return room.lowerBound - span.lowerBound
        }
        return min(room.upperBound - span.upperBound, 0)
    }

    /// Stores a copy of the current label as a template named like the label (S11).
    func saveAsTemplate() {
        guard let library else { return }
        // An edit still waiting on the autosave would otherwise leave the label's old name.
        saveNow()
        do {
            try library.saveTemplate(document, name: libraryName ?? LabelLibrary.name(for: document),
                                     thumbnailPNG: thumbnailPNG)
        } catch {
            Self.log.error("Save as template failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The library deleted labels `ids`; if the open label is one of them, the editor starts a blank label
    /// that joins the library on its first edit.
    func libraryDeleted(_ ids: Set<UUID>) {
        guard let id = libraryID, ids.contains(id) else { return }
        // Drop the deleted label's unsaved changes so load() does not save them back as a new label.
        persistTask?.cancel()
        savedDocument = document
        libraryID = nil
        load(LabelDocument(size: document.size, orientation: document.orientation, grid: document.grid,
                                  stock: lastStock),
             libraryID: nil, name: nil)
    }

    /// Writes any pending change to the library now: the app is leaving the foreground, or another label opens.
    func saveNow() {
        persistTask?.cancel()
        persistTask = nil
        guard let library, document != savedDocument else { return }
        let thumbnail = thumbnailPNG
        do {
            if let id = libraryID {
                guard let name = try library.autosave(document, id: id, thumbnailPNG: thumbnail) else {
                    Self.log.error("Open label is missing from the library; not saved")
                    return
                }
                libraryName = name
            } else {
                let created = try library.create(document, thumbnailPNG: thumbnail)
                libraryID = created.id
                libraryName = created.name
                rememberOpenLabel()
            }
            savedDocument = document
        } catch {
            Self.log.error("Autosave failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Internals

    /// The library thumbnail: the label as printed, on its stock colour (S16).
    private var thumbnailPNG: Data? {
        image.flatMap { PictureImport.thumbnailPNG($0, stock: document.stock) }
    }

    private func commit(_ newDocument: LabelDocument, action: String?) {
        let normalized = LayoutEngine.normalized(newDocument)
        guard normalized != document else { return }
        let previous = document
        document = normalized
        refresh()
        if let action, gestureStart == nil { registerUndo(restoring: previous, action: action) }
    }

    private func registerUndo(restoring previous: LabelDocument, action: String) {
        undoManager?.registerAction(action, target: self) { editor in editor.restore(previous, action: action) }
    }

    /// Undo and redo: swap in the snapshot and register the reverse.
    private func restore(_ snapshot: LabelDocument, action: String) {
        let current = document
        document = snapshot
        selection = selection.filter { snapshot.element($0) != nil }
        if let id = editingID, snapshot.element(id) == nil { editingID = nil }
        refresh()
        registerUndo(restoring: current, action: action)
    }

    private func refresh() {
        let start = ContinuousClock.now
        let geometry = document.geometry
        layouts = Dictionary(uniqueKeysWithValues: document.elements.map { ($0.id, LayoutEngine.layout($0, in: geometry)) })
        bitmap = LabelRenderer.render(document, layouts: layouts)
        image = bitmap.cgImage()
        let elapsed = ContinuousClock.now - start
        if elapsed > .milliseconds(30) {
            Self.log.warning("Render took \(elapsed.formatted(.units(allowed: [.milliseconds])), privacy: .public)")
        }
        schedulePersist()
    }

    private func schedulePersist() {
        guard library != nil, document != savedDocument else { return }
        persistTask?.cancel()
        persistTask = Task {
            try? await Task.sleep(for: Self.persistDelay)
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func rememberOpenLabel() {
        guard persistsWorkingLabel else { return }
        UserDefaults.standard.set(libraryID?.uuidString, forKey: Self.openLabelKey)
    }

    /// Opens the label that was open last time, or moves the pre-S9 working label into the library.
    private func reopenLastLabel() {
        guard let library else { return }
        let defaults = UserDefaults.standard
        if let text = defaults.string(forKey: Self.openLabelKey), let id = UUID(uuidString: text),
           let doc = try? library.load(id) {
            document = LayoutEngine.normalized(doc)
            savedDocument = document
            libraryID = id
            libraryName = try? library.name(id)
            return
        }
        guard let data = defaults.data(forKey: Self.legacyWorkingLabelKey),
              let doc = try? JSONDecoder().decode(LabelDocument.self, from: data) else { return }
        do {
            let created = try library.create(doc)
            document = LayoutEngine.normalized(doc)
            savedDocument = document
            libraryID = created.id
            libraryName = created.name
            rememberOpenLabel()
            defaults.removeObject(forKey: Self.legacyWorkingLabelKey)
            Self.log.info("Moved the working label into the library")
        } catch {
            Self.log.error("Moving the working label failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
