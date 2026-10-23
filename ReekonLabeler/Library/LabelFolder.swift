import Foundation
import SwiftData

/// A folder of labels in the library, made by dropping one label on another (S10). One level only.
@Model
final class LabelFolder {
    @Attribute(.unique) var id: UUID
    var name: String
    var created: Date

    init(id: UUID = UUID(), name: String = "Folder", created: Date = .now) {
        self.id = id
        self.name = name
        self.created = created
    }
}
