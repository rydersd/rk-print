import SwiftUI

/// One text block's hit area on the canvas: tap to select and type, drag to move, drag the right-edge
/// handle to change width. The text itself is drawn by the bitmap underneath; the inline field's text
/// is clear so only the caret and selection show over it.
struct BlockOverlay: View {
    let editor: LabelEditor
    let block: TextBlock
    let index: Int
    let scale: Double

    @State private var isDragging = false
    @State private var isResizing = false
    @FocusState private var isFocused: Bool

    private var layout: BlockLayout? { editor.layouts[block.id] }
    private var isSelected: Bool { editor.selectedID == block.id }
    private var isEditing: Bool { editor.editingID == block.id }

    var body: some View {
        let frame = layout?.frameMM ?? CGRect(origin: block.originMM, size: CGSize(width: block.widthMM, height: 4))
        let screen = CGRect(x: frame.minX * scale, y: frame.minY * scale,
                            width: frame.width * scale, height: frame.height * scale)

        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.clear)
                .contentShape(.rect)
                .accessibilityElement()
                .accessibilityIdentifier("block-\(index)")
                .accessibilityValue(Text(verbatim: "\(block.text)|ink:\(ink(in: frame))")) // verbatim: no "1,950"
            if isEditing { field }
            if isSelected {
                Rectangle()
                    .strokeBorder(Theme.selection, style: StrokeStyle(lineWidth: 1, dash: isEditing ? [] : [4, 3]))
                    .allowsHitTesting(false)
                widthHandle(height: screen.height)
            }
        }
        .frame(width: screen.width, height: screen.height)
        .offset(x: screen.minX, y: screen.minY)
        .onTapGesture { editor.select(block.id) }
        .gesture(move)
    }

    /// Inline editor sized to match the rendered text, so the caret sits on the printed glyphs.
    private var field: some View {
        let pointSize = (layout?.effectivePointSize ?? block.pointSize) * 25.4 / 72 * scale
        return TextField("", text: Binding(get: { block.text }, set: { editor.setText($0, for: block.id) }),
                         axis: .vertical)
            .font(Font(FontCatalog.uiFont(block.font, pointSize: pointSize)))
            .multilineTextAlignment(block.alignment.textAlignment)
            .foregroundStyle(.clear)
            .tint(Theme.selection)
            .focused($isFocused)
            .accessibilityIdentifier("blockField-\(index)")
            .onAppear { isFocused = true }
            .onChange(of: isFocused) { _, focused in
                if !focused, editor.editingID == block.id { editor.editingID = nil }
            }
    }

    private func widthHandle(height: Double) -> some View {
        Capsule()
            .fill(Theme.handle)
            .frame(width: 6, height: min(max(height * 0.6, 14), 28))
            .frame(width: 28, height: max(height, 28)) // 28 pt touch target
            .contentShape(.rect)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .offset(x: 14)
            .gesture(resize)
            .accessibilityIdentifier("widthHandle-\(index)")
    }

    private var move: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    editor.selectedID = block.id
                    editor.beginGesture()
                }
                editor.moveBlock(block.id, translationMM: CGSize(width: value.translation.width / scale,
                                                                 height: value.translation.height / scale))
            }
            .onEnded { _ in
                isDragging = false
                editor.endGesture(action: "Move Text")
            }
    }

    private var resize: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if !isResizing { isResizing = true; editor.beginGesture() }
                editor.resizeBlock(block.id, deltaMM: value.translation.width / scale)
            }
            .onEnded { _ in
                isResizing = false
                editor.endGesture(action: "Resize Text")
            }
    }

    private func ink(in frameMM: CGRect) -> Int {
        editor.bitmap.inkCount(inDots: editor.document.geometry.dotRect(forMM: frameMM))
    }
}

extension TextAlignmentOption {
    var textAlignment: TextAlignment {
        switch self {
        case .left: .leading
        case .center: .center
        case .right: .trailing
        }
    }
}
