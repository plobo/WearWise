import XCTest

/// End-to-end flows against the real app, launched with an isolated in-memory sample wardrobe.
@MainActor
final class WearWiseUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    // MARK: Helpers

    private func tab(_ name: String) {
        let button = app.tabBars.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Tab \(name)")
        button.tap()
    }

    private func item(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)["wardrobe.item.\(name)"]
    }

    private func outfitCard(_ title: String) -> XCUIElement {
        app.descendants(matching: .any)["outfit.card.\(title)"]
    }

    private func openMatch(for top: String) {
        tab("Match")
        let start = app.descendants(matching: .any)["match.start.\(top)"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(app.staticTexts["Best outfits from your closet"].waitForExistence(timeout: 5))
    }

    // MARK: Wardrobe

    func testBrowseFilterAndSearch() {
        // The grid is lazy: only items near the top exist until scrolled to. Newest items come first.
        XCTAssertTrue(item("Navy scarf").waitForExistence(timeout: 5))
        XCTAssertTrue(item("Brown belt").exists)

        app.buttons["Bottoms"].firstMatch.tap()
        XCTAssertTrue(item("Beige chinos").waitForExistence(timeout: 2))
        XCTAssertFalse(item("Navy scarf").exists, "Bottoms filter hides accessories")

        app.buttons["All"].firstMatch.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        search.tap()
        search.typeText("chinos")
        XCTAssertTrue(item("Beige chinos").waitForExistence(timeout: 2))
        XCTAssertFalse(item("Dark jeans").exists)
    }

    func testEditItemName() {
        XCTAssertTrue(item("White tee").waitForExistence(timeout: 5))
        item("White tee").tap()
        app.buttons["Edit"].tap()

        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 2))
        name.tap()
        name.clearAndType("White crew tee")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.navigationBars["White crew tee"].waitForExistence(timeout: 3))
    }

    func testDeleteItem() {
        XCTAssertTrue(item("Navy scarf").waitForExistence(timeout: 5))
        item("Navy scarf").tap()
        let delete = app.buttons["Delete item"]
        for _ in 0..<4 where !delete.isHittable { app.swipeUp() }
        delete.tap()
        app.sheets.buttons["Delete"].firstMatch.tap()

        XCTAssertTrue(item("Brown belt").waitForExistence(timeout: 3), "Back on the wardrobe")
        XCTAssertFalse(item("Navy scarf").exists)
    }

    func testAddRequiresAPhotoBeforeSaving() {
        app.buttons["Add clothing"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Add a photo"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(item("Light blue oxford").waitForExistence(timeout: 3))
    }

    // MARK: Match and outfits

    func testMatchSaveAndWearShowsInOutfits() {
        openMatch(for: "Light blue oxford")
        let card = outfitCard("Beige chinos + Brown loafers")
        XCTAssertTrue(card.waitForExistence(timeout: 3))

        card.buttons["Save"].tap()
        XCTAssertTrue(card.buttons["Saved"].waitForExistence(timeout: 2))
        card.buttons["Wore today"].tap()
        XCTAssertTrue(card.buttons["Worn today"].waitForExistence(timeout: 2))

        tab("Outfits")
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Beige chinos + Brown loafers"].exists)
    }

    func testNotForMeHidesAndUndoRestores() {
        openMatch(for: "Light blue oxford")
        let card = outfitCard("Beige chinos + Brown loafers")
        XCTAssertTrue(card.waitForExistence(timeout: 3))

        card.buttons["Not for me"].tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 2))
        XCTAssertFalse(card.exists, "Hidden outfit disappears")

        app.buttons["Undo"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 3), "Undo brings it back")
    }

    func testDressStartsADressOutfit() {
        openMatch(for: "Burgundy dress")
        XCTAssertTrue(app.navigationBars["Match this dress"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'outfit.card.Burgundy dress + '")).firstMatch.exists)
    }
}

extension XCUIElement {
    /// Replaces a text field's contents.
    func clearAndType(_ text: String) {
        if let current = value as? String, !current.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        typeText(text)
    }
}
