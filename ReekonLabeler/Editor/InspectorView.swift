import SwiftUI

/// Controls for the selection. Text settings apply to every selected text element (S5); picture settings
/// show for a single picture (S7, S8); rotate, group and delete apply to the whole selection.
struct InspectorView: View {
    let editor: LabelEditor
    let showFonts: () -> Void
    let crop: (LabelElement) -> Void

    var body: some View {
        if !editor.selection.isEmpty {
            VStack(spacing: 12) {
                if let text = editor.selectedElements.compactMap(\.textContent).first { textRows(text) }
                if let element = editor.selectedElement, let picture = element.picture {
                    pictureRows(element, picture)
                }
                arrangeRow
            }
            .padding(16)
            .background(.bar)
        }
    }

    // MARK: Text

    /// `text` is the first selected text element's settings, shown as the current value.
    @ViewBuilder
    private func textRows(_ text: TextContent) -> some View {
        HStack(spacing: 12) {
            Button(action: showFonts) {
                HStack {
                    Text(text.font.family).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("fontFamilyButton")

            Menu {
                Picker("Weight", selection: textBinding(text.font.face, action: "Weight") { $0.font.face = $1 }) {
                    ForEach(FontCatalog.faces(for: text.font.family)) { Text($0.name).tag($0.id) }
                }
            } label: {
                Text(FontCatalog.displayName(of: text.font)).lineLimit(1)
            }
            .buttonStyle(.bordered)
        }

        HStack(spacing: 12) {
            Text(sizeLabel(text))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("Alignment", selection: textBinding(text.alignment, action: "Alignment") { $0.alignment = $1 }) {
                Image(systemName: "text.alignleft").tag(TextAlignmentOption.left)
                Image(systemName: "text.aligncenter").tag(TextAlignmentOption.center)
                Image(systemName: "text.alignright").tag(TextAlignmentOption.right)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 140)
            Stepper("Size", value: textBinding(text.pointSize, action: "Text Size") { $0.pointSize = $1 },
                    in: TextContent.minimumPointSize...TextContent.maximumPointSize, step: 1)
                .labelsHidden()
                .accessibilityIdentifier("sizeStepper")
        }
    }

    /// "24 pt", or "24 pt (fits at 17)" when shrink-to-fit is drawing the first selected text smaller.
    private func sizeLabel(_ text: TextContent) -> String {
        let requested = text.pointSize.formatted(.number.precision(.fractionLength(0...1)))
        let id = editor.selectedElements.first { $0.isText }?.id
        guard let fitted = id.flatMap({ editor.layouts[$0]?.effectivePointSize }), fitted < text.pointSize else {
            return "\(requested) pt"
        }
        return "\(requested) pt (fits at \(fitted.formatted(.number.precision(.fractionLength(0...1)))))"
    }

    /// Shows `value` and writes changes to every selected text element as one undo step.
    private func textBinding<Value>(_ value: Value, action: String,
                                    _ apply: @escaping (inout TextContent, Value) -> Void) -> Binding<Value> {
        Binding(get: { value }, set: { newValue in
            editor.updateSelected(action: action) { element in
                guard var text = element.textContent else { return }
                apply(&text, newValue)
                element.textContent = text
            }
        })
    }

    // MARK: Picture

    @ViewBuilder
    private func pictureRows(_ element: LabelElement, _ picture: PictureContent) -> some View {
        HStack(spacing: 12) {
            Toggle("Line art", isOn: Binding(get: { picture.lineArt }, set: { on in
                editor.updateElement(element.id, action: "Line Art") { $0.picture?.lineArt = on }
            }))
            .accessibilityIdentifier("lineArtToggle")
            Button("Crop", systemImage: "crop") { crop(element) }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("cropButton")
        }
        HStack(spacing: 12) {
            Image(systemName: "sun.min").accessibilityHidden(true)
            // One undo step per slide: the gesture spans every change until the thumb is let go.
            Slider(value: Binding(get: { picture.brightness }, set: { value in
                editor.updateElement(element.id, action: "Brightness") { $0.picture?.brightness = value }
            }), in: -1...1) { editing in
                if editing { editor.beginGesture() } else { editor.endGesture(action: "Brightness") }
            }
            .accessibilityLabel("Brightness")
            .accessibilityIdentifier("brightnessSlider")
            Image(systemName: "sun.max").accessibilityHidden(true)
        }
    }

    // MARK: Arrange

    private var arrangeRow: some View {
        HStack(spacing: 12) {
            Button("Rotate 90°", systemImage: "rotate.right") { editor.rotateSelection() }
                .accessibilityIdentifier("rotateElementButton")
            if editor.canGroup {
                Button("Group", systemImage: "square.on.square") { editor.group() }
                    .accessibilityIdentifier("groupButton")
            } else if editor.selectedElements.contains(where: { $0.groupID != nil }) {
                Button("Ungroup", systemImage: "square.on.square.dashed") { editor.ungroup() }
                    .accessibilityIdentifier("ungroupButton")
            }
            Spacer()
            Button("Delete", systemImage: "trash", role: .destructive) { editor.deleteSelected() }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("deleteBlockButton")
        }
        .buttonStyle(.bordered)
    }
}
