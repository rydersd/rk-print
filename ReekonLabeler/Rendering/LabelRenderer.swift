import CoreGraphics
import CoreText
import Foundation

/// Draws a label into the 1-bit bitmap that both the canvas and the printer use.
/// The bitmap covers the printable area only, at 8 dots per mm, in label-space orientation.
nonisolated enum LabelRenderer {
    static func render(_ document: LabelDocument, layouts: [UUID: ElementLayout]? = nil) -> Bitmap {
        let geometry = document.geometry
        let width = geometry.bitmapWidth, height = geometry.bitmapHeight
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return Bitmap(width: max(width, 0), height: max(height, 0)) }

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // The printer has no gray: draw hard edges so the threshold below matches what was drawn.
        context.setShouldAntialias(false)
        context.setAllowsAntialiasing(false)
        context.setShouldSmoothFonts(false)
        context.interpolationQuality = .none

        for element in document.elements {
            let layout = layouts?[element.id] ?? LayoutEngine.layout(element, in: geometry)
            draw(element, layout: layout, geometry: geometry, bitmapHeight: height, in: context)
        }

        guard let data = context.data else { return Bitmap(width: width, height: height) }
        let gray = data.bindMemory(to: UInt8.self, capacity: width * height)
        var bitmap = Bitmap(width: width, height: height)
        for i in 0..<(width * height) where gray[i] < 128 { bitmap.dots[i] = 1 }
        return bitmap
    }

    /// Draws one element's content centred in its footprint, turned clockwise by its rotation.
    private static func draw(_ element: LabelElement, layout: ElementLayout, geometry: LabelGeometry,
                             bitmapHeight: Int, in context: CGContext) {
        let footprint = geometry.dotRect(forMM: layout.frameMM)
        let contentWidth = (layout.contentSizeMM.width * LabelGeometry.dotsPerMM).rounded()
        let contentHeight = (layout.contentSizeMM.height * LabelGeometry.dotsPerMM).rounded()
        guard contentWidth >= 1, contentHeight >= 1 else { return }
        // Whole-dot footprint so a quarter turn lands the content's corners on whole dots.
        let sideways = element.rotation.isSideways
        let originX = footprint.minX.rounded(), originY = footprint.minY.rounded()
        let footprintWidth = sideways ? contentHeight : contentWidth
        let footprintHeight = sideways ? contentWidth : contentHeight
        let content = CGRect(x: -contentWidth / 2, y: -contentHeight / 2, width: contentWidth, height: contentHeight)

        context.saveGState()
        defer { context.restoreGState() }
        // Core Graphics counts y from the bottom; a negative angle there is clockwise on the label.
        context.translateBy(x: originX + footprintWidth / 2, y: CGFloat(bitmapHeight) - originY - footprintHeight / 2)
        context.rotate(by: -CGFloat(element.rotation.rawValue) * .pi / 180)
        context.clip(to: content)

        switch element.content {
        case .text(let text):
            guard !text.text.isEmpty else { return }
            let font = FontCatalog.ctFont(text.font, pointSize: layout.effectivePointSize * LayoutEngine.dotsPerPoint)
            let framesetter = CTFramesetterCreateWithAttributedString(LayoutEngine.attributedText(text, font: font))
            // Lines are set from the top of the path; extend it downward so rounding never drops a last line.
            let path = CGPath(rect: CGRect(x: content.minX, y: content.minY - contentHeight,
                                           width: contentWidth, height: contentHeight * 2), transform: nil)
            CTFrameDraw(CTFramesetterCreateFrame(framesetter, CFRange(), path, nil), context)
        case .picture(let picture):
            guard let dots = PictureRasterizer.dots(for: picture, width: Int(contentWidth), height: Int(contentHeight))
            else { return }
            context.draw(dots, in: content)
        }
    }
}
