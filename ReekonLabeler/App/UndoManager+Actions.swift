import Foundation

extension UndoManager {
    /// Registers one named undo action. Outside an event loop (tests, scripted edits) there is no automatic
    /// undo group, so the action gets its own; inside one, it joins the event's group as usual.
    func registerAction<Target: AnyObject>(_ name: String, target: Target, handler: @escaping @MainActor (Target) -> Void) {
        let ownGroup = !groupsByEvent && groupingLevel == 0
        if ownGroup { beginUndoGrouping() }
        registerUndo(withTarget: target) { target in
            MainActor.assumeIsolated { handler(target) }
        }
        setActionName(name)
        if ownGroup { endUndoGrouping() }
    }
}
