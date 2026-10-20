import SwiftUI

/// Font, weight, size and alignment for the selected block.
struct InspectorView: View {
    let editor: LabelEditor
    let showFonts: () -> Void

    var body: some View {
        if let block = editor.selectedBlock {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button(action: showFonts) {
                        HStack {
                            Text(block.font.family).lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down").font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("fontFamilyButton")

                    Menu {
                        Picker("Weight", selection: faceBinding(block)) {
                            ForEach(FontCatalog.faces(for: block.font.family)) { Text($0.name).tag($0.id) }
                        }
                    } label: {
                        Text(FontCatalog.displayName(of: block.font)).lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 12) {
                    Text(sizeLabel(block))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Stepper("Size", value: sizeBinding(block), in: TextBlock.minimumPointSize...TextBlock.maximumPointSize, step: 1)
                        .labelsHidden()
                        .accessibilityIdentifier("sizeStepper")
                }

                HStack(spacing: 12) {
                    Picker("Alignment", selection: alignmentBinding(block)) {
                        Image(systemName: "text.alignleft").tag(TextAlignmentOption.left)
                        Image(systemName: "text.aligncenter").tag(TextAlignmentOption.center)
                        Image(systemName: "text.alignright").tag(TextAlignmentOption.right)
                    }
                    .pickerStyle(.segmented)

                    Button("Delete", systemImage: "trash", role: .destructive) { editor.deleteSelected() }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("deleteBlockButton")
                }
            }
            .padding(16)
            .background(.bar)
        }
    }

    /// "24 pt", or "24 pt (fits at 17)" when shrink-to-fit is drawing it smaller.
    private func sizeLabel(_ block: TextBlock) -> String {
        let requested = block.pointSize.formatted(.number.precision(.fractionLength(0...1)))
        guard let fitted = editor.layouts[block.id]?.effectivePointSize, fitted < block.pointSize else {
            return "\(requested) pt"
        }
        return "\(requested) pt (fits at \(fitted.formatted(.number.precision(.fractionLength(0...1)))))"
    }

    private func faceBinding(_ block: TextBlock) -> Binding<String> {
        Binding(get: { block.font.face }, set: { face in editor.updateBlock(block.id, action: "Weight") { $0.font.face = face } })
    }

    private func sizeBinding(_ block: TextBlock) -> Binding<Double> {
        Binding(get: { block.pointSize }, set: { size in editor.updateBlock(block.id, action: "Text Size") { $0.pointSize = size } })
    }

    private func alignmentBinding(_ block: TextBlock) -> Binding<TextAlignmentOption> {
        Binding(get: { block.alignment }, set: { a in editor.updateBlock(block.id, action: "Alignment") { $0.alignment = a } })
    }
}
