import SwiftData
import SwiftUI

@main
struct ReekonLabelerApp: App {
    /// UI tests launch with `-uiTesting` so they start from an empty label and an in-memory library.
    private let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    var body: some Scene {
        WindowGroup {
            EditorScreen(persistsWorkingLabel: !isUITesting)
        }
        .modelContainer(for: SavedLabel.self, inMemory: isUITesting)
    }
}
