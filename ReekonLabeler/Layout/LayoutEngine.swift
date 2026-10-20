import CoreGraphics
import CoreText
import Foundation

/// Where a block is drawn and at what size, after clamping and shrink-to-fit.
struct BlockLayout: Equatable, Sendable {
    var frameMM: CGRect
    var effectivePointSize: Double
}

/// Layout rules shared by the editor and the renderer, so the canvas and the print use the same numbers.
/// Text is measured with Core Text in bitmap dots (8 per mm).
enum LayoutEngine {
    /// Typographic points to bitmap dots: 1 pt = 25.4/72 mm.
    static let dotsPerPoint = 25.4 / 72 * LabelGeometry.dotsPerMM
    private static let fitStep = 0.5

    // MARK: Layout

    static func layout(_ block: TextBlock, in geometry: LabelGeometry) -> BlockLayout {
        let printable = geometry.printableRect
        let width = clamp(block.widthMM, TextBlock.minimumWidthMM, printable.width)
        let x = clamp(block.originMM.x, printable.minX, printable.maxX - width)
        let top = clamp(block.originMM.y, printable.minY, printable.maxY)
        let available = printable.maxY - top

        let size = fittedPointSize(for: block, widthMM: width, availableMM: available)
        let height = textHeightMM(block, pointSize: size, widthMM: width)
        let y = height >= printable.height ? printable.minY : clamp(top, printable.minY, printable.maxY - height)
        return BlockLayout(frameMM: CGRect(x: x, y: y, width: width, height: height), effectivePointSize: size)
    }

    /// The largest size ≤ the requested size, in 0.5 pt steps, whose wrapped text fits `availableMM`.
    private static func fittedPointSize(for block: TextBlock, widthMM: Double, availableMM: Double) -> Double {
        let requested = clamp(block.pointSize, TextBlock.minimumPointSize, TextBlock.maximumPointSize)
        if textHeightMM(block, pointSize: requested, widthMM: widthMM) <= availableMM { return requested }
        // Binary search over sizes requested − k × step, k in 1...maxK.
        var low = 1, high = Int(((requested - TextBlock.minimumPointSize) / fitStep).rounded(.down))
        guard high >= 1 else { return requested }
        var best = high
        while low <= high {
            let mid = (low + high) / 2
            if textHeightMM(block, pointSize: requested - Double(mid) * fitStep, widthMM: widthMM) <= availableMM {
                best = mid
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
        return requested - Double(best) * fitStep
    }

    static func textHeightMM(_ block: TextBlock, pointSize: Double, widthMM: Double) -> Double {
        let font = FontCatalog.ctFont(block.font, pointSize: pointSize * dotsPerPoint)
        let lineHeight = (CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)).rounded(.up)
        guard !block.text.isEmpty else { return lineHeight / LabelGeometry.dotsPerMM }
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText(block, font: font))
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(), nil,
            CGSize(width: widthMM * LabelGeometry.dotsPerMM, height: .greatestFiniteMagnitude), nil)
        var height = suggested.height.rounded(.up)
        // A trailing newline starts a line the framesetter does not measure; count it so the caret has room.
        if block.text.hasSuffix("\n") { height += lineHeight }
        return max(height, lineHeight) / LabelGeometry.dotsPerMM
    }

    static func attributedText(_ block: TextBlock, font: CTFont) -> CFAttributedString {
        var alignment: CTTextAlignment = switch block.alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        }
        var lineBreak = CTLineBreakMode.byWordWrapping
        let paragraph = withUnsafeBytes(of: &alignment) { alignmentBytes in
            withUnsafeBytes(of: &lineBreak) { breakBytes in
                let settings = [
                    CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size,
                                            value: alignmentBytes.baseAddress!),
                    CTParagraphStyleSetting(spec: .lineBreakMode, valueSize: MemoryLayout<CTLineBreakMode>.size,
                                            value: breakBytes.baseAddress!),
                ]
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTParagraphStyleAttributeName: paragraph,
            kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1),
        ]
        return CFAttributedStringCreate(nil, block.text as CFString, attributes as CFDictionary)
    }

    // MARK: Editing

    /// The origin for a block dragged by `delta` from `start`: snapped to the grid, then kept inside the
    /// printable area at the block's current drawn size.
    static func moved(_ block: TextBlock, from start: CGPoint, by delta: CGSize, grid: GridStep,
                      in geometry: LabelGeometry) -> CGPoint {
        let size = layout(block, in: geometry).frameMM.size
        let printable = geometry.printableRect
        let proposed = CGPoint(x: snap(start.x + delta.width, grid), y: snap(start.y + delta.height, grid))
        return CGPoint(x: clamp(proposed.x, printable.minX, printable.maxX - size.width),
                       y: clamp(proposed.y, printable.minY, max(printable.minY, printable.maxY - size.height)))
    }

    /// The width for a block whose right edge is dragged by `delta` from `startWidth`.
    static func resizedWidth(_ block: TextBlock, from startWidth: Double, by delta: Double, grid: GridStep,
                             in geometry: LabelGeometry) -> Double {
        let right = min(snap(block.originMM.x + startWidth + delta, grid), geometry.printableRect.maxX)
        return max(TextBlock.minimumWidthMM, right - block.originMM.x)
    }

    /// The document with every block's stored origin and width pulled inside the printable area.
    static func normalized(_ document: LabelDocument) -> LabelDocument {
        var doc = document
        let geometry = doc.geometry
        for index in doc.blocks.indices {
            let frame = layout(doc.blocks[index], in: geometry).frameMM
            doc.blocks[index].originMM = frame.origin
            doc.blocks[index].widthMM = frame.width
        }
        return doc
    }

    // MARK: Helpers

    static func snap(_ value: Double, _ grid: GridStep) -> Double {
        guard grid != .off else { return value }
        return (value / grid.rawValue).rounded() * grid.rawValue
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(max(value, low), max(low, high))
    }
}
