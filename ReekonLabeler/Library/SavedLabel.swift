import Foundation
import SwiftData

/// A label in the library. The document is stored as JSON so it reopens exactly as saved.
@Model
final class SavedLabel {
    @Attribute(.unique) var id: UUID
    var name: String
    var modified: Date
    var documentJSON: Data
    @Attribute(.externalStorage) var thumbnailPNG: Data?
    /// The name follows the label's first line of text until it is renamed (S9). Labels saved by name
    /// before S9 decode as false and keep their names.
    var followsText: Bool = false
    /// The folder holding this label, or nil at the top level (S10).
    var folderID: UUID?
    /// A starting point for new labels rather than a label (S11). Templates never sit in folders.
    var isTemplate: Bool = false

    init(id: UUID = UUID(), name: String, modified: Date = .now, documentJSON: Data, thumbnailPNG: Data?,
         followsText: Bool = false, folderID: UUID? = nil, isTemplate: Bool = false) {
        self.id = id
        self.followsText = followsText
        self.folderID = folderID
        self.isTemplate = isTemplate
        self.name = name
        self.modified = modified
        self.documentJSON = documentJSON
        self.thumbnailPNG = thumbnailPNG
    }

    var document: LabelDocument? { try? JSONDecoder().decode(LabelDocument.self, from: documentJSON) }
}
