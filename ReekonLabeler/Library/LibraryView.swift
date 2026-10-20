import SwiftData
import SwiftUI
import UIKit

/// Saved labels, newest first. Tap to open, swipe to delete (undoable), long-press to rename.
struct LibraryView: View {
    let library: LabelLibrary
    let open: (UUID, String, LabelDocument) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedLabel.modified, order: .reverse) private var labels: [SavedLabel]
    @State private var renaming: SavedLabel?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(labels) { label in
                    Button {
                        guard let doc = label.document else { return }
                        open(label.id, label.name, doc)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            thumbnail(label)
                            VStack(alignment: .leading) {
                                Text(label.name).foregroundStyle(.primary)
                                Text(label.modified, format: .relative(presentation: .named))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") { newName = label.name; renaming = label }
                    }
                }
                .onDelete { offsets in
                    for id in offsets.map({ labels[$0].id }) { try? library.delete(id) }
                }
            }
            .overlay {
                if labels.isEmpty {
                    ContentUnavailableView("No Saved Labels", systemImage: "tag",
                                           description: Text("Save a label to reuse it."))
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Undo", systemImage: "arrow.uturn.backward") { library.undoManager?.undo() }
                }
            }
            .alert("Rename Label", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Rename") { if let renaming { try? library.rename(renaming.id, to: newName) } }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ label: SavedLabel) -> some View {
        if let data = label.thumbnailPNG, let image = UIImage(data: data) {
            Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
                .frame(width: 64, height: 40)
                .background(Theme.labelStock)
                .border(Theme.labelEdge)
        } else {
            Image(systemName: "tag").frame(width: 64, height: 40)
        }
    }
}
