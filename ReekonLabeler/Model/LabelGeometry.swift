import CoreGraphics

/// The label's dimensions in label space: millimetres, origin at the label's top-left as shown on the
/// canvas. The printable area is the part of the label the head can reach.
struct LabelGeometry: Equatable, Sendable {
    static let dotsPerMM = 8.0

    let labelSizeMM: CGSize
    let printableRect: CGRect
    let bitmapWidth: Int
    let bitmapHeight: Int

    init(size: LabelSize, orientation: Orientation) {
        let headPrintMM = Double(size.headDots) / Self.dotsPerMM
        let feedPrintMM = Double(size.feedDots) / Self.dotsPerMM
        // A 50 mm label is wider than the 48 mm head; assume the head is centred on it.
        let headMargin = max(0, (size.headMM - headPrintMM) / 2)
        switch orientation {
        case .headNative:
            labelSizeMM = CGSize(width: size.headMM, height: size.feedMM)
            printableRect = CGRect(x: headMargin, y: 0, width: headPrintMM, height: feedPrintMM)
            bitmapWidth = size.headDots
            bitmapHeight = size.feedDots
        case .rotated:
            labelSizeMM = CGSize(width: size.feedMM, height: size.headMM)
            printableRect = CGRect(x: 0, y: headMargin, width: feedPrintMM, height: headPrintMM)
            bitmapWidth = size.feedDots
            bitmapHeight = size.headDots
        }
    }

    /// Converts a label-space rect in mm to bitmap dots (bitmap origin is the printable area's top-left).
    func dotRect(forMM rect: CGRect) -> CGRect {
        CGRect(x: (rect.minX - printableRect.minX) * Self.dotsPerMM,
               y: (rect.minY - printableRect.minY) * Self.dotsPerMM,
               width: rect.width * Self.dotsPerMM,
               height: rect.height * Self.dotsPerMM)
    }
}
