import CoreGraphics
import Foundation

/// A font family and one of its faces. `face` is a PostScript name for installed families, or a
/// weight name ("Bold") for the system families (see `FontCatalog`).
nonisolated struct FontSpec: Codable, Hashable, Sendable {
    var family: String
    var face: String

    static let standard = FontSpec(family: FontCatalog.systemFamily, face: "Bold")
}

nonisolated enum TextAlignmentOption: String, Codable, Sendable, CaseIterable {
    case left, center, right
}

/// A quarter-turn rotation, clockwise as seen on the label (S6).
nonisolated enum QuarterTurn: Int, Codable, Sendable, CaseIterable {
    case none = 0, quarter = 90, half = 180, threeQuarter = 270

    var next: QuarterTurn { QuarterTurn(rawValue: (rawValue + 90) % 360) ?? .none }
    /// True at 90° and 270°, where the content's width runs down the label.
    var isSideways: Bool { self == .quarter || self == .threeQuarter }
}

/// The text of a text element and how it is set.
nonisolated struct TextContent: Codable, Hashable, Sendable {
    var text = ""
    var font = FontSpec.standard
    /// The size the user asked for. Layout may draw it smaller to fit (shrink-to-fit).
    var pointSize = 14.0
    var alignment = TextAlignmentOption.left
    /// The box hugs the longest line and wraps only at the label edge; a width-handle drag turns it off
    /// (S12). Labels saved before S12 decode as fixed width.
    var autoWidth = false

    static let minimumPointSize = 4.0
    static let maximumPointSize = 144.0

    init(text: String = "", font: FontSpec = .standard, pointSize: Double = 14.0,
         alignment: TextAlignmentOption = .left, autoWidth: Bool = false) {
        self.text = text
        self.font = font
        self.pointSize = pointSize
        self.alignment = alignment
        self.autoWidth = autoWidth
    }

    private enum CodingKeys: String, CodingKey { case text, font, pointSize, alignment, autoWidth }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        font = try container.decode(FontSpec.self, forKey: .font)
        pointSize = try container.decode(Double.self, forKey: .pointSize)
        alignment = try container.decode(TextAlignmentOption.self, forKey: .alignment)
        autoWidth = try container.decodeIfPresent(Bool.self, forKey: .autoWidth) ?? false
    }
}

/// Finger strokes drawn in one go (S14). Points are mm from the top-left of the strokes' bounds, pen
/// included, at the size they were drawn; the element's width scales them.
nonisolated struct ScribbleContent: Codable, Hashable, Sendable {
    var strokes: [[CGPoint]]
    var sizeMM: CGSize
    /// At `sizeMM`; it scales with the scribble.
    var penWidthMM: Double

    static let penWidthMM = 0.75

    var aspect: Double { sizeMM.height / sizeMM.width }

    /// A scribble of `strokes` given in label mm, and where its top-left sits on the label. The box is the
    /// strokes' bounds plus half the pen on every side, widened to the minimum element width if need be.
    static func fitting(_ strokes: [[CGPoint]], penWidthMM: Double) -> (content: ScribbleContent, originMM: CGPoint)? {
        let points = strokes.flatMap { $0 }
        guard let first = points.first else { return nil }
        var bounds = points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
        bounds = bounds.insetBy(dx: -penWidthMM / 2, dy: -penWidthMM / 2)
        if bounds.width < LabelElement.minimumWidthMM {
            bounds = bounds.insetBy(dx: -(LabelElement.minimumWidthMM - bounds.width) / 2, dy: 0)
        }
        let local = strokes.map { $0.map { CGPoint(x: $0.x - bounds.minX, y: $0.y - bounds.minY) } }
        return (ScribbleContent(strokes: local, sizeMM: bounds.size, penWidthMM: penWidthMM), bounds.origin)
    }
}

nonisolated enum ElementContent: Codable, Hashable, Sendable {
    case text(TextContent)
    case picture(PictureContent)
    case scribble(ScribbleContent)
}

/// One thing on the label: text, a picture or a scribble. `originMM` is the top-left of its footprint (the box it
/// covers once rotated); `widthMM` is the unrotated content width. Both are label-space mm.
nonisolated struct LabelElement: Codable, Hashable, Sendable, Identifiable {
    var id = UUID()
    var originMM: CGPoint
    var widthMM: Double
    var rotation = QuarterTurn.none
    /// Elements sharing a group ID select, move, rotate and delete together (S5).
    var groupID: UUID?
    var content: ElementContent

    static let minimumWidthMM = 2.0

    static func text(_ text: String = "", originMM: CGPoint, widthMM: Double, font: FontSpec = .standard,
                     pointSize: Double = 14, alignment: TextAlignmentOption = .left,
                     autoWidth: Bool = false) -> LabelElement {
        LabelElement(originMM: originMM, widthMM: widthMM,
                     content: .text(TextContent(text: text, font: font, pointSize: pointSize, alignment: alignment,
                                                autoWidth: autoWidth)))
    }

    /// The text, for text elements; setting it on a picture does nothing.
    var textContent: TextContent? {
        get { if case .text(let text) = content { text } else { nil } }
        set { if let newValue, case .text = content { content = .text(newValue) } }
    }

    var picture: PictureContent? {
        get { if case .picture(let picture) = content { picture } else { nil } }
        set { if let newValue, case .picture = content { content = .picture(newValue) } }
    }

    var scribble: ScribbleContent? {
        get { if case .scribble(let scribble) = content { scribble } else { nil } }
        set { if let newValue, case .scribble = content { content = .scribble(newValue) } }
    }

    var isText: Bool { textContent != nil }

    /// Height ÷ width for content that keeps its proportions (pictures and scribbles); nil for text.
    var aspect: Double? {
        switch content {
        case .text: nil
        case .picture(let picture): picture.aspect
        case .scribble(let scribble): scribble.aspect
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, originMM, widthMM, rotation, groupID, content
    }

    init(id: UUID = UUID(), originMM: CGPoint, widthMM: Double, rotation: QuarterTurn = .none, groupID: UUID? = nil,
         content: ElementContent) {
        self.id = id
        self.originMM = originMM
        self.widthMM = widthMM
        self.rotation = rotation
        self.groupID = groupID
        self.content = content
    }

    /// Reads current elements and labels saved before S5–S7, whose text blocks kept their text, font,
    /// size and alignment at the top level and had no rotation or group.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        originMM = try container.decode(CGPoint.self, forKey: .originMM)
        widthMM = try container.decode(Double.self, forKey: .widthMM)
        rotation = try container.decodeIfPresent(QuarterTurn.self, forKey: .rotation) ?? .none
        groupID = try container.decodeIfPresent(UUID.self, forKey: .groupID)
        content = try container.decodeIfPresent(ElementContent.self, forKey: .content)
            ?? .text(TextContent(from: decoder))
    }
}
