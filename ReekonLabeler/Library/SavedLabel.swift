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

    init(id: UUID = UUID(), name: String, modified: Date = .now, documentJSON: Data, thumbnailPNG: Data?) {
        self.id = id
        self.name = name
        self.modified = modified
        self.documentJSON = documentJSON
        self.thumbnailPNG = thumbnailPNG
    }

    var document: LabelDocument? { try? JSONDecoder().decode(LabelDocument.self, from: documentJSON) }
}
