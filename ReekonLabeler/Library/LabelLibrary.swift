import Foundation
import SwiftData

/// Saves, opens, renames and deletes labels. Delete is undoable. Every label the editor works on lives here
/// and saves itself as it changes (S9).
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

    /// The first non-empty line of text, else "Untitled".
    static func name(for document: LabelDocument) -> String {
        let lines = document.elements.lazy.compactMap(\.textContent?.text)
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

    func delete(_ id: UUID) throws {
        guard let label = try record(id) else { return }
        let copy = (name: label.name, modified: label.modified, json: label.documentJSON, thumbnail: label.thumbnailPNG,
                    followsText: label.followsText)
        context.delete(label)
        try context.save()
        undoManager?.registerAction("Delete Label", target: self) { library in
            let restored = SavedLabel(id: id, name: copy.name, modified: copy.modified,
                                      documentJSON: copy.json, thumbnailPNG: copy.thumbnail,
                                      followsText: copy.followsText)
            library.context.insert(restored)
            try? library.context.save()
            library.undoManager?.registerAction("Delete Label", target: library) { try? $0.delete(id) }
        }
    }

    private func record(_ id: UUID) throws -> SavedLabel? {
        try context.fetch(FetchDescriptor<SavedLabel>(predicate: #Predicate { $0.id == id })).first
    }
}
