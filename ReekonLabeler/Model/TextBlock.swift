import CoreGraphics
import Foundation

/// A font family and one of its faces. `face` is a PostScript name for installed families, or a
/// weight name ("Bold") for the system families (see `FontCatalog`).
struct FontSpec: Codable, Hashable, Sendable {
    var family: String
    var face: String

    static let standard = FontSpec(family: FontCatalog.systemFamily, face: "Bold")
}

enum TextAlignmentOption: String, Codable, Sendable, CaseIterable {
    case left, center, right
}

/// One block of text on the label. Position and width are in label-space mm; height comes from layout.
struct TextBlock: Codable, Hashable, Sendable, Identifiable {
    var id = UUID()
    var text = ""
    var originMM: CGPoint
    var widthMM: Double
    var font = FontSpec.standard
    /// The size the user asked for. Layout may draw it smaller to fit (shrink-to-fit).
    var pointSize = 14.0
    var alignment = TextAlignmentOption.left

    static let minimumWidthMM = 2.0
    static let minimumPointSize = 4.0
    static let maximumPointSize = 144.0
}
