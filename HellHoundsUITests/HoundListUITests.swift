//
//  HoundListUITests.swift
//  HellHoundsUITests
//
//  The app on the in-process fake transport, driven through the UI.
//

import XCTest

final class HoundListUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// Always the in-process fake: UI tests must never reach a broker
    /// (real hounds are live on the public one). Profiles start empty
    /// unless `resetProfiles` is false (a relaunch).
    @MainActor
    private func launch(houndCount: Int, resetProfiles: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-useFakeTransport", "YES", "-fakeHoundCount", String(houndCount)]
        if resetProfiles {
            app.launchArguments += ["-resetProfiles", "YES"]
        }
        app.launch()
        return app
    }

    @MainActor
    private func waitForLabel(_ label: String, of element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForValue(_ value: String, of element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }

    /// Phase 3's "done when": six hounds, more than fit on screen.
    @MainActor
    func testSixthHoundIsReachedByScrollingAndSwitchesOn() {
        let app = launch(houndCount: 6)
        XCTAssertTrue(app.switches["hound-0-toggle"].waitForExistence(timeout: 5), "the first hound never appeared")

        let sixth = app.switches["hound-5-toggle"]
        XCTAssertFalse(sixth.exists && sixth.isHittable, "the 6th hound should start off screen")

        for _ in 0..<5 where !(sixth.exists && sixth.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(sixth.isHittable, "scrolling never reached the 6th hound")
        XCTAssertEqual(app.buttons["hound-5-edit"].label, "Edit Hound 6")
        XCTAssertEqual(sixth.value as? String, "0")

        sixth.tap()

        // The fake hound answers with its status; the switch follows that, not the tap.
        XCTAssertTrue(waitForValue("1", of: sixth), "the 6th hound didn't report itself on")
        XCTAssertEqual(app.switches["hound-4-toggle"].value as? String, "0", "only the 6th hound should change")
    }

    @MainActor
    func testRenamedHoundKeepsItsNameAfterRelaunch() {
        var app = launch(houndCount: 2)
        let edit = app.buttons["hound-1-edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "the second hound never appeared")
        edit.tap()

        let name = app.textFields["edit-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Fang")
        app.buttons["edit-save"].tap()

        // The card's title is its edit button's label.
        XCTAssertTrue(waitForLabel("Edit Fang", of: app.buttons["hound-1-edit"]))
        XCTAssertEqual(app.buttons["hound-0-edit"].label, "Edit Hound 1", "only the second hound should be renamed")

        app.terminate()
        app = launch(houndCount: 2, resetProfiles: false)
        XCTAssertTrue(waitForLabel("Edit Fang", of: app.buttons["hound-1-edit"]), "the name didn't survive a relaunch")
    }

    @MainActor
    func testSettingsCannotChangeTheBrokerOnTheFakeTransport() {
        let app = launch(houndCount: 2)
        app.tabBars.buttons["Settings"].tap()

        let host = app.textFields["settings-host"]
        XCTAssertTrue(host.waitForExistence(timeout: 5))
        XCTAssertFalse(host.isEnabled)
        XCTAssertFalse(app.buttons["settings-connect"].isEnabled)
        XCTAssertFalse(app.buttons["Use the Public Broker"].exists)
    }
}
