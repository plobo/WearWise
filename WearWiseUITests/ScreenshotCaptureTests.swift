import XCTest

/// Captures screenshots of screens that can't be reached from the command line. Opt-in.
@MainActor
final class ScreenshotCaptureTests: XCTestCase {
    func testCaptureScreens() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CAPTURE_SCREENS"] == "1", "Set CAPTURE_SCREENS=1")
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()

        func snap(_ name: String) {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        XCTAssertTrue(app.descendants(matching: .any)["wardrobe.item.Light blue oxford"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["wardrobe.item.Light blue oxford"].tap()
        sleep(1)
        snap("item-detail")
        app.navigationBars.buttons.firstMatch.tap()

        app.tabBars.buttons["Match"].tap()
        sleep(1)
        snap("match-picker")
        app.descendants(matching: .any)["match.start.Light blue oxford"].tap()
        sleep(1)
        snap("match-results")

        app.tabBars.buttons["Wardrobe"].tap()
        app.buttons["Add clothing"].firstMatch.tap()
        sleep(1)
        snap("add-clothing")
    }
}
