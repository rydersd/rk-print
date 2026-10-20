import CoreGraphics
import Foundation
import Observation
import os

/// The label being edited. Every change goes through here so it is kept inside the label, re-rendered,
/// and undoable as a whole-document snapshot.
@Observable
final class LabelEditor {
    private(set) var document: LabelDocument
    /// The selected elements. Selecting a grouped element selects its whole group (S5).
    private(set) var selection: Set<UUID> = []
    /// Select mode: taps add or remove elements from the selection and never start typing (S5).
    private(set) var isSelecting = false
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

    /// The working label kept in UserDefaults before S9; moved into the library on first launch.
    private static let legacyWorkingLabelKey = "workingLabel"
    private static let openLabelKey = "openLabelID"
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

    /// Taps on an element. In Select mode this adds or removes its group. Otherwise it selects its group and,
    /// for ungrouped text, starts typing; tapping a member of the already-selected group types into that
    /// member, so a double tap edits it without single taps waiting to rule out a double.
    func tap(_ id: UUID) {
        let members = document.groupMembers(of: id)
        guard !members.isEmpty else { return }
        let isText = document.element(id)?.isText == true
        if isSelecting {
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

    /// Select mode starts with nothing selected, so the block just typed in is not toggled off by the
    /// first tap meant to add it.
    func setSelecting(_ on: Bool) {
        if on && !isSelecting { selection = [] }
        isSelecting = on
        editingID = nil
    }

    // MARK: Adding and removing

    func addText() {
        var doc = document
        let printable = doc.geometry.printableRect
        let style = selectedElements.compactMap(\.textContent).last
        let element = LabelElement.text(originMM: CGPoint(x: printable.minX, y: nextFreeY(in: doc)),
                                        widthMM: printable.width, font: style?.font ?? .standard,
                                        pointSize: style?.pointSize ?? 14)
        doc.elements.append(element)
        commit(doc, action: "Add Text")
        selection = [element.id]
        editingID = isSelecting ? nil : element.id
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
        doc.elements[index].widthMM = LayoutEngine.resizedWidth(doc.elements[index], from: start.widthMM,
                                                                by: deltaMM, grid: base.grid, in: doc.geometry)
        commit(doc, action: nil)
    }

    /// Pinch: text changes point size, pictures change width, measured from the gesture's start.
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
            case .picture:
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

    /// A blank label with the current size and grid, added to the library at once (S9).
    func newLabel() {
        let blank = LabelDocument(size: document.size, orientation: document.orientation, grid: document.grid)
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

    /// Stores a copy of the current label as a template named like the label (S11).
    func saveAsTemplate() {
        guard let library else { return }
        do {
            try library.saveTemplate(document, name: libraryName ?? LabelLibrary.name(for: document),
                                     thumbnailPNG: image.flatMap(PictureImport.pngData))
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
        load(LabelDocument(size: document.size, orientation: document.orientation, grid: document.grid),
             libraryID: nil, name: nil)
    }

    /// Writes any pending change to the library now: the app is leaving the foreground, or another label opens.
    func saveNow() {
        persistTask?.cancel()
        persistTask = nil
        guard let library, document != savedDocument else { return }
        let thumbnail = image.flatMap(PictureImport.pngData)
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
