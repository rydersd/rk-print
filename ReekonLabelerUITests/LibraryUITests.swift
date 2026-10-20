import XCTest

final class LibraryUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// S9: an empty library offers New Label; the new label, once typed in, is listed without a Save step.
    func testEmptyLibraryCreatesLabel() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        let library = app.buttons["Library"]
        XCTAssertTrue(library.waitForExistence(timeout: 10))
        library.tap()
        let newLabel = app.buttons["libraryNewLabelButton"]
        XCTAssertTrue(newLabel.waitForExistence(timeout: 5), "empty library should offer New Label")
        newLabel.tap()

        app.buttons["addTextButton"].tap()
        app.typeText("BINS")
        library.tap()
        let row = app.buttons["libraryLabel"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["BINS"].waitForExistence(timeout: 3), "label should be listed by its text")
        XCTAssertEqual(app.buttons.matching(identifier: "libraryLabel").count, 1)
    }
}
