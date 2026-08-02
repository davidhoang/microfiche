//
//  MicroficheUITests.swift
//  MicroficheUITests
//
//  Created by David Hoang on 6/8/25.
//

import XCTest

final class MicroficheUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it's important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
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
    func testThumbnailSizeSliderSupportsRepeatedAdjustments() throws {
        let app = configuredApp()
        app.launch()

        let slider = app.sliders["thumbnail-size-slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))

        drag(slider, from: 0.5, to: 0.2)
        let smallerValue = try XCTUnwrap(slider.value as? String)

        drag(slider, from: 0.2, to: 0.8)
        let largerValue = try XCTUnwrap(slider.value as? String)
        XCTAssertNotEqual(largerValue, smallerValue)

        drag(slider, from: 0.8, to: 0.2)
        XCTAssertEqual(slider.value as? String, smallerValue)
    }

    @MainActor
    private func drag(_ slider: XCUIElement, from start: CGFloat, to end: CGFloat) {
        let startCoordinate = slider.coordinate(
            withNormalizedOffset: CGVector(dx: start, dy: 0.5)
        )
        let endCoordinate = slider.coordinate(
            withNormalizedOffset: CGVector(dx: end, dy: 0.5)
        )
        startCoordinate.press(forDuration: 0.05, thenDragTo: endCoordinate)
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
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
            "-hasCompletedOnboarding", "YES"
        ]
        return app
    }
}
