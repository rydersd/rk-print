import Foundation
import SwiftData

/// Saves, opens, renames and deletes labels, folders (S10) and templates (S11). Deletes are undoable. Every
/// label the editor works on lives here and saves itself as it changes (S9).
final class LabelLibrary {
    /// Every model the library stores; the app and the tests build their containers from it.
    static let schema = Schema([SavedLabel.self, LabelFolder.self])

    let context: ModelContext
    var undoManager: UndoManager?

    init(context: ModelContext, undoManager: UndoManager? = nil) {
        self.context = context
        self.undoManager = undoManager
    }

    /// Saves `document` under `name`. Updates the record `id` when it exists, else creates one.
    @discardableResult
    func save(_ document: LabelDocument, name: String, id: UUID? = nil, thumbnailPNG: Data? = nil) throws -> UUID {
        let json = try JSONEncoder().encode(document)
        if let id, let existing = try record(id) {
            existing.name = name
            existing.documentJSON = json
            existing.thumbnailPNG = thumbnailPNG
            existing.modified = .now
            try context.save()
            return id
        }
        let label = SavedLabel(name: name, documentJSON: json, thumbnailPNG: thumbnailPNG)
        context.insert(label)
        try context.save()
        return label.id
    }

    /// Adds a label whose name follows its first line of text.
    func create(_ document: LabelDocument, thumbnailPNG: Data? = nil) throws -> (id: UUID, name: String) {
        let name = Self.name(for: document)
        let label = SavedLabel(name: name, documentJSON: try JSONEncoder().encode(document),
                               thumbnailPNG: thumbnailPNG, followsText: true)
        context.insert(label)
        try context.save()
        return (label.id, name)
    }

    /// Writes the editor's latest copy of label `id`. Returns its name, which follows the text unless the
    /// label was renamed, or nil when the label is no longer in the library.
    func autosave(_ document: LabelDocument, id: UUID, thumbnailPNG: Data?) throws -> String? {
        guard let label = try record(id) else { return nil }
        if label.followsText { label.name = Self.name(for: document) }
        label.documentJSON = try JSONEncoder().encode(document)
        label.thumbnailPNG = thumbnailPNG
        label.modified = .now
        try context.save()
        return label.name
    }

    /// The first non-empty line of text or table title, else "Untitled".
    static func name(for document: LabelDocument) -> String {
        let lines = document.elements.lazy.compactMap { $0.textContent?.text ?? $0.table?.title }
            .flatMap { $0.split(separator: "\n") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.first { !$0.isEmpty } ?? "Untitled"
    }

    func load(_ id: UUID) throws -> LabelDocument? {
        try record(id)?.document
    }

    func name(_ id: UUID) throws -> String? {
        try record(id)?.name
    }

    func rename(_ id: UUID, to name: String) throws {
        guard let label = try record(id) else { return }
        label.name = name
        label.followsText = false
        try context.save()
    }

    /// Deletes a label or a template; undo puts it back where it was.
    func delete(_ id: UUID) throws {
        guard let label = try record(id) else { return }
        let copy = Snapshot(label)
        context.delete(label)
        try context.save()
        undoManager?.registerAction(label.isTemplate ? "Delete Template" : "Delete Label", target: self) { library in
            copy.restore(into: library.context)
            try? library.context.save()
            library.undoManager?.registerAction("Delete Label", target: library) { try? $0.delete(id) }
        }
    }

    // MARK: Folders (S10)

    func folders() throws -> [LabelFolder] {
        try context.fetch(FetchDescriptor<LabelFolder>(sortBy: [SortDescriptor(\.created)]))
    }

    /// The labels in folder `folderID`, or at the top level when nil, most recently edited first. No templates.
    func labels(inFolder folderID: UUID?) throws -> [SavedLabel] {
        try context.fetch(FetchDescriptor<SavedLabel>(
            predicate: #Predicate { $0.folderID == folderID && !$0.isTemplate },
            sortBy: [SortDescriptor(\.modified, order: .reverse)]))
    }

    /// Label `dragged` dropped on label `target`: joins the target's folder, or the two make a new one.
    func drop(_ dragged: UUID, onLabel target: UUID) throws {
        guard dragged != target, let draggedLabel = try record(dragged), let targetLabel = try record(target),
              !draggedLabel.isTemplate, !targetLabel.isTemplate else { return }
        if let folderID = targetLabel.folderID {
            draggedLabel.folderID = folderID
        } else {
            let folder = LabelFolder()
            context.insert(folder)
            targetLabel.folderID = folder.id
            draggedLabel.folderID = folder.id
        }
        try context.save()
    }

    /// Moves label `id` into folder `folderID`, or back to the top level when nil.
    func move(_ id: UUID, toFolder folderID: UUID?) throws {
        guard let label = try record(id), !label.isTemplate else { return }
        if let folderID, try folder(folderID) == nil { return }
        label.folderID = folderID
        try context.save()
    }

    func renameFolder(_ id: UUID, to name: String) throws {
        guard let folder = try folder(id) else { return }
        folder.name = name
        try context.save()
    }

    /// Deletes folder `id`, returning its labels to the top level or deleting them too, as one undo step.
    /// Returns the ids of the labels deleted.
    @discardableResult
    func deleteFolder(_ id: UUID, keepingLabels: Bool) throws -> Set<UUID> {
        guard let folder = try folder(id) else { return [] }
        let folderCopy = (name: folder.name, created: folder.created)
        let members = try labels(inFolder: id)
        let memberIDs = Set(members.map(\.id))
        let deletedCopies = keepingLabels ? [] : members.map(Snapshot.init)
        for label in members {
            if keepingLabels { label.folderID = nil } else { context.delete(label) }
        }
        context.delete(folder)
        try context.save()
        undoManager?.registerAction("Delete Folder", target: self) { library in
            library.context.insert(LabelFolder(id: id, name: folderCopy.name, created: folderCopy.created))
            if keepingLabels {
                for label in (try? library.labels(inFolder: nil)) ?? [] where memberIDs.contains(label.id) {
                    label.folderID = id
                }
            } else {
                for copy in deletedCopies { copy.restore(into: library.context) }
            }
            try? library.context.save()
            library.undoManager?.registerAction("Delete Folder", target: library) {
                try? $0.deleteFolder(id, keepingLabels: keepingLabels)
            }
        }
        return keepingLabels ? [] : memberIDs
    }

    // MARK: Templates (S11)

    func templates() throws -> [SavedLabel] {
        try context.fetch(FetchDescriptor<SavedLabel>(predicate: #Predicate { $0.isTemplate },
                                                      sortBy: [SortDescriptor(\.name)]))
    }

    /// Stores a copy of `document` as a template named `name`.
    @discardableResult
    func saveTemplate(_ document: LabelDocument, name: String, thumbnailPNG: Data? = nil) throws -> UUID {
        let template = SavedLabel(name: name, documentJSON: try JSONEncoder().encode(document),
                                  thumbnailPNG: thumbnailPNG, isTemplate: true)
        context.insert(template)
        try context.save()
        return template.id
    }

    /// A new top-level label copied from template `id`, with fresh element ids so the two never share state.
    func createLabel(fromTemplate id: UUID) throws -> (id: UUID, name: String, document: LabelDocument)? {
        guard let template = try record(id), template.isTemplate, let document = template.document else { return nil }
        let copy = document.withFreshIDs()
        let label = SavedLabel(name: template.name, documentJSON: try JSONEncoder().encode(copy),
                               thumbnailPNG: template.thumbnailPNG)
        context.insert(label)
        try context.save()
        return (label.id, label.name, copy)
    }

    // MARK: Internals

    private func record(_ id: UUID) throws -> SavedLabel? {
        try context.fetch(FetchDescriptor<SavedLabel>(predicate: #Predicate { $0.id == id })).first
    }

    private func folder(_ id: UUID) throws -> LabelFolder? {
        try context.fetch(FetchDescriptor<LabelFolder>(predicate: #Predicate { $0.id == id })).first
    }

    /// Everything needed to put a deleted label back exactly as it was.
    private struct Snapshot {
        let id: UUID, name: String, modified: Date, json: Data, thumbnail: Data?
        let followsText: Bool, folderID: UUID?, isTemplate: Bool

        init(_ label: SavedLabel) {
            id = label.id; name = label.name; modified = label.modified; json = label.documentJSON
            thumbnail = label.thumbnailPNG; followsText = label.followsText; folderID = label.folderID
            isTemplate = label.isTemplate
        }

        func restore(into context: ModelContext) {
            context.insert(SavedLabel(id: id, name: name, modified: modified, documentJSON: json,
                                      thumbnailPNG: thumbnail, followsText: followsText, folderID: folderID,
                                      isTemplate: isTemplate))
        }
    }
}
