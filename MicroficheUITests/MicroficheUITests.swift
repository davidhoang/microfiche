//
//  MicroficheUITests.swift
//  MicroficheUITests
//
//  Created by David Hoang on 6/8/25.
//

import XCTest

final class MicroficheUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    @MainActor
    func testAppLaunchesTwice() throws {
        let app = configuredApp()

        for attempt in 1...2 {
            app.launch()
            XCTAssertTrue(
                app.windows.firstMatch.waitForExistence(timeout: 5),
                "Expected a window on launch attempt \(attempt)"
            )
            app.terminate()
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        }
    }

    @MainActor
    func testPrimaryNavigationControls() throws {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(element("library.sidebar", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("sidebar.toggle", in: app).waitForExistence(timeout: 3))

        let gridButton = element("viewMode.grid", in: app)
        let listButton = element("viewMode.list", in: app)
        XCTAssertTrue(gridButton.waitForExistence(timeout: 3))
        XCTAssertTrue(listButton.exists)
        XCTAssertTrue(element("library.filter", in: app).exists)
        XCTAssertTrue(element("inspector.toggle", in: app).exists)

        listButton.click()
        XCTAssertTrue(listButton.isSelected)
        listButton.click()
        XCTAssertTrue(listButton.isSelected)

        gridButton.click()
        XCTAssertTrue(gridButton.isSelected)
        gridButton.click()
        XCTAssertTrue(gridButton.isSelected)
    }

    @MainActor
    func testInspectorCanBeToggled() throws {
        let app = configuredApp()
        app.launch()

        let firstImage = element("image.fixture-01.png", in: app)
        XCTAssertTrue(firstImage.waitForExistence(timeout: 5))
        firstImage.click()

        let inspectorButton = element("inspector.toggle", in: app)
        XCTAssertTrue(inspectorButton.waitForExistence(timeout: 3))
        inspectorButton.click()
        XCTAssertTrue(
            element("inspector.selection-summary", in: app)
                .waitForExistence(timeout: 2)
        )
        inspectorButton.click()
        XCTAssertFalse(element("inspector.selection-summary", in: app).exists)
        inspectorButton.click()
        XCTAssertTrue(
            element("inspector.selection-summary", in: app)
                .waitForExistence(timeout: 2)
        )
        inspectorButton.click()
        XCTAssertFalse(element("inspector.selection-summary", in: app).exists)
    }

    @MainActor
    func testFixtureLibraryAndRepeatedSelectionTransitions() throws {
        let app = configuredApp()
        app.launch()

        let first = fixtureImage(1, in: app)
        let second = fixtureImage(2, in: app)
        let third = fixtureImage(3, in: app)
        let fifth = fixtureImage(5, in: app)
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(fifth.exists)
        XCTAssertTrue(app.staticTexts["First Review"].exists)
        XCTAssertTrue(app.staticTexts["Second Review"].exists)
        XCTAssertEqual(first.value as? String, "Not selected")

        first.click()
        XCTAssertTrue(first.isSelected)
        second.click()
        XCTAssertTrue(second.isSelected)
        second.click()
        XCTAssertTrue(second.isSelected)

        third.click(forDuration: 0, modifierFlags: .command)
        XCTAssertTrue(second.isSelected)
        XCTAssertTrue(third.isSelected)
        fifth.click(forDuration: 0, modifierFlags: .shift)
        XCTAssertTrue(fifth.isSelected)

        for _ in 0..<5 {
            first.click()
        }
        XCTAssertTrue(first.isSelected)

        first.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(second.isSelected)
        second.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(first.isSelected)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(first.isSelected)

        element("viewMode.list", in: app).click()
        XCTAssertTrue(element("viewMode.list", in: app).isSelected)
        third.click()
        XCTAssertTrue(third.isSelected)
        element("viewMode.grid", in: app).click()
        XCTAssertTrue(element("viewMode.grid", in: app).isSelected)
    }

    @MainActor
    func testDoubleClickDragAndContextMenuDoNotDisableLaterClicks() throws {
        let app = configuredApp()
        app.launch()

        let first = fixtureImage(1, in: app)
        let second = fixtureImage(2, in: app)
        let third = fixtureImage(3, in: app)
        XCTAssertTrue(first.waitForExistence(timeout: 5))

        for image in [first, second] {
            for _ in 0..<2 {
                image.doubleClick()
                XCTAssertTrue(
                    element("image.detail", in: app).waitForExistence(timeout: 2)
                )
                app.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(first.waitForExistence(timeout: 2))
            }
        }

        let start = first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = first.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: end)
        second.click()
        XCTAssertTrue(second.isSelected)

        second.rightClick()
        XCTAssertTrue(app.menuItems["Move to Archive"].waitForExistence(timeout: 2))
        app.typeKey(.escape, modifierFlags: [])
        third.click()
        XCTAssertTrue(third.isSelected)
    }

    @MainActor
    func testRemovingSelectedImageClearsInspectorWithoutStaleContent() throws {
        let app = configuredApp()
        app.launch()

        for index in 1...2 {
            let image = fixtureImage(index, in: app)
            XCTAssertTrue(image.waitForExistence(timeout: 5))
            image.click()
            element("inspector.toggle", in: app).click()
            XCTAssertTrue(
                element("inspector.selection-summary", in: app)
                    .waitForExistence(timeout: 2)
            )

            app.typeKey(.delete, modifierFlags: [.command, .shift])
            XCTAssertTrue(image.waitForNonExistence(timeout: 3))
            XCTAssertFalse(element("inspector.selection-summary", in: app).exists)
        }
    }

    @MainActor
    func testSidebarAndInspectorTransitionBothDirectionsTwice() throws {
        let app = configuredApp()
        app.launch()

        let sidebar = element("library.sidebar", in: app)
        let toggle = element("sidebar.toggle", in: app)
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))

        for _ in 0..<2 {
            toggle.click()
            XCTAssertTrue(sidebar.waitForNonExistence(timeout: 2))
            toggle.click()
            XCTAssertTrue(sidebar.waitForExistence(timeout: 2))
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                configuredApp().launch()
            }
        }
    }

    @MainActor
    private func configuredApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-isOnboardingEnabled", "NO",
            "-hasCompletedOnboarding", "YES",
            "--ui-testing",
            "--ui-testing-fixtures"
        ]
        return app
    }

    @MainActor
    private func fixtureImage(_ index: Int, in app: XCUIApplication) -> XCUIElement {
        element(String(format: "image.fixture-%02d.png", index), in: app)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
