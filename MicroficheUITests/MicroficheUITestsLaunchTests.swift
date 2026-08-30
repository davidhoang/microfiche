//
//  MicroficheUITestsLaunchTests.swift
//  MicroficheUITests
//
//  Created by David Hoang on 6/8/25.
//

import XCTest

final class MicroficheUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ApplePersistenceIgnoreState", "YES",
            "--ui-testing",
            "--ui-testing-fixtures",
            "--ui-testing-defaults-suite",
            "MicroficheUITests.Launch.\(UUID().uuidString)"
        ]
        app.launch()
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "image.fixture-01.png")
                .firstMatch
                .waitForExistence(timeout: 5)
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
