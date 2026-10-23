import os
import PhotosUI
import SwiftData
import SwiftUI

/// The whole app on one screen: the label canvas, the selection's inspector, and the tools.
struct EditorScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    private let library: LabelLibrary
    @State private var editor: LabelEditor
    @State private var printer = P1LPrinter()
    @State private var undoManager: UndoManager
    @State private var canUndo = false
    @State private var canRedo = false
    @State private var sheet: Sheet?
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var cropping: CropRequest?
    @State private var showsPhotos = false
    @Query(filter: #Predicate<SavedLabel> { $0.isTemplate }, sort: \SavedLabel.name) private var templates: [SavedLabel]

    private enum Sheet: String, Identifiable {
        case labelSize, fonts, printer, library
        var id: String { rawValue }
    }

    init(library: LabelLibrary, persistsWorkingLabel: Bool) {
        let undo = UndoManager()
        self.library = library
        _undoManager = State(initialValue: undo)
        _editor = State(initialValue: LabelEditor(undoManager: undo, persistsWorkingLabel: persistsWorkingLabel,
                                                  library: library))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CanvasView(editor: editor)
                    .padding(16)
                    .frame(maxHeight: .infinity)
                if !editor.selection.isEmpty {
                    InspectorView(editor: editor, showFonts: { sheet = .fonts }) { element in
                        guard let picture = element.picture else { return }
                        cropping = CropRequest(picture: picture, elementID: element.id,
                                               maximumAspect: editor.maximumPictureAspect(rotation: element.rotation))
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .background(Theme.canvasBackground)
            .animation(.snappy(duration: 0.2), value: editor.selection.isEmpty)
            .navigationTitle(editor.libraryName ?? "Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(item: $sheet) { sheet in sheetContent(sheet) }
            .fullScreenCover(item: $cropping) { request in
                CropView(request: request) { crop in finishCrop(request, crop: crop) }
            }
            .photosPicker(isPresented: $showsPhotos, selection: $pickedPhoto, matching: .images)
            .onChange(of: pickedPhoto) { _, item in
                guard let item else { return }
                pickedPhoto = nil
                Task { await importPhoto(item) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSUndoManagerCheckpoint, object: undoManager)) { _ in
            canUndo = undoManager.canUndo
            canRedo = undoManager.canRedo
        }
        .task {
            // One undo history for the editor and the library, so the library's Undo also covers deletes.
            library.undoManager = undoManager
            if printer.hasSavedPrinter { printer.activate() }
        }
        // Don't lose the last half second of edits if the app is closed right after them.
        .onChange(of: scenePhase) { _, phase in if phase != .active { editor.saveNow() } }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // The tools are in the top bar so they stay reachable while the keyboard covers the bottom bar (S13).
        ToolbarItemGroup(placement: .topBarLeading) {
            Button("Library", systemImage: "books.vertical") { sheet = .library }
            toolMenu("Input", tools: [.type, .draw], showsPhoto: true)
                .accessibilityIdentifier("inputMenu")
            toolMenu("Adjust", tools: [.move, .scale], showsPhoto: false)
                .accessibilityIdentifier("adjustMenu")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            insertTemplateMenu
            Button("Undo", systemImage: "arrow.uturn.backward") { undoManager.undo() }
                .disabled(!canUndo)
            Button("Redo", systemImage: "arrow.uturn.forward") { undoManager.redo() }
                .disabled(!canRedo)
        }
        ToolbarItemGroup(placement: .bottomBar) {
            Button(editor.document.size.displayName) { sheet = .labelSize }
                .accessibilityIdentifier("labelSizeButton")
            // Turns the whole label; the inspector's Rotate 90° turns the selection.
            Button("Turn Label", systemImage: "rectangle.portrait.rotate") {
                editor.setOrientation(editor.document.orientation == .headNative ? .rotated : .headNative)
            }
            Menu("Grid", systemImage: editor.document.grid == .off ? "grid.circle" : "grid.circle.fill") {
                Picker("Grid", selection: Binding(get: { editor.document.grid }, set: { editor.setGrid($0) })) {
                    ForEach(GridStep.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            Spacer()
            // Bottom bar: the top bar is full, and more there (a title menu too) collapses Add Text into the
            // overflow menu. Tap for a blank label; long-press to save this one as a template (S11).
            Menu {
                Button("Save as Template", systemImage: "doc.badge.plus") { editor.saveAsTemplate() }
                    .accessibilityIdentifier("saveTemplateButton")
            } label: {
                Label("New Label", systemImage: "square.and.pencil")
            } primaryAction: {
                editor.newLabel()
            }
            .accessibilityIdentifier("newLabelButton")
            printButton
        }
    }

    /// + (S15): adds a template's items to this label. With no templates yet, it says how to make one.
    private var insertTemplateMenu: some View {
        Menu("Insert Template", systemImage: "plus") {
            if templates.isEmpty {
                Text("No templates yet. Long-press New Label and choose Save as Template.")
            } else {
                ForEach(templates) { template in
                    Button(template.name) { editor.insertTemplate(template.id) }
                }
            }
        }
        .accessibilityIdentifier("insertTemplateMenu")
    }

    /// A dropdown of tools (S13). Its icon is the current tool when that tool is in this menu, tinted so
    /// the active menu stands out; otherwise the menu's first tool.
    private func toolMenu(_ title: String, tools: [EditorTool], showsPhoto: Bool) -> some View {
        let isActive = tools.contains(editor.tool)
        let shown = isActive ? editor.tool : tools[0]
        return Menu {
            Picker(title, selection: Binding(get: { editor.tool }, set: { editor.setTool($0) })) {
                ForEach(tools, id: \.self) { tool in Label(tool.title, systemImage: tool.systemImage).tag(tool) }
            }
            if showsPhoto {
                // An action, not a tool: the tool in use stays as it was.
                Button("Photo", systemImage: "photo.badge.plus") { showsPhotos = true }
            }
        } label: {
            Label(title, systemImage: shown.systemImage)
                .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        .accessibilityValue(isActive ? shown.title : "")
    }

    private var printButton: some View {
        Button {
            if printer.isReady {
                editor.clearSelection()
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
            LabelSizeSheet(current: editor.document.size, stock: editor.document.stock,
                           choose: { editor.setSize($0) }, chooseStock: { editor.setStock($0) })
        case .fonts:
            FontPickerSheet(current: editor.selectedElements.compactMap(\.textContent).first?.font ?? .standard) { family in
                editor.updateSelected(action: "Font") { element in
                    guard let font = element.textContent?.font else { return }
                    element.textContent?.font = FontSpec(family: family,
                                                         face: FontCatalog.defaultFace(for: family, matching: font))
                }
            }
        case .printer:
            PrinterSheet(printer: printer)
        case .library:
            LibraryView(library: library, openID: editor.libraryID,
                        open: { id, name, doc in editor.load(doc, libraryID: id, name: name) },
                        newLabel: { editor.newLabel() },
                        newFromTemplate: { editor.newLabel(fromTemplate: $0) },
                        deleted: { editor.libraryDeleted($0) })
        }
    }

    // MARK: Pictures

    /// Loads the picked photo, shrinks it to a greyscale picture off the main thread, then opens the crop.
    private func importPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let picture = await Task.detached(priority: .userInitiated) { PictureImport.picture(fromImageData: data) }.value
            guard let picture else {
                Logger.editorUI.error("Picked photo could not be read as an image")
                return
            }
            cropping = CropRequest(picture: picture, elementID: nil,
                                   maximumAspect: editor.maximumPictureAspect(rotation: .none))
        } catch {
            Logger.editorUI.error("Photo load failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func finishCrop(_ request: CropRequest, crop: CGRect) {
        if let id = request.elementID {
            editor.setCrop(crop, for: id)
        } else {
            var picture = request.picture
            picture.crop = crop
            editor.addPicture(picture)
        }
    }
}

extension EditorTool {
    var title: String {
        switch self {
        case .type: "Type"
        case .draw: "Draw"
        case .move: "Move"
        case .scale: "Scale"
        }
    }

    var systemImage: String {
        switch self {
        case .type: "character.cursor.ibeam"
        case .draw: "scribble"
        case .move: "arrow.up.and.down.and.arrow.left.and.right"
        case .scale: "arrow.up.left.and.arrow.down.right"
        }
    }
}

extension Logger {
    static let editorUI = Logger(subsystem: "tools.reekon.labeler", category: "ui")
}
