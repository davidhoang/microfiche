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
                app.windows.firstMatch.waitForExistence(timeout: 8),
                "Expected a window on launch attempt \(attempt)"
            )
            app.terminate()
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 8))
        }
    }

    @MainActor
    func testPrimaryNavigationControls() throws {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(element("library.sidebar", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(element("sidebar.toggle", in: app).waitForExistence(timeout: 5))

        let gridButton = button("viewMode.grid", in: app)
        let listButton = button("viewMode.list", in: app)
        XCTAssertTrue(gridButton.waitForExistence(timeout: 5))
        XCTAssertTrue(listButton.waitForExistence(timeout: 5))
        XCTAssertTrue(element("library.filter", in: app).exists)
        XCTAssertTrue(element("inspector.toggle", in: app).exists)

        selectViewMode("list", in: app)
        selectViewMode("list", in: app)
        selectViewMode("grid", in: app)
        selectViewMode("grid", in: app)
    }

    @MainActor
    func testInspectorCanBeToggled() throws {
        let app = configuredApp()
        app.launch()

        let firstImage = waitForFixtureImage(1, in: app)
        tap(firstImage)

        let inspectorButton = button("inspector.toggle", in: app)
        XCTAssertTrue(inspectorButton.waitForExistence(timeout: 5))
        let inspector = element("inspector.content", in: app)

        tap(inspectorButton)
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        tap(inspectorButton)
        XCTAssertTrue(inspector.waitForNonExistence(timeout: 5))
        tap(inspectorButton)
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        tap(inspectorButton)
        XCTAssertTrue(inspector.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testFixtureLibraryAndRepeatedSelectionTransitions() throws {
        let app = configuredApp()
        app.launch()

        let first = waitForFixtureImage(1, in: app)
        let second = waitForFixtureImage(2, in: app)
        let third = waitForFixtureImage(3, in: app)
        let fifth = waitForFixtureImage(5, in: app)

        XCTAssertTrue(
            element("sidebar.contact-sheet.First Review", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            element("sidebar.contact-sheet.Second Review", in: app)
                .waitForExistence(timeout: 5)
        )
        XCTAssertEqual(first.value as? String, "Not selected")

        tap(first)
        XCTAssertTrue(waitUntilChosen(first))
        tap(second)
        XCTAssertTrue(waitUntilChosen(second))
        tap(second)
        XCTAssertTrue(waitUntilChosen(second))

        XCUIElement.perform(withKeyModifiers: .command) {
            tap(third)
        }
        XCTAssertTrue(waitUntilChosen(second))
        XCTAssertTrue(waitUntilChosen(third))
        XCUIElement.perform(withKeyModifiers: .shift) {
            tap(fifth)
        }
        XCTAssertTrue(waitUntilChosen(third))
        XCTAssertTrue(waitUntilChosen(waitForFixtureImage(4, in: app)))
        XCTAssertTrue(waitUntilChosen(fifth))

        for _ in 0..<5 {
            tap(first)
        }
        XCTAssertTrue(waitUntilChosen(first))

        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(waitUntilChosen(second))
        app.typeKey(.leftArrow, modifierFlags: [])
        XCTAssertTrue(waitUntilChosen(first))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitUntilNotChosen(first))

        selectViewMode("list", in: app)
        tap(third)
        XCTAssertTrue(waitUntilChosen(third))
        selectViewMode("grid", in: app)
        XCTAssertTrue(waitUntilChosen(third))
    }

    @MainActor
    func testDoubleClickDragAndContextMenuDoNotDisableLaterClicks() throws {
        let app = configuredApp()
        app.launch()

        let first = waitForFixtureImage(1, in: app)
        let second = waitForFixtureImage(2, in: app)
        let third = waitForFixtureImage(3, in: app)

        for image in [first, second] {
            for _ in 0..<2 {
                image.doubleClick()
                XCTAssertTrue(
                    element("image.detail", in: app).waitForExistence(timeout: 5)
                )
                app.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(first.waitForExistence(timeout: 5))
            }
        }

        let start = first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = first.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: end)
        tap(second)
        XCTAssertTrue(waitUntilChosen(second))

        second.rightClick()
        XCTAssertTrue(app.menuItems["Move to Archive"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        tap(third)
        XCTAssertTrue(waitUntilChosen(third))
    }

    @MainActor
    func testRemovingSelectedImageClearsInspectorWithoutStaleContent() throws {
        let app = configuredApp()
        app.launch()

        let first = waitForFixtureImage(1, in: app)
        tap(first)
        tap(button("inspector.toggle", in: app))
        waitForInspectorFile("fixture-01.png", in: app)

        for index in 1...2 {
            let removedImage = waitForFixtureImage(index, in: app)
            app.typeKey(.delete, modifierFlags: [.command, .shift])
            XCTAssertTrue(removedImage.waitForNonExistence(timeout: 8))
            waitForInspectorFile(
                String(format: "fixture-%02d.png", index + 1),
                in: app
            )
        }
    }

    @MainActor
    func testSidebarCollapseAndExpansionPersistAcrossRelaunchTwice() throws {
        let app = configuredApp()
        app.launch()

        let sidebar = element("library.sidebar", in: app)
        let toggle = button("sidebar.toggle", in: app)
        XCTAssertTrue(sidebar.waitForExistence(timeout: 8))

        for _ in 0..<2 {
            tap(toggle)
            XCTAssertTrue(sidebar.waitForNonExistence(timeout: 5))
            relaunch(app)
            XCTAssertTrue(sidebar.waitForNonExistence(timeout: 5))

            tap(toggle)
            XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
            relaunch(app)
            XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testInspectorCollapseAndExpansionPersistAcrossRelaunchTwice() throws {
        let app = configuredApp()
        app.launch()

        let first = waitForFixtureImage(1, in: app)
        let inspector = element("inspector.content", in: app)
        let toggle = button("inspector.toggle", in: app)
        tap(first)

        for _ in 0..<2 {
            tap(toggle)
            XCTAssertTrue(inspector.waitForExistence(timeout: 5))
            relaunch(app)
            tap(waitForFixtureImage(1, in: app))
            XCTAssertTrue(inspector.waitForExistence(timeout: 5))

            tap(toggle)
            XCTAssertTrue(inspector.waitForNonExistence(timeout: 5))
            relaunch(app)
            tap(waitForFixtureImage(1, in: app))
            XCTAssertTrue(inspector.waitForNonExistence(timeout: 5))
        }
    }

    @MainActor
    func testAccessibleNamesValuesAndKeyboardFocusAcrossLibraryAndDetail() throws {
        let app = configuredApp()
        app.launch()

        let first = waitForFixtureImage(1, in: app)
        let second = waitForFixtureImage(2, in: app)
        XCTAssertEqual(first.label, "fixture-01.png")
        XCTAssertEqual(first.value as? String, "Not selected")

        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(waitUntilChosen(first))
        XCTAssertEqual(first.value as? String, "Selected")
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(waitUntilChosen(second))
        XCTAssertEqual(second.value as? String, "Selected")

        second.doubleClick()
        XCTAssertTrue(element("image.detail", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(element("image.detail", in: app).label, "fixture-02.png")
        XCTAssertTrue(
            ["Hide inspector", "Show inspector"].contains(
                element("detail.inspector.toggle", in: app).label
            )
        )
        XCTAssertTrue(element("detail.share", in: app).exists)
        XCTAssertEqual(
            element("detail.more", in: app).label,
            "More actions for fixture-02.png"
        )
    }

    @MainActor
    func testInspectorTextEditingKeepsKeyboardInputOutOfLibraryNavigation() throws {
        let app = configuredApp()
        app.launch()

        let first = waitForFixtureImage(1, in: app)
        tap(first)
        tap(button("inspector.toggle", in: app))
        XCTAssertTrue(element("inspector.content", in: app).waitForExistence(timeout: 5))

        let replace = button("inspector.replace-comments", in: app)
        XCTAssertTrue(replace.waitForExistence(timeout: 5))

        for attempt in 1...2 {
            tap(replace)
            let editor = element("inspector.replace-comments.editor", in: app)
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            tap(editor)
            editor.typeText("Keyboard audit \(attempt)")
            editor.typeKey(.rightArrow, modifierFlags: [])
            XCTAssertTrue(waitUntilChosen(first))
            tap(button("inspector.replace-comments.cancel", in: app))
            XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        }
    }

    @MainActor
    func testAccessibilityAppearancesSupportRepeatedTransitions() throws {
        let app = configuredApp(additionalArguments: [
            "--ui-testing-reduce-motion",
            "--ui-testing-increased-contrast",
            "--ui-testing-reduce-transparency"
        ])
        app.launch()

        let first = waitForFixtureImage(1, in: app)

        for _ in 0..<2 {
            tap(first)
            XCTAssertTrue(waitUntilChosen(first))
            app.typeKey(.space, modifierFlags: [])
            XCTAssertTrue(element("preview.quick", in: app).waitForExistence(timeout: 5))
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(element("preview.quick", in: app).waitForNonExistence(timeout: 5))
            XCTAssertTrue(first.waitForExistence(timeout: 5))

            selectViewMode("list", in: app)
            XCTAssertTrue(element("image.list", in: app).waitForExistence(timeout: 5))
            selectViewMode("grid", in: app)
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
    private func configuredApp(additionalArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        let defaultsSuite = "MicroficheUITests.\(UUID().uuidString)"
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "-isOnboardingEnabled", "NO",
            "-hasCompletedOnboarding", "YES",
            "--ui-testing",
            "--ui-testing-fixtures",
            "--ui-testing-defaults-suite", defaultsSuite
        ] + additionalArguments
        return app
    }

    @MainActor
    private func relaunch(_ app: XCUIApplication) {
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 8))
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 8))
    }

    @MainActor
    private func fixtureImage(_ index: Int, in app: XCUIApplication) -> XCUIElement {
        let identifier = String(format: "image.fixture-%02d.png", index)
        let button = app.buttons[identifier]
        if button.waitForExistence(timeout: 0.2) {
            return button
        }
        return element(identifier, in: app)
    }

    @MainActor
    private func waitForFixtureImage(_ index: Int, in app: XCUIApplication) -> XCUIElement {
        let image = fixtureImage(index, in: app)
        if image.waitForExistence(timeout: 3) {
            return image
        }

        for identifier in ["image.grid", "image.list", "library.sidebar"] {
            let scroller = element(identifier, in: app)
            if scroller.exists {
                scroller.scroll(byDeltaX: 0, deltaY: identifier == "library.sidebar" ? 240 : -480)
            }
        }

        XCTAssertTrue(
            image.waitForExistence(timeout: 8),
            "Expected fixture image \(index) in the isolated library"
        )
        return image
    }

    @MainActor
    private func button(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons[identifier]
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons.matching(identifier: identifier).firstMatch
        if button.exists {
            return button
        }
        return app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected \(element) to exist before clicking")
        if element.isHittable {
            element.click()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }
    }

    @MainActor
    private func selectViewMode(_ mode: String, in app: XCUIApplication) {
        let control = button("viewMode.\(mode)", in: app)
        XCTAssertTrue(control.waitForExistence(timeout: 5), "Missing viewMode.\(mode)")
        tap(control)
        if !waitUntilChosen(control, timeout: 1) {
            app.typeKey(mode == "list" ? "2" : "1", modifierFlags: .command)
        }
        XCTAssertTrue(
            waitUntilChosen(control),
            "Expected viewMode.\(mode) to become selected"
        )
    }

    @MainActor
    private func waitUntilChosen(
        _ element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        waitUntil(timeout: timeout) {
            element.isSelected || (element.value as? String) == "Selected"
        }
    }

    @MainActor
    private func waitUntilNotChosen(
        _ element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        waitUntil(timeout: timeout) {
            !element.isSelected && (element.value as? String) != "Selected"
        }
    }

    @MainActor
    private func waitForInspectorFile(_ name: String, in app: XCUIApplication) {
        let file = element("inspector.current-file", in: app)
        XCTAssertTrue(file.waitForExistence(timeout: 5), "Expected inspector.current-file")
        let matched = waitUntil(timeout: 5) {
            inspectorFileName(file) == name
        }
        XCTAssertTrue(matched, "Inspector showed \(inspectorFileName(file)) instead of \(name)")
    }

    private func inspectorFileName(_ file: XCUIElement) -> String {
        if !file.label.isEmpty {
            return file.label
        }
        return file.value as? String ?? ""
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval,
        _ condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }
}
