import os
import SwiftData
import SwiftUI

@main
struct ReekonLabelerApp: App {
    /// UI tests launch with `-uiTesting` so they start from an empty label and an in-memory library.
    private let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
    /// Built here rather than by `.modelContainer(for:)` so the editor can reopen the last label at launch.
    private let container: ModelContainer
    private let library: LabelLibrary

    init() {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: isUITesting)
        do {
            container = try ModelContainer(for: LabelLibrary.schema, configurations: configuration)
        } catch {
            // Without a store there is nowhere to keep labels; stop rather than silently lose them.
            Logger(subsystem: "tools.reekon.labeler", category: "app")
                .fault("Library store failed to open: \(error.localizedDescription, privacy: .public)")
            fatalError("Library store failed to open: \(error)")
        }
        library = LabelLibrary(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            EditorScreen(library: library, persistsWorkingLabel: !isUITesting)
        }
        .modelContainer(container)
    }
}
