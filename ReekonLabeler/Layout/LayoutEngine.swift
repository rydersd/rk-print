import CoreGraphics
import CoreText
import Foundation

/// Where an element is drawn and at what size, after clamping and shrink-to-fit.
nonisolated struct ElementLayout: Equatable, Sendable {
    /// The footprint: the box the element covers on the label once rotated.
    var frameMM: CGRect
    /// The content's own size before rotation (width along its text lines or picture width).
    var contentSizeMM: CGSize
    /// For text and tables, the size actually drawn; 0 for pictures and scribbles.
    var effectivePointSize: Double
}

/// Layout rules shared by the editor and the renderer, so the canvas and the print use the same numbers.
/// Text is measured with Core Text in bitmap dots (8 per mm).
nonisolated enum LayoutEngine {
    /// Typographic points to bitmap dots: 1 pt = 25.4/72 mm.
    static let dotsPerPoint = 25.4 / 72 * LabelGeometry.dotsPerMM
    private static let fitStep = 0.5

    // MARK: Layout

    /// The element's footprint inside the printable area. Content runs along the "along" axis (x, or y when
    /// sideways) and stacks along the "cross" axis; text shrinks to fit the cross space left below its top.
    static func layout(_ element: LabelElement, in geometry: LabelGeometry) -> ElementLayout {
        let printable = geometry.printableRect
        let sideways = element.rotation.isSideways
        let (alongMin, alongMax) = sideways ? (printable.minY, printable.maxY) : (printable.minX, printable.maxX)
        let (crossMin, crossMax) = sideways ? (printable.minX, printable.maxX) : (printable.minY, printable.maxY)
        let originAlong = sideways ? element.originMM.y : element.originMM.x
        let originCross = sideways ? element.originMM.x : element.originMM.y

        var width = clamp(element.widthMM, LabelElement.minimumWidthMM, alongMax - alongMin)
        let height: Double, pointSize: Double, crossPosition: Double
        switch element.content {
        case .text(let text):
            // Auto width (S12): as wide as the longest line, wrapping only at the printable edge.
            if text.autoWidth {
                let room = alongMax - clamp(originAlong, alongMin, alongMax - LabelElement.minimumWidthMM)
                width = clamp(naturalWidthMM(text, maximumMM: room), LabelElement.minimumWidthMM, room)
            }
            let top = clamp(originCross, crossMin, crossMax)
            pointSize = fittedPointSize(for: text, widthMM: width, availableMM: crossMax - top)
            height = textHeightMM(text, pointSize: pointSize, widthMM: width)
            crossPosition = height >= crossMax - crossMin ? crossMin : clamp(top, crossMin, crossMax - height)
        case .table(let table):
            // Like text: shrinks to fit the cross space left below its top (S20).
            let top = clamp(originCross, crossMin, crossMax)
            pointSize = TableLayout.fittedPointSize(table, availableMM: crossMax - top)
            // Never taller than the label: a table rotated onto the short side squeezes its rows instead.
            height = min(TableLayout.heightMM(table, pointSize: pointSize), crossMax - crossMin)
            crossPosition = height >= crossMax - crossMin ? crossMin : clamp(top, crossMin, crossMax - height)
        case .picture, .scribble:
            // Keep proportions: a picture or scribble too tall for the cross space narrows instead.
            let aspect = element.aspect ?? 1
            if width * aspect > crossMax - crossMin { width = (crossMax - crossMin) / aspect }
            height = width * aspect
            pointSize = 0
            crossPosition = clamp(originCross, crossMin, crossMax - height)
        }
        let alongPosition = clamp(originAlong, alongMin, alongMax - width)
        let frame = sideways
            ? CGRect(x: crossPosition, y: alongPosition, width: height, height: width)
            : CGRect(x: alongPosition, y: crossPosition, width: width, height: height)
        return ElementLayout(frameMM: frame, contentSizeMM: CGSize(width: width, height: height),
                             effectivePointSize: pointSize)
    }

    /// The largest size ≤ the requested size, in 0.5 pt steps, whose wrapped text fits `availableMM`.
    private static func fittedPointSize(for text: TextContent, widthMM: Double, availableMM: Double) -> Double {
        let requested = clamp(text.pointSize, TextContent.minimumPointSize, TextContent.maximumPointSize)
        if textHeightMM(text, pointSize: requested, widthMM: widthMM) <= availableMM { return requested }
        // Binary search over sizes requested − k × step, k in 1...maxK.
        var low = 1, high = Int(((requested - TextContent.minimumPointSize) / fitStep).rounded(.down))
        guard high >= 1 else { return requested }
        var best = high
        while low <= high {
            let mid = (low + high) / 2
            if textHeightMM(text, pointSize: requested - Double(mid) * fitStep, widthMM: widthMM) <= availableMM {
                best = mid
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
        return requested - Double(best) * fitStep
    }

    /// The width of the longest line at the requested size when lines may run up to `maximumMM`, rounded up
    /// to whole dots. Empty text is a caret's width wide so the box can still be tapped.
    static func naturalWidthMM(_ text: TextContent, maximumMM: Double) -> Double {
        let pointSize = clamp(text.pointSize, TextContent.minimumPointSize, TextContent.maximumPointSize)
        let font = FontCatalog.ctFont(text.font, pointSize: pointSize * dotsPerPoint)
        guard !text.text.isEmpty else {
            return ((CTFontGetAscent(font) + CTFontGetDescent(font)) / 2).rounded(.up) / LabelGeometry.dotsPerMM
        }
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText(text, font: font))
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(), nil,
            CGSize(width: maximumMM * LabelGeometry.dotsPerMM, height: .greatestFiniteMagnitude), nil)
        // One spare dot so the measured line never wraps when laid out at exactly this width.
        return (suggested.width.rounded(.up) + 1) / LabelGeometry.dotsPerMM
    }

    static func textHeightMM(_ text: TextContent, pointSize: Double, widthMM: Double) -> Double {
        let font = FontCatalog.ctFont(text.font, pointSize: pointSize * dotsPerPoint)
        let lineHeight = (CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)).rounded(.up)
        guard !text.text.isEmpty else { return lineHeight / LabelGeometry.dotsPerMM }
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText(text, font: font))
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(), nil,
            CGSize(width: widthMM * LabelGeometry.dotsPerMM, height: .greatestFiniteMagnitude), nil)
        var height = suggested.height.rounded(.up)
        // A trailing newline starts a line the framesetter does not measure; count it so the caret has room.
        if text.text.hasSuffix("\n") { height += lineHeight }
        return max(height, lineHeight) / LabelGeometry.dotsPerMM
    }

    static func attributedText(_ text: TextContent, font: CTFont) -> CFAttributedString {
        var alignment: CTTextAlignment = switch text.alignment {
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
        return CFAttributedStringCreate(nil, text.text as CFString, attributes as CFDictionary)
    }

    // MARK: Editing

    /// How far a set of footprints, dragged by `delta`, may move: the union's top-left is snapped to the
    /// grid, then the union is kept inside the printable area. Every member moves by the returned amount.
    static func movedDelta(of frames: [CGRect], by delta: CGSize, grid: GridStep,
                           in geometry: LabelGeometry) -> CGSize {
        guard let first = frames.first else { return .zero }
        let union = frames.dropFirst().reduce(first) { $0.union($1) }
        let printable = geometry.printableRect
        let x = clamp(snap(union.minX + delta.width, grid), printable.minX, printable.maxX - union.width)
        let y = clamp(snap(union.minY + delta.height, grid), printable.minY, printable.maxY - union.height)
        return CGSize(width: x - union.minX, height: y - union.minY)
    }

    /// The content width for an element whose far edge (right, or bottom when sideways) is dragged by
    /// `delta` from `startWidth`.
    static func resizedWidth(_ element: LabelElement, from startWidth: Double, by delta: Double, grid: GridStep,
                             in geometry: LabelGeometry) -> Double {
        let printable = geometry.printableRect
        let sideways = element.rotation.isSideways
        let start = sideways ? element.originMM.y : element.originMM.x
        let limit = sideways ? printable.maxY : printable.maxX
        let farEdge = min(snap(start + startWidth + delta, grid), limit)
        return max(LabelElement.minimumWidthMM, farEdge - start)
    }

    /// The document with every element's stored origin pulled inside the printable area. Widths are kept as set:
    /// an item turned sideways lays out narrower but is as wide as before when it turns back (S29).
    static func normalized(_ document: LabelDocument) -> LabelDocument {
        var doc = document
        let geometry = doc.geometry
        for index in doc.elements.indices {
            doc.elements[index].originMM = layout(doc.elements[index], in: geometry).frameMM.origin
        }
        return doc
    }

    /// The width an element is laid out at, which the width handle, Scale and pinch start from (S29).
    static func shownWidthMM(_ element: LabelElement, in geometry: LabelGeometry) -> Double {
        layout(element, in: geometry).contentSizeMM.width
    }

    // MARK: Helpers

    static func snap(_ value: Double, _ grid: GridStep) -> Double {
        guard grid != .off else { return value }
        return (value / grid.rawValue).rounded() * grid.rawValue
    }

    static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(max(value, low), max(low, high))
    }
}
