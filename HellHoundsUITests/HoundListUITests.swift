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
    /// unless `resetProfiles` is false (a relaunch). Debug mode is off
    /// unless asked for, whatever it was left at.
    @MainActor
    private func launch(houndCount: Int, resetProfiles: Bool = true, debugMode: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-useFakeTransport", "YES", "-fakeHoundCount", String(houndCount), "-debugMode", debugMode ? "YES" : "NO",
        ]
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
    func testANamedHoundThatIsntFoundStillShows() {
        var app = launch(houndCount: 2)
        let edit = app.buttons["hound-1-edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "the second hound never appeared")
        edit.tap()
        let name = app.textFields["edit-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Yellow Hound of the Baskervilles")
        app.buttons["edit-save"].tap()
        XCTAssertTrue(waitForLabel("Edit Yellow Hound of the Baskervilles", of: app.buttons["hound-1-edit"]))

        // Only the first hound is around now.
        app.terminate()
        app = launch(houndCount: 1, resetProfiles: false)
        XCTAssertTrue(app.switches["hound-0-toggle"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel("Edit Yellow Hound of the Baskervilles", of: app.buttons["hound-1-edit"]))
        let status = app.descendants(matching: .any)["hound-1-status"].firstMatch
        XCTAssertTrue(waitForLabel("Not found", of: status, timeout: 10), "the missing hound isn't marked")
        XCTAssertFalse(app.switches["hound-1-toggle"].exists, "a missing hound has no controls")
        XCTAssertTrue(app.buttons["hound-1-edit"].isEnabled, "a missing hound can still be edited")
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

    @MainActor
    func testIdentifyFromDebugModeAndLongPressShowsInTheLog() {
        let app = launch(houndCount: 2, debugMode: true)
        let debug = app.descendants(matching: .any)["hound-0-debug"].firstMatch
        XCTAssertTrue(debug.waitForExistence(timeout: 5), "debug mode shows no details")
        XCTAssertTrue(debug.label.contains("HellHounds-MQTT/0/"), "no topic in \(debug.label)")

        app.buttons["hound-0-identify"].tap()
        let stop = app.buttons["hound-0-stop-identify"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5), "identify didn't start")
        stop.tap()
        XCTAssertTrue(app.buttons["hound-0-identify"].waitForExistence(timeout: 5), "identify didn't stop")

        app.descendants(matching: .any)["hound-1"].firstMatch.press(forDuration: 1.2)
        let menuItem = app.buttons["Identify (Blink 30 s)"]
        XCTAssertTrue(menuItem.waitForExistence(timeout: 5), "no Identify in the long-press menu")
        menuItem.tap()
        XCTAssertTrue(app.buttons["hound-1-stop-identify"].waitForExistence(timeout: 5))
        app.buttons["hound-1-stop-identify"].tap()

        app.tabBars.buttons["Settings"].tap()
        let connectedAt = app.descendants(matching: .any)["settings-connected-at"].firstMatch
        XCTAssertTrue(connectedAt.waitForExistence(timeout: 5), "no connection time")
        let logLink = app.buttons["settings-event-log"]
        if !logLink.isHittable { app.swipeUp() }
        logLink.tap()
        let stopped = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Identify stopped")).firstMatch
        XCTAssertTrue(stopped.waitForExistence(timeout: 5), "the log doesn't show identify")
    }
}
