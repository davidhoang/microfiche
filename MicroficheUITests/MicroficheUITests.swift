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

        let inspectorButton = element("inspector.toggle", in: app)
        XCTAssertTrue(inspectorButton.waitForExistence(timeout: 3))
        inspectorButton.click()
        XCTAssertTrue(inspectorButton.waitForExistence(timeout: 2))
        inspectorButton.click()
        XCTAssertTrue(inspectorButton.exists)
        inspectorButton.click()
        XCTAssertTrue(inspectorButton.exists)
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
            "--ui-testing"
        ]
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
