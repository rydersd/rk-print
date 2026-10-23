import SwiftUI

/// Favourite families first; "More Fonts" lists every installed family, each previewed in itself.
struct FontPickerSheet: View {
    let current: FontSpec
    let choose: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Favourites") {
                    ForEach(FontCatalog.favourites, id: \.self, content: row)
                }
                Section {
                    NavigationLink("More Fonts") { allFonts }
                }
            }
            .navigationTitle("Font")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private var allFonts: some View {
        List(FontCatalog.allFamilies.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) },
             id: \.self, rowContent: row)
            .searchable(text: $search)
            .navigationTitle("All Fonts")
    }

    private func row(_ family: String) -> some View {
        Button {
            choose(family)
            dismiss()
        } label: {
            HStack {
                Text(family)
                    .font(Font(FontCatalog.uiFont(FontSpec(family: family, face: FontCatalog.defaultFace(for: family, matching: current)),
                                                  pointSize: 18)))
                    .foregroundStyle(.primary)
                Spacer()
                if family == current.family { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }
}
