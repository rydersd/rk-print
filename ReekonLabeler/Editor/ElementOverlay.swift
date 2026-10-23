import SwiftUI

/// One element's hit area on the canvas: tap to select (and type, for text), drag with Move to move the selection
/// (or with Scale to scale it), drag the handle to change width. Text and pictures are drawn by the
/// bitmap underneath; the inline field's text is clear so only the caret and selection show over it.
struct ElementOverlay: View {
    let editor: LabelEditor
    let element: LabelElement
    let index: Int
    let scale: Double

    @State private var isDragging = false
    /// The tool the current drag started in, so its undo step is named for what it did.
    @State private var dragScales = false
    @State private var isResizing = false
    /// True while a drag or resize is live. SwiftUI resets it when a gesture is cancelled (a call, Notification
    /// Center, the tool changing mid-drag), which never reaches `onEnded`; the reset ends the undo step instead.
    @GestureState private var dragLive = false
    @GestureState private var resizeLive = false
    @FocusState private var isFocused: Bool

    private var layout: ElementLayout? { editor.layouts[element.id] }
    private var isSelected: Bool { editor.selection.contains(element.id) }
    private var isEditing: Bool { editor.editingID == element.id }
    /// The width handle belongs to a lone, ungrouped element (S5).
    private var showsHandle: Bool { editor.selectedID == element.id && element.groupID == nil }

    var body: some View {
        let frame = layout?.frameMM ?? CGRect(origin: element.originMM, size: CGSize(width: element.widthMM, height: 4))
        let screen = CGRect(x: frame.minX * scale, y: frame.minY * scale,
                            width: frame.width * scale, height: frame.height * scale)

        ZStack {
            Rectangle()
                .fill(.clear)
                .contentShape(.rect)
                .accessibilityElement()
                .accessibilityIdentifier("block-\(index)")
                .accessibilityValue(Text(verbatim: "\(accessibilityText)|ink:\(ink(in: frame))")) // verbatim: no "1,950"
            if isEditing, let text = element.textContent { field(text) }
            if isSelected {
                Rectangle()
                    .strokeBorder(Theme.selection,
                                  style: StrokeStyle(lineWidth: 1, dash: isEditing ? [] : element.groupID == nil ? [4, 3] : [1, 3]))
                    .allowsHitTesting(false)
                if showsHandle { handle(screenSize: screen.size) }
            }
        }
        .frame(width: screen.width, height: screen.height)
        .offset(x: screen.minX, y: screen.minY)
        .onTapGesture { editor.tap(element.id) }
        // Only the Adjust tools arrange things (S13); in Type a drag on text belongs to the text field.
        .gesture(move, isEnabled: editor.tool.selects)
        .onChange(of: dragLive) { _, live in if !live { endDrag() } }
        .onChange(of: resizeLive) { _, live in if !live { endResize() } }
    }

    private var accessibilityText: String {
        element.textContent?.text ?? (element.scribble != nil ? "scribble" : "picture")
    }

    /// Inline editor sized and turned to match the rendered text, so the caret sits on the printed glyphs.
    private func field(_ text: TextContent) -> some View {
        let pointSize = (layout?.effectivePointSize ?? text.pointSize) * 25.4 / 72 * scale
        let content = layout?.contentSizeMM ?? CGSize(width: element.widthMM, height: 4)
        return TextField("", text: Binding(get: { text.text }, set: { editor.setText($0, for: element.id) }),
                         axis: .vertical)
            .font(Font(FontCatalog.uiFont(text.font, pointSize: pointSize)))
            .multilineTextAlignment(text.alignment.textAlignment)
            .foregroundStyle(.clear)
            .tint(Theme.selection)
            .focused($isFocused)
            .frame(width: content.width * scale, height: content.height * scale, alignment: .topLeading)
            .rotationEffect(.degrees(Double(element.rotation.rawValue)))
            .accessibilityIdentifier("blockField-\(index)")
            .onAppear { isFocused = true }
            .onChange(of: isFocused) { _, focused in
                if !focused, editor.editingID == element.id { editor.editingID = nil }
            }
    }

    /// Text: a bar on the edge where its lines end (right, or bottom when sideways). Pictures: a corner dot.
    private func handle(screenSize: CGSize) -> some View {
        let sideways = element.rotation.isSideways
        let alignment: Alignment = !element.isText ? .bottomTrailing : sideways ? .bottom : .trailing
        let edge = sideways ? screenSize.width : screenSize.height
        let bar = min(max(edge * 0.6, 14), 28)
        return Group {
            if element.isText {
                Capsule()
                    .fill(Theme.handle)
                    .frame(width: sideways ? bar : 6, height: sideways ? 6 : bar)
            } else {
                Circle()
                    .fill(Theme.handle)
                    .frame(width: 12, height: 12)
            }
        }
        .frame(width: 28, height: 28) // 28 pt touch target
        .contentShape(.rect)
        .offset(x: alignment == .bottom ? 0 : 14, y: alignment == .trailing ? 0 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .gesture(resize)
        .accessibilityIdentifier("widthHandle-\(index)")
    }

    private var move: some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($dragLive) { _, live, _ in live = true }
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragScales = editor.tool == .scale
                    editor.beginGesture()
                }
                let translation = CGSize(width: value.translation.width / scale,
                                         height: value.translation.height / scale)
                if dragScales {
                    editor.scaleSelection(grabbing: element.id, translationMM: translation)
                } else {
                    editor.moveSelection(grabbing: element.id, translationMM: translation)
                }
            }
            .onEnded { _ in endDrag() }
    }

    private func endDrag() {
        guard isDragging else { return }
        isDragging = false
        editor.endGesture(action: dragScales ? "Scale" : "Move")
    }

    private var resize: some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($resizeLive) { _, live, _ in live = true }
            .onChanged { value in
                if !isResizing { isResizing = true; editor.beginGesture() }
                let along = element.rotation.isSideways ? value.translation.height : value.translation.width
                editor.resizeElement(element.id, deltaMM: along / scale)
            }
            .onEnded { _ in endResize() }
    }

    private func endResize() {
        guard isResizing else { return }
        isResizing = false
        editor.endGesture(action: element.isText ? "Resize Text" : "Resize Picture")
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
