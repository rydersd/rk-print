import XCTest

final class EditorUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// S1, S13: with the Type tool, tap the label twice to add two text blocks, type in each, and see each
    /// one's text printed inside its own block.
    func testAddTwoBlocksAndTypeInEach() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        try typeTwoBlocks(app)

        let first = app.descendants(matching: .any)["block-0"]
        let second = app.descendants(matching: .any)["block-1"]
        guard first.waitForExistence(timeout: 5), second.exists else {
            attachHierarchy(app)
            return XCTFail("block-0 or block-1 missing from the accessibility tree")
        }

        for (element, text) in [(first, "SHELF A"), (second, "M6")] {
            let value = try XCTUnwrap(element.value as? String)
            let parts = value.split(separator: "|")
            XCTAssertEqual(parts.first.map(String.init), text)
            let ink = Int(parts.last?.dropFirst("ink:".count) ?? "") ?? 0
            XCTAssertGreaterThan(ink, 0, "block \(text) printed no dots")
        }
        XCTAssertLessThan(first.frame.maxY, second.frame.minY + 1, "second block should sit below the first")
    }

    /// S5, S13: with the Move tool, tap two blocks and Group; afterwards one tap selects the whole group.
    func testSelectModeGroupsTwoBlocks() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
        try typeTwoBlocks(app)

        let first = app.descendants(matching: .any)["block-0"]
        let second = app.descendants(matching: .any)["block-1"]
        app.buttons["adjustMenu"].tap()
        app.buttons["Move"].tap()
        first.tap()
        second.tap()
        let group = app.buttons["groupButton"]
        guard group.waitForExistence(timeout: 2) else {
            attachHierarchy(app)
            return XCTFail("Group should appear with two blocks selected")
        }
        group.tap()

        // In Move a tap on empty label deselects; in Type it would add text.
        app.descendants(matching: .any)["labelCanvas"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
        XCTAssertFalse(app.buttons["ungroupButton"].exists, "tapping empty canvas should clear the selection")
        first.tap()
        XCTAssertTrue(app.buttons["ungroupButton"].waitForExistence(timeout: 2),
                      "tapping one member should select the whole group")
    }

    /// Type tool: a tap high on the label adds "SHELF A", a tap low adds "M6". The canvas element spans the
    /// whole editing area with the label centred in it, so both taps sit near the middle.
    private func typeTwoBlocks(_ app: XCUIApplication) throws {
        let canvas = app.descendants(matching: .any)["labelCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.4)).tap()
        guard app.descendants(matching: .any)["blockField-0"].waitForExistence(timeout: 3) else {
            attachHierarchy(app)
            return XCTFail("a Type tap on the label should open a text field")
        }
        app.typeText("SHELF A")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.58)).tap()
        app.typeText("M6")
    }

    /// Keeps the accessibility tree with the result bundle so a failure can be read, not guessed.
    private func attachHierarchy(_ app: XCUIApplication) {
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
