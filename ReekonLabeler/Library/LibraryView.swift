import SwiftData
import SwiftUI
import UIKit

/// Every label, most recently edited first (S9). Tap to open, swipe to delete (undoable), long-press to
/// rename. An empty library offers New Label.
struct LibraryView: View {
    let library: LabelLibrary
    /// The label open in the editor, marked in the list.
    let openID: UUID?
    let open: (UUID, String, LabelDocument) -> Void
    let newLabel: () -> Void
    /// Tells the editor which labels were deleted, in case one is open.
    let deleted: (Set<UUID>) -> Void
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
                            Spacer()
                            if label.id == openID {
                                Text("Open").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("libraryLabel")
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") { newName = label.name; renaming = label }
                    }
                }
                .onDelete { offsets in
                    let ids = Set(offsets.map { labels[$0].id })
                    for id in ids { try? library.delete(id) }
                    deleted(ids)
                }
            }
            .overlay {
                if labels.isEmpty {
                    ContentUnavailableView {
                        Label("No Labels", systemImage: "tag")
                    } description: {
                        Text("Labels save here as you make them.")
                    } actions: {
                        newLabelButton.buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Undo", systemImage: "arrow.uturn.backward") { library.undoManager?.undo() }
                }
                // The empty state has its own New Label; one per screen.
                if !labels.isEmpty {
                    ToolbarItem(placement: .bottomBar) { newLabelButton }
                }
            }
            .alert("Rename Label", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Rename") { if let renaming { try? library.rename(renaming.id, to: newName) } }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var newLabelButton: some View {
        Button("New Label", systemImage: "square.and.pencil") {
            newLabel()
            dismiss()
        }
        .accessibilityIdentifier("libraryNewLabelButton")
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
