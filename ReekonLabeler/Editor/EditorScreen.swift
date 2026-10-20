import os
import SwiftData
import SwiftUI
import UIKit

/// The whole app on one screen: the label canvas, the selected block's inspector, and the tools.
struct EditorScreen: View {
    @Environment(\.modelContext) private var modelContext
    @State private var editor: LabelEditor
    @State private var printer = P1LPrinter()
    @State private var undoManager: UndoManager
    @State private var canUndo = false
    @State private var canRedo = false
    @State private var sheet: Sheet?
    @State private var saveName = ""
    @State private var isNamingSave = false

    private enum Sheet: String, Identifiable {
        case labelSize, fonts, printer, library
        var id: String { rawValue }
    }

    init(persistsWorkingLabel: Bool) {
        let undo = UndoManager()
        _undoManager = State(initialValue: undo)
        _editor = State(initialValue: LabelEditor(undoManager: undo, persistsWorkingLabel: persistsWorkingLabel))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CanvasView(editor: editor)
                    .padding(16)
                    .frame(maxHeight: .infinity)
                if editor.selectedBlock != nil {
                    InspectorView(editor: editor, showFonts: { sheet = .fonts })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .background(Theme.canvasBackground)
            .animation(.snappy(duration: 0.2), value: editor.selectedID == nil)
            .navigationTitle(editor.libraryName ?? "Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(item: $sheet) { sheet in sheetContent(sheet) }
            .alert("Save Label", isPresented: $isNamingSave) {
                TextField("Name", text: $saveName)
                Button("Save") { save() }
                Button("Cancel", role: .cancel) {}
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerCheckpoint, object: undoManager)) { _ in
            canUndo = undoManager.canUndo
            canRedo = undoManager.canRedo
        }
        .task { if printer.hasSavedPrinter { printer.activate() } }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button("Library", systemImage: "books.vertical") { sheet = .library }
            Button("Save", systemImage: "square.and.arrow.down") {
                saveName = editor.libraryName ?? defaultName
                isNamingSave = true
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Undo", systemImage: "arrow.uturn.backward") { undoManager.undo() }
                .disabled(!canUndo)
            Button("Redo", systemImage: "arrow.uturn.forward") { undoManager.redo() }
                .disabled(!canRedo)
        }
        // In the top bar so it stays reachable while the keyboard covers the bottom bar.
        ToolbarItem(placement: .topBarTrailing) {
            Button("Add Text", systemImage: "plus") { editor.addBlock() }
                .accessibilityIdentifier("addTextButton")
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button(editor.document.size.displayName) { sheet = .labelSize }
                .accessibilityIdentifier("labelSizeButton")
            Button("Rotate", systemImage: "rotate.right") {
                editor.setOrientation(editor.document.orientation == .headNative ? .rotated : .headNative)
            }
            Menu("Grid", systemImage: editor.document.grid == .off ? "grid.circle" : "grid.circle.fill") {
                Picker("Grid", selection: Binding(get: { editor.document.grid }, set: { editor.setGrid($0) })) {
                    ForEach(GridStep.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            Spacer()
            printButton
        }
    }

    private var printButton: some View {
        Button {
            if printer.isReady {
                editor.select(nil)
                Task { await printer.print(editor.document) }
            } else {
                sheet = .printer
            }
        } label: {
            switch printer.state {
            case .printing: ProgressView()
            default: Label("Print", systemImage: printer.isReady ? "printer.fill" : "printer")
            }
        }
        .disabled(printer.isCoolingDown || printer.isPrinting)
        .contextMenu { Button("Printer…", systemImage: "antenna.radiowaves.left.and.right") { sheet = .printer } }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: Sheet) -> some View {
        switch sheet {
        case .labelSize:
            LabelSizeSheet(current: editor.document.size) { editor.setSize($0) }
        case .fonts:
            FontPickerSheet(current: editor.selectedBlock?.font ?? .standard) { family in
                guard let block = editor.selectedBlock else { return }
                let face = FontCatalog.defaultFace(for: family, matching: block.font)
                editor.updateBlock(block.id, action: "Font") { $0.font = FontSpec(family: family, face: face) }
            }
        case .printer:
            PrinterSheet(printer: printer)
        case .library:
            LibraryView(library: LabelLibrary(context: modelContext, undoManager: undoManager)) { id, name, doc in
                editor.load(doc, libraryID: id, name: name)
            }
        }
    }

    // MARK: Saving

    /// The first line of text, else "Label".
    private var defaultName: String {
        let first = editor.document.blocks.lazy.map(\.text).first { !$0.isEmpty } ?? ""
        let line = first.split(separator: "\n").first.map(String.init) ?? ""
        return line.isEmpty ? "Label" : line
    }

    private func save() {
        let name = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
        let library = LabelLibrary(context: modelContext)
        let thumbnail = editor.image.flatMap { UIImage(cgImage: $0).pngData() }
        do {
            let id = try library.save(editor.document, name: name.isEmpty ? defaultName : name,
                                      id: editor.libraryID, thumbnailPNG: thumbnail)
            editor.libraryID = id
            editor.libraryName = name.isEmpty ? defaultName : name
        } catch {
            Logger.editorUI.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension Logger {
    static let editorUI = Logger(subsystem: "tools.reekon.labeler", category: "ui")
}
