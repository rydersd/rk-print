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

/// A whole label: its stock, how it is shown, and its text blocks.
nonisolated struct LabelDocument: Codable, Hashable, Sendable {
    var size = LabelSize.small
    var orientation = Orientation.headNative
    var grid = GridStep.one
    var blocks: [TextBlock] = []

    var geometry: LabelGeometry { LabelGeometry(size: size, orientation: orientation) }

    func block(_ id: UUID) -> TextBlock? { blocks.first { $0.id == id } }

    func index(of id: UUID) -> Int? { blocks.firstIndex { $0.id == id } }
}
