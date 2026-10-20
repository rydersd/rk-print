import SwiftUI

/// What the crop screen is cropping: a newly picked picture (added on Done) or one already on the label.
struct CropRequest: Identifiable {
    let id = UUID()
    var picture: PictureContent
    /// The element being re-cropped; nil for a picture that is not on the label yet.
    var elementID: UUID?
    /// The tallest crop (height ÷ width) that still prints at least 2 mm wide on the current label.
    var maximumAspect: Double
}

/// Free-aspect crop over the whole original picture (S8). Corners and edges resize, the middle moves.
/// The rectangle is kept in unit coordinates of the picture so it survives any display size.
struct CropView: View {
    let request: CropRequest
    let onDone: (CGRect) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var crop: CGRect
    @State private var dragStart: CGRect?

    init(request: CropRequest, onDone: @escaping (CGRect) -> Void) {
        self.request = request
        self.onDone = onDone
        _crop = State(initialValue: request.picture.crop)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let fitted = fittedRect(in: proxy.size.insetBy(16))
                ZStack(alignment: .topLeading) {
                    if let image = PictureRasterizer.decoded(request.picture) {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .frame(width: fitted.width, height: fitted.height)
                            .offset(x: fitted.minX, y: fitted.minY)
                    }
                    cropOverlay(in: fitted)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .background(Theme.canvasBackground)
            .navigationTitle("Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(crop)
                        dismiss()
                    }
                    .accessibilityIdentifier("cropDoneButton")
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Reset", systemImage: "arrow.counterclockwise") { crop = Self.full }
                        .disabled(crop == Self.full)
                }
            }
        }
    }

    private static let full = CGRect(x: 0, y: 0, width: 1, height: 1)

    private var pixelAspect: Double {
        Double(request.picture.pixelHeight) / Double(max(request.picture.pixelWidth, 1))
    }

    /// The picture aspect-fitted and centred in `size`, offset by the 16 pt margin.
    private func fittedRect(in size: CGSize) -> CGRect {
        let aspect = Double(request.picture.pixelHeight) / Double(max(request.picture.pixelWidth, 1))
        let width = min(size.width, size.height / aspect)
        let height = width * aspect
        return CGRect(x: 16 + (size.width - width) / 2, y: 16 + (size.height - height) / 2, width: width, height: height)
    }

    private func cropOverlay(in fitted: CGRect) -> some View {
        let rect = CGRect(x: fitted.minX + crop.minX * fitted.width, y: fitted.minY + crop.minY * fitted.height,
                          width: crop.width * fitted.width, height: crop.height * fitted.height)
        return ZStack(alignment: .topLeading) {
            // Dim what will be cut away.
            Path { path in
                path.addRect(fitted)
                path.addRect(rect)
            }
            .fill(Theme.cropDim, style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            Rectangle()
                .strokeBorder(Theme.selection, lineWidth: 2)
                .contentShape(.rect)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .gesture(dragGesture(.move, fitted: fitted))
                .accessibilityIdentifier("cropRect")

            ForEach(CropHandle.allCases.filter { $0 != .move }, id: \.self) { handle in
                let point = handle.point(in: rect)
                Circle()
                    .fill(Theme.handle)
                    .frame(width: 14, height: 14)
                    .frame(width: 32, height: 32) // touch target
                    .contentShape(.rect)
                    .offset(x: point.x - 16, y: point.y - 16)
                    .gesture(dragGesture(handle, fitted: fitted))
            }
        }
    }

    private func dragGesture(_ handle: CropHandle, fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = dragStart ?? crop
                if dragStart == nil { dragStart = crop }
                let delta = CGSize(width: value.translation.width / fitted.width,
                                   height: value.translation.height / fitted.height)
                crop = handle.adjust(start, by: delta, pixelAspect: pixelAspect,
                                     maximumAspect: request.maximumAspect)
            }
            .onEnded { _ in dragStart = nil }
    }
}

/// A part of the crop rectangle that can be dragged. Adjustments stay inside the picture and never shrink a
/// side below `PictureContent.minimumCropFraction`.
enum CropHandle: CaseIterable {
    case move, top, bottom, left, right, topLeft, topRight, bottomLeft, bottomRight

    func point(in rect: CGRect) -> CGPoint {
        let x = movesLeft ? rect.minX : movesRight ? rect.maxX : rect.midX
        let y = movesTop ? rect.minY : movesBottom ? rect.maxY : rect.midY
        return CGPoint(x: x, y: y)
    }

    /// `start` dragged by `delta`, stopping before the crop's height ÷ width (in pixels, using `pixelAspect`
    /// = pixel height ÷ pixel width) passes `maximumAspect`, or the start's aspect when that is already past it.
    func adjust(_ start: CGRect, by delta: CGSize, pixelAspect: Double, maximumAspect: Double) -> CGRect {
        func aspect(_ rect: CGRect) -> Double { rect.height / rect.width * pixelAspect }
        let limit = max(maximumAspect, aspect(start))
        let full = adjust(start, by: delta)
        guard aspect(full) > limit else { return full }
        // Find the furthest point along the drag that stays inside the limit, so the handle stops at it.
        var low = 0.0, high = 1.0
        for _ in 0..<20 {
            let mid = (low + high) / 2
            let rect = adjust(start, by: CGSize(width: delta.width * mid, height: delta.height * mid))
            if aspect(rect) > limit { high = mid } else { low = mid }
        }
        return adjust(start, by: CGSize(width: delta.width * low, height: delta.height * low))
    }

    /// `start` with this handle dragged by `delta`, both in unit coordinates of the picture.
    func adjust(_ start: CGRect, by delta: CGSize) -> CGRect {
        let minSide = PictureContent.minimumCropFraction
        if self == .move {
            let x = min(max(start.minX + delta.width, 0), 1 - start.width)
            let y = min(max(start.minY + delta.height, 0), 1 - start.height)
            return CGRect(x: x, y: y, width: start.width, height: start.height)
        }
        var minX = start.minX, maxX = start.maxX, minY = start.minY, maxY = start.maxY
        if movesLeft { minX = min(max(minX + delta.width, 0), maxX - minSide) }
        if movesRight { maxX = max(min(maxX + delta.width, 1), minX + minSide) }
        if movesTop { minY = min(max(minY + delta.height, 0), maxY - minSide) }
        if movesBottom { maxY = max(min(maxY + delta.height, 1), minY + minSide) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private var movesLeft: Bool { self == .left || self == .topLeft || self == .bottomLeft }
    private var movesRight: Bool { self == .right || self == .topRight || self == .bottomRight }
    private var movesTop: Bool { self == .top || self == .topLeft || self == .topRight }
    private var movesBottom: Bool { self == .bottom || self == .bottomLeft || self == .bottomRight }
}

private extension CGSize {
    func insetBy(_ inset: Double) -> CGSize {
        CGSize(width: max(0, width - 2 * inset), height: max(0, height - 2 * inset))
    }
}
