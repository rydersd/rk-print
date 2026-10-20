import SwiftUI

/// The label at true proportions. What you see is the 1-bit bitmap the printer gets; elements are
/// interactive overlays on top. All gesture maths converts screen points to label mm via `scale`.
struct CanvasView: View {
    let editor: LabelEditor
    @State private var isPinching = false

    var body: some View {
        GeometryReader { proxy in
            let geometry = editor.document.geometry
            let label = geometry.labelSizeMM
            let scale = min(proxy.size.width / label.width, proxy.size.height / label.height)
            let size = CGSize(width: label.width * scale, height: label.height * scale)

            ZStack(alignment: .topLeading) {
                stock(geometry: geometry, scale: scale)
                    .accessibilityIdentifier("labelCanvas")
                if let image = editor.image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: geometry.printableRect.width * scale, height: geometry.printableRect.height * scale)
                        .offset(x: geometry.printableRect.minX * scale, y: geometry.printableRect.minY * scale)
                        .allowsHitTesting(false)
                }
                ForEach(Array(editor.document.elements.enumerated()), id: \.element.id) { index, element in
                    ElementOverlay(editor: editor, element: element, index: index, scale: scale)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: 1.5 * scale))
            .overlay { RoundedRectangle(cornerRadius: 1.5 * scale).strokeBorder(Theme.labelEdge) }
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            .gesture(pinch)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .contentShape(.rect)
            .onTapGesture { editor.clearSelection() }
        }
    }

    /// White stock, hatched where the head cannot print, and grid dots inside the printable area.
    private func stock(geometry: LabelGeometry, scale: Double) -> some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.labelStock))
            let printable = CGRect(x: geometry.printableRect.minX * scale, y: geometry.printableRect.minY * scale,
                                   width: geometry.printableRect.width * scale, height: geometry.printableRect.height * scale)
            var hatch = Path()
            let step = 6.0
            var x = -size.height
            while x < size.width {
                hatch.move(to: CGPoint(x: x, y: size.height))
                hatch.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += step
            }
            var outside = Path(CGRect(origin: .zero, size: size))
            outside.addRect(printable)
            context.drawLayer { layer in
                layer.clip(to: outside, style: FillStyle(eoFill: true))
                layer.stroke(hatch, with: .color(Theme.unprintableHatch), lineWidth: 1)
            }

            let grid = editor.document.grid.rawValue
            guard grid > 0, grid * scale >= 6 else { return }
            var dots = Path()
            var gy = (geometry.printableRect.minY / grid).rounded(.up) * grid
            while gy <= geometry.printableRect.maxY {
                var gx = (geometry.printableRect.minX / grid).rounded(.up) * grid
                while gx <= geometry.printableRect.maxX {
                    dots.addEllipse(in: CGRect(x: gx * scale - 0.75, y: gy * scale - 0.75, width: 1.5, height: 1.5))
                    gx += grid
                }
                gy += grid
            }
            context.fill(dots, with: .color(Theme.gridDot))
        }
    }

    /// Pinch anywhere on the label scales the selection: text size, or picture width.
    private var pinch: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard !editor.selection.isEmpty else { return }
                if !isPinching { isPinching = true; editor.beginGesture() }
                editor.scaleSelection(by: value.magnification)
            }
            .onEnded { _ in
                isPinching = false
                editor.endGesture(action: "Scale")
            }
    }
}
