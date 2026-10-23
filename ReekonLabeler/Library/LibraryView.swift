import SwiftData
import SwiftUI
import UIKit

/// Templates (S11) above every folder and top-level label, most recently edited first (S9). Tap to open, swipe
/// to delete (undoable), long-press to rename. Drag a label onto another to make a folder, or onto a folder to
/// add it (S10). An empty library offers New Label.
struct LibraryView: View {
    let library: LabelLibrary
    /// The label open in the editor, marked in the list.
    let openID: UUID?
    let open: (UUID, String, LabelDocument) -> Void
    let newLabel: () -> Void
    let newFromTemplate: (UUID) -> Void
    /// Tells the editor which labels were deleted, in case one is open.
    let deleted: (Set<UUID>) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedLabel.modified, order: .reverse) private var everything: [SavedLabel]
    @Query(sort: \LabelFolder.created) private var folders: [LabelFolder]
    @State private var renaming: Renaming?
    @State private var newName = ""
    @State private var deletingFolder: LabelFolder?

    /// What the Rename alert renames.
    private enum Renaming {
        case label(UUID), folder(UUID)
    }

    private var templates: [SavedLabel] { everything.filter(\.isTemplate).sorted { $0.name < $1.name } }
    private var topLevel: [SavedLabel] { everything.filter { !$0.isTemplate && $0.folderID == nil } }

    var body: some View {
        NavigationStack {
            List {
                if !templates.isEmpty {
                    Section("Templates") {
                        ForEach(templates) { template in
                            Button {
                                newFromTemplate(template.id)
                                dismiss()
                            } label: {
                                LabelRow(label: template, isOpen: false)
                            }
                            .accessibilityIdentifier("libraryTemplate")
                            .contextMenu { renameButton(template.name, .label(template.id)) }
                        }
                        .onDelete { offsets in delete(offsets.map { templates[$0].id }) }
                    }
                }
                Section {
                    ForEach(folders) { folder in folderRow(folder) }
                    ForEach(topLevel) { label in labelRow(label) }
                        .onDelete { offsets in delete(offsets.map { topLevel[$0].id }) }
                } header: {
                    if !templates.isEmpty { Text("Labels") }
                }
            }
            .overlay {
                if everything.isEmpty && folders.isEmpty {
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
            .navigationDestination(for: UUID.self) { folderID in
                FolderContents(library: library, folderID: folderID, openID: openID,
                               name: folders.first { $0.id == folderID }?.name ?? "Folder",
                               open: openAndClose, delete: delete,
                               rename: { label in newName = label.name; renaming = .label(label.id) })
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Undo", systemImage: "arrow.uturn.backward") { library.undoManager?.undo() }
                }
                // The empty state has its own New Label; one per screen.
                if !(everything.isEmpty && folders.isEmpty) {
                    ToolbarItem(placement: .bottomBar) { newLabelButton }
                }
            }
        }
        // On the stack, not the list, so they also present over an open folder.
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { rename() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \(deletingFolder?.name ?? "Folder")?",
                            isPresented: Binding(get: { deletingFolder != nil },
                                                 set: { if !$0 { deletingFolder = nil } }),
                            titleVisibility: .visible, presenting: deletingFolder) { folder in
            Button("Delete Folder, Keep Labels") { _ = try? library.deleteFolder(folder.id, keepingLabels: true) }
            Button("Delete Folder and Labels", role: .destructive) {
                if let ids = try? library.deleteFolder(folder.id, keepingLabels: false) { deleted(ids) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Either can be undone.")
        }
    }

    private func labelRow(_ label: SavedLabel) -> some View {
        Button { openAndClose(label) } label: { LabelRow(label: label, isOpen: label.id == openID) }
            .accessibilityIdentifier("libraryLabel")
            .contextMenu {
                renameButton(label.name, .label(label.id))
                // The way into a folder without dragging, for VoiceOver too.
                if !folders.isEmpty {
                    Menu("Move to Folder", systemImage: "folder") {
                        ForEach(folders) { folder in
                            Button(folder.name) { try? library.move(label.id, toFolder: folder.id) }
                        }
                    }
                }
            }
            .draggable(label.id.uuidString) { LabelRow.thumbnail(label) }
            .dropDestination(for: String.self) { items, _ in
                guard let dragged = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                try? library.drop(dragged, onLabel: label.id)
                return true
            }
    }

    private func folderRow(_ folder: LabelFolder) -> some View {
        let count = everything.count { $0.folderID == folder.id && !$0.isTemplate }
        return NavigationLink(value: folder.id) {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill").font(.title2).foregroundStyle(.tint)
                    .frame(width: 64, height: 40)
                VStack(alignment: .leading) {
                    Text(folder.name)
                    Text(count == 1 ? "1 label" : "\(count) labels").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("libraryFolder")
        .contextMenu {
            renameButton(folder.name, .folder(folder.id))
            Button("Delete Folder…", systemImage: "trash", role: .destructive) { deletingFolder = folder }
        }
        .swipeActions {
            // Not role: .destructive, which would remove the row before the delete is confirmed.
            Button("Delete", systemImage: "trash") { deletingFolder = folder }.tint(.red)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.first.flatMap(UUID.init(uuidString:)) else { return false }
            try? library.move(dragged, toFolder: folder.id)
            return true
        }
    }

    private func renameButton(_ current: String, _ target: Renaming) -> some View {
        Button("Rename", systemImage: "pencil") { newName = current; renaming = target }
    }

    private func rename() {
        switch renaming {
        case .label(let id): try? library.rename(id, to: newName)
        case .folder(let id): try? library.renameFolder(id, to: newName)
        case nil: break
        }
    }

    private func openAndClose(_ label: SavedLabel) {
        guard let doc = label.document else { return }
        open(label.id, label.name, doc)
        dismiss()
    }

    private func delete(_ ids: [UUID]) {
        for id in ids { try? library.delete(id) }
        deleted(Set(ids))
    }

    private var newLabelButton: some View {
        Button("New Label", systemImage: "square.and.pencil") {
            newLabel()
            dismiss()
        }
        .accessibilityIdentifier("libraryNewLabelButton")
    }
}

/// An open folder's labels (S10). Drag a label onto the top row, or use its menu, to move it out of the folder.
private struct FolderContents: View {
    let library: LabelLibrary
    let openID: UUID?
    let name: String
    let open: (SavedLabel) -> Void
    let delete: ([UUID]) -> Void
    let rename: (SavedLabel) -> Void
    @Query private var labels: [SavedLabel]

    init(library: LabelLibrary, folderID: UUID, openID: UUID?, name: String, open: @escaping (SavedLabel) -> Void,
         delete: @escaping ([UUID]) -> Void, rename: @escaping (SavedLabel) -> Void) {
        self.library = library
        self.openID = openID
        self.name = name
        self.open = open
        self.delete = delete
        self.rename = rename
        _labels = Query(filter: #Predicate { $0.folderID == folderID && !$0.isTemplate },
                        sort: \.modified, order: .reverse)
    }

    var body: some View {
        List {
            Label("Drop here to move out of the folder", systemImage: "arrow.up.doc")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("moveOutOfFolder")
                .dropDestination(for: String.self) { items, _ in
                    guard let dragged = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                    try? library.move(dragged, toFolder: nil)
                    return true
                }
            ForEach(labels) { label in
                Button { open(label) } label: { LabelRow(label: label, isOpen: label.id == openID) }
                    .accessibilityIdentifier("libraryLabel")
                    .draggable(label.id.uuidString) { LabelRow.thumbnail(label) }
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") { rename(label) }
                        Button("Move Out of Folder", systemImage: "arrow.up.doc") {
                            try? library.move(label.id, toFolder: nil)
                        }
                    }
            }
            .onDelete { offsets in delete(offsets.map { labels[$0].id }) }
        }
        .navigationTitle(name)
    }
}

/// One label or template: its thumbnail, name and last edit.
private struct LabelRow: View {
    let label: SavedLabel
    let isOpen: Bool

    var body: some View {
        HStack(spacing: 12) {
            Self.thumbnail(label)
            VStack(alignment: .leading) {
                Text(label.name).foregroundStyle(.primary)
                Text(label.modified, format: .relative(presentation: .named))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isOpen {
                Text("Open").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    static func thumbnail(_ label: SavedLabel) -> some View {
        if let data = label.thumbnailPNG, let image = UIImage(data: data) {
            // The thumbnail carries its own stock colour (S16), so the edge hugs the image.
            Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
                .border(Theme.labelEdge)
                .frame(width: 64, height: 40)
        } else {
            Image(systemName: "tag").frame(width: 64, height: 40)
        }
    }
}
