import SwiftUI

/// The label at true proportions. What you see is the 1-bit bitmap the printer gets; elements are
/// interactive overlays on top. All gesture maths converts screen points to label mm via `scale`.
struct CanvasView: View {
    let editor: LabelEditor
    @State private var isPinching = false
    /// Reset by SwiftUI when the pinch is cancelled, which skips `onEnded` (see ElementOverlay).
    @GestureState private var pinchLive = false

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
                        // The bitmap is opaque white where nothing prints; multiply lets the stock colour through.
                        .blendMode(.multiply)
                        .frame(width: geometry.printableRect.width * scale, height: geometry.printableRect.height * scale)
                        .offset(x: geometry.printableRect.minX * scale, y: geometry.printableRect.minY * scale)
                        .allowsHitTesting(false)
                }
                ForEach(Array(editor.document.elements.enumerated()), id: \.element.id) { index, element in
                    ElementOverlay(editor: editor, element: element, index: index, scale: scale)
                }
                // Above the elements, so drawing works over a photo (S14).
                if editor.tool == .draw { DrawSurface(editor: editor, scale: scale) }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: 1.5 * scale))
            .overlay { RoundedRectangle(cornerRadius: 1.5 * scale).strokeBorder(Theme.labelEdge) }
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            .gesture(pinch)
            .onChange(of: pinchLive) { _, live in if !live { endPinch() } }
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .contentShape(.rect)
            .onTapGesture { location in
                // The label is centred in the proxy; taps on the background around it only deselect.
                let mm = CGPoint(x: (location.x - (proxy.size.width - size.width) / 2) / scale,
                                 y: (location.y - (proxy.size.height - size.height) / 2) / scale)
                if CGRect(origin: .zero, size: label).contains(mm) {
                    editor.tapLabel(atMM: mm)
                } else {
                    editor.clearSelection()
                }
            }
        }
    }

    /// The stock in its colour (S16), hatched where the head cannot print, and grid dots inside the printable area.
    private func stock(geometry: LabelGeometry, scale: Double) -> some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.labelStock(editor.document.stock)))
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
            .updating($pinchLive) { _, live, _ in live = true }
            .onChanged { value in
                guard !editor.selection.isEmpty else { return }
                if !isPinching { isPinching = true; editor.beginGesture() }
                editor.scaleSelection(by: value.magnification)
            }
            .onEnded { _ in endPinch() }
    }

    private func endPinch() {
        guard isPinching else { return }
        isPinching = false
        editor.endGesture(action: "Scale")
    }
}

/// Draw (S14): a finger drag draws a stroke, shown live as a path and added to the label when the finger
/// lifts, where the bitmap takes over.
private struct DrawSurface: View {
    let editor: LabelEditor
    let scale: Double
    @State private var stroke: [CGPoint] = []
    @State private var startedAt: TimeInterval = 0
    /// Reset by SwiftUI when the stroke ends or is cancelled (which skips `onEnded`); either way the stroke is
    /// added once, so it neither vanishes nor joins the next one.
    @GestureState private var strokeLive = false

    /// Points closer than this to the last one add nothing a 203 dpi print could show.
    private static let minimumStepMM = 0.2

    var body: some View {
        Canvas { context, _ in
            guard let first = stroke.first else { return }
            var path = Path()
            path.move(to: CGPoint(x: first.x * scale, y: first.y * scale))
            for point in stroke.count > 1 ? Array(stroke.dropFirst()) : [first] {
                path.addLine(to: CGPoint(x: point.x * scale, y: point.y * scale))
            }
            context.stroke(path, with: .color(Theme.ink),
                           style: StrokeStyle(lineWidth: ScribbleContent.penWidthMM * scale, lineCap: .round,
                                              lineJoin: .round))
        }
        .contentShape(.rect)
        .gesture(draw)
        .onChange(of: strokeLive) { _, live in if !live { finishStroke() } }
        .accessibilityIdentifier("drawSurface")
    }

    private var draw: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($strokeLive) { _, live, _ in live = true }
            .onChanged { value in
                let point = CGPoint(x: value.location.x / scale, y: value.location.y / scale)
                if stroke.isEmpty { startedAt = ProcessInfo.processInfo.systemUptime }
                if let last = stroke.last, hypot(point.x - last.x, point.y - last.y) < Self.minimumStepMM { return }
                stroke.append(point)
            }
            .onEnded { _ in finishStroke() }
    }

    private func finishStroke() {
        guard !stroke.isEmpty else { return }
        editor.addStroke(stroke, startedAt: startedAt, endedAt: ProcessInfo.processInfo.systemUptime)
        stroke = []
    }
}
