import Foundation

/// A label stock size. The head axis is the side that runs across the P1L's print head; the feed axis
/// is the direction the label travels (SDK Section II, Print Job Format).
nonisolated struct LabelSize: Codable, Hashable, Sendable {
    /// Length of the label side that runs across the print head, in mm.
    var headMM: Double
    /// Length of the label in the feed direction, in mm.
    var feedMM: Double
    /// Printable rows in the feed direction. The SDK gives these for its presets; custom sizes leave
    /// 2 mm unprinted (an assumption, see the spec's open questions).
    var feedDots: Int

    static let small = LabelSize(headMM: 50, feedMM: 30, feedDots: 240)
    static let large = LabelSize(headMM: 50, feedMM: 80, feedDots: 624)
    static let presets: [LabelSize] = [.small, .large]

    static let headMaxDots = 384
    static let minimumMM = 10.0

    static func custom(headMM: Double, feedMM: Double) -> LabelSize {
        let head = min(max(headMM, minimumMM), 50)
        let feed = min(max(feedMM, minimumMM), 200)
        return LabelSize(headMM: head, feedMM: feed, feedDots: max(8, Int(feed * LabelGeometry.dotsPerMM) - 16))
    }

    /// Printable dots across the head: the full 384-dot head, or less on narrower stock, rounded down
    /// to whole bytes so every row is a whole number of bytes.
    var headDots: Int {
        let dots = Int((headMM * LabelGeometry.dotsPerMM).rounded(.down))
        return min(Self.headMaxDots, dots / 8 * 8)
    }

    var isPreset: Bool { Self.presets.contains(self) }

    /// "30 × 50 mm": feed first, matching how REEKON names its rolls.
    var displayName: String {
        "\(feedMM.formatted(.number.precision(.fractionLength(0...1)))) × \(headMM.formatted(.number.precision(.fractionLength(0...1)))) mm"
    }
}

/// How the label is shown on the canvas.
nonisolated enum Orientation: String, Codable, Sendable, CaseIterable {
    /// The head axis runs left to right (30 × 50 reads 50 wide by 30 tall).
    case headNative
    /// The feed axis runs left to right; the bitmap is rotated 90° before printing.
    case rotated
}
