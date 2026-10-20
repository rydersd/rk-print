import Foundation

/// Grid spacing for snapping, in mm. `off` disables snapping.
nonisolated enum GridStep: Double, Codable, Sendable, CaseIterable {
    case off = 0
    case half = 0.5
    case one = 1
    case two = 2

    var displayName: String {
        switch self {
        case .off: "Off"
        case .half: "0.5 mm"
        case .one: "1 mm"
        case .two: "2 mm"
        }
    }
}

/// A whole label: its stock, how it is shown, and the text and pictures on it, back to front.
nonisolated struct LabelDocument: Codable, Hashable, Sendable {
    var size = LabelSize.small
    var orientation = Orientation.headNative
    var grid = GridStep.one
    var elements: [LabelElement] = []

    init(size: LabelSize = .small, orientation: Orientation = .headNative, grid: GridStep = .one,
         elements: [LabelElement] = []) {
        self.size = size
        self.orientation = orientation
        self.grid = grid
        self.elements = elements
    }

    var geometry: LabelGeometry { LabelGeometry(size: size, orientation: orientation) }

    func element(_ id: UUID) -> LabelElement? { elements.first { $0.id == id } }

    func index(of id: UUID) -> Int? { elements.firstIndex { $0.id == id } }

    /// The element's whole group, or just the element when it is not grouped.
    func groupMembers(of id: UUID) -> Set<UUID> {
        guard let element = element(id) else { return [] }
        guard let group = element.groupID else { return [id] }
        return Set(elements.filter { $0.groupID == group }.map(\.id))
    }

    // Labels saved before S5–S7 store their text blocks under "blocks".
    private enum CodingKeys: String, CodingKey { case size, orientation, grid, elements, blocks }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = try container.decode(LabelSize.self, forKey: .size)
        orientation = try container.decode(Orientation.self, forKey: .orientation)
        grid = try container.decode(GridStep.self, forKey: .grid)
        elements = try container.decodeIfPresent([LabelElement].self, forKey: .elements)
            ?? container.decodeIfPresent([LabelElement].self, forKey: .blocks) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(size, forKey: .size)
        try container.encode(orientation, forKey: .orientation)
        try container.encode(grid, forKey: .grid)
        try container.encode(elements, forKey: .elements)
    }
}
