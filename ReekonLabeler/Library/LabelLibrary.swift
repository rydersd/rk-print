import Foundation
import SwiftData

/// Saves, opens, renames and deletes labels. Delete is undoable.
final class LabelLibrary {
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

    func load(_ id: UUID) throws -> LabelDocument? {
        try record(id)?.document
    }

    func rename(_ id: UUID, to name: String) throws {
        guard let label = try record(id) else { return }
        label.name = name
        try context.save()
    }

    func delete(_ id: UUID) throws {
        guard let label = try record(id) else { return }
        let copy = (name: label.name, modified: label.modified, json: label.documentJSON, thumbnail: label.thumbnailPNG)
        context.delete(label)
        try context.save()
        undoManager?.registerAction("Delete Label", target: self) { library in
            let restored = SavedLabel(id: id, name: copy.name, modified: copy.modified,
                                      documentJSON: copy.json, thumbnailPNG: copy.thumbnail)
            library.context.insert(restored)
            try? library.context.save()
            library.undoManager?.registerAction("Delete Label", target: library) { try? $0.delete(id) }
        }
    }

    private func record(_ id: UUID) throws -> SavedLabel? {
        try context.fetch(FetchDescriptor<SavedLabel>(predicate: #Predicate { $0.id == id })).first
    }
}
