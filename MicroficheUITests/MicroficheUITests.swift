//
//  MicroficheUITests.swift
//  MicroficheUITests
//
//  Created by David Hoang on 6/8/25.
//

import AppKit
import Darwin
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
        let screen = try XCTUnwrap(NSScreen.main)
        let visible = screen.visibleFrame
        // AppKit screen coordinates have a bottom-left origin; XCTest uses
        // the top-left of the main display.
        let visibleBounds = CGRect(
            x: visible.minX,
            y: screen.frame.maxY - visible.maxY,
            width: visible.width,
            height: visible.height
        )

        for attempt in 1...2 {
            app.launch()
            XCTAssertTrue(
                app.windows.firstMatch.waitForExistence(timeout: 8),
                "Expected a window on launch attempt \(attempt)"
            )
            XCTAssertTrue(waitUntil(timeout: 5) {
                visibleBounds.insetBy(dx: -1, dy: -1).contains(app.windows.firstMatch.frame)
            }, "Fixture window \(app.windows.firstMatch.frame) must fit \(visibleBounds)")
            app.terminate()
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 8))
        }
    }

    @MainActor
    func testPanelControlsStayAtToolbarEdges() throws {
        let app = configuredApp()
        app.launch()

        let sidebar = element("library.sidebar", in: app)
        let inspector = element("inspector.content", in: app)
        let sidebarToggle = sidebarControl(in: app)
        let inspectorToggle = button("inspector.toggle", in: app)
        XCTAssertTrue(sidebar.waitForExistence(timeout: 8))
        XCTAssertFalse(inspectorToggle.isEnabled)
        assertPanelControlsAtEdges(in: app)

        for mode in ["grid", "list"] {
            selectViewMode(mode, in: app)
            tap(waitForFixtureImage(1, in: app))
            XCTAssertTrue(inspectorToggle.isEnabled)

            tap(inspectorToggle)
            XCTAssertTrue(inspector.waitForExistence(timeout: 5))
            assertPanelControlsAtEdges(in: app)

            tap(sidebarToggle)
            XCTAssertTrue(sidebar.waitForNonExistence(timeout: 5))
            assertPanelControlsAtEdges(in: app)

            tap(inspectorToggle)
            XCTAssertTrue(inspector.waitForNonExistence(timeout: 5))
            assertPanelControlsAtEdges(in: app)

            tap(sidebarToggle)
            XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
            assertPanelControlsAtEdges(in: app)
        }

        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "Panel controls at toolbar edges"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testPrimaryNavigationControls() throws {
        let app = configuredApp()
        app.launch()

        XCTAssertTrue(element("library.sidebar", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(sidebarControl(in: app).waitForExistence(timeout: 5))

        let gridButton = button("viewMode.grid", in: app)
        let listButton = button("viewMode.list", in: app)
        XCTAssertTrue(gridButton.waitForExistence(timeout: 5))
        XCTAssertTrue(listButton.waitForExistence(timeout: 5))
        XCTAssertTrue(element("library.filter", in: app).exists)
        XCTAssertTrue(element("library.sort", in: app).exists)
        XCTAssertTrue(element("inspector.toggle", in: app).exists)

        selectViewMode("list", in: app)
        selectViewMode("list", in: app)
        selectViewMode("grid", in: app)
        selectViewMode("grid", in: app)
    }

    @MainActor
    func testCommandFFocusesSearchAndRepeatedQueriesResetResults() throws {
        let app = configuredApp()
        app.launch()

        let first = waitForFixtureImage(1, in: app)
        let second = waitForFixtureImage(2, in: app)
        let searchField = app.searchFields.firstMatch

        for query in ["golden", "Seattle"] {
            app.typeKey("f", modifierFlags: .command)
            XCTAssertTrue(
                searchField.waitForExistence(timeout: 5),
                "Command-F should reveal and focus the library search field"
            )
            searchField.typeKey("a", modifierFlags: .command)
            searchField.typeText(query)
            XCTAssertTrue(first.waitForExistence(timeout: 5))
            XCTAssertTrue(second.waitForNonExistence(timeout: 5))

            searchField.typeKey("a", modifierFlags: .command)
            searchField.typeKey(.delete, modifierFlags: [])
            XCTAssertTrue(second.waitForExistence(timeout: 5))
            tap(first)
        }
    }

    @MainActor
    func testCombinedSearchFiltersAndNoResultsResetInBothViews() throws {
        let app = configuredApp()
        app.launch()
        let first = waitForFixtureImage(1, in: app)
        let second = waitForFixtureImage(2, in: app)
        let search = app.searchFields.firstMatch
        for mode in ["grid", "list"] {
            selectViewMode(mode, in: app)
            tap(first)
            app.typeKey("f", modifierFlags: .command)
            search.typeText("golden")
            XCTAssertTrue(second.waitForNonExistence(timeout: 5))
            XCTAssertTrue(waitUntilChosen(first))

            for (group, option) in [("File Type", "PNG"), ("Tag", "Travel"), ("Finder Label", "Red")] {
                chooseFilter(option, in: group, app: app)
            }
            let summary = element("library.filter-summary", in: app)
            XCTAssertTrue(waitUntil(timeout: 5) {
                let text = summary.label.isEmpty ? (summary.value as? String ?? "") : summary.label
                return text.contains("1 result") && text.contains("Tag Travel")
                    && text.contains("Finder label Red")
            }, "Filter summary: \(summary.debugDescription)")
            XCTAssertTrue(waitUntilChosen(first))
            if mode == "grid" {
                let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                screenshot.name = "Combined library filters"
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }

            chooseFilter("Blue", in: "Finder Label", app: app)
            XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 5))
            XCTAssertFalse(button("inspector.toggle", in: app).isEnabled)
            tap(button("library.clear-filters", in: app))
            XCTAssertTrue(second.waitForExistence(timeout: 5))
            XCTAssertEqual(search.value as? String, "")
            XCTAssertTrue(button("library.clear-filters", in: app).waitForNonExistence(timeout: 5))
        }
    }

    @MainActor
    func testExternalMetadataRefreshAndDetailRetentionRepeatedly() throws {
        // Link a runner-owned folder through the normal file picker so both
        // sandboxed processes can access it without changing app entitlements.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("microfiche-search-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("live-search.png")
        let originalData = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        try originalData.write(to: url)
        let app = configuredApp(additionalArguments: ["--ui-testing-watch-files"])
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: root)
        }
        app.launch()
        _ = waitForFixtureImage(1, in: app)
        tap(app.buttons["Add Folder"])
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(root.path)
        app.typeKey(.return, modifierFlags: [])
        // Confirm the open panel's default action after navigating to the folder.
        // Avoid traversing its remote file-list accessibility tree in XCTest.
        app.typeKey(.return, modifierFlags: [])
        let third = element("image.live-search.png", in: app)
        let search = app.searchFields.firstMatch
        app.typeKey("f", modifierFlags: .command)
        search.typeText("live-search")
        XCTAssertTrue(third.waitForExistence(timeout: 8))
        for attempt in 1...2 {
            app.typeKey("f", modifierFlags: .command)
            search.typeKey("a", modifierFlags: .command)
            search.typeText("Live tag \(attempt)")
            XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 5))
            try setFinderTags(["Live tag \(attempt)"], at: url)
            XCTAssertTrue(third.waitForExistence(timeout: 8), "Finder tag edits should refresh search")
            tap(third)
            XCTAssertTrue(waitUntilChosen(third))
            third.doubleClick()
            XCTAssertTrue(element("image.detail", in: app).waitForExistence(timeout: 5))

            // The selected image still matches as the query and metadata change.
            try setFinderTags(["Live tag \(attempt)", "Updated"], at: url)
            app.typeKey("f", modifierFlags: .command)
            search.typeKey("a", modifierFlags: .command)
            search.typeText("Live tag \(attempt) ")
            XCTAssertTrue(waitUntil(timeout: 8) {
                element("image.detail", in: app).exists
                    && (search.value as? String) == "Live tag \(attempt) "
            })
            // Leave the search editor before Escape so it closes detail.
            search.typeKey(.tab, modifierFlags: [])
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(third.waitForExistence(timeout: 8))
            app.activate()
            tap(app.menuButtons["library.filter"])
            XCTAssertTrue(app.menuItems["Updated"].waitForExistence(timeout: 8))
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(waitUntilChosen(third))

            try setFinderTags([], at: url)
            XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 8))
            tap(button("library.clear-filters", in: app))
            XCTAssertTrue(third.waitForExistence(timeout: 5))

            third.doubleClick()
            XCTAssertTrue(element("image.detail", in: app).waitForExistence(timeout: 5))
            try FileManager.default.removeItem(at: url)
            XCTAssertTrue(element("image.detail", in: app).waitForNonExistence(timeout: 8))
            XCTAssertTrue(third.waitForNonExistence(timeout: 5))
            try originalData.write(to: url)
            XCTAssertTrue(third.waitForExistence(timeout: 8))
            XCTAssertTrue(waitUntilNotChosen(third))
        }
    }

    @MainActor
    func testLocalSourceEditsRefreshSearchWithoutLosingSelection() throws {
        let app = configuredApp()
        app.launch()
        let first = waitForFixtureImage(1, in: app)
        let second = waitForFixtureImage(2, in: app)
        let search = app.searchFields.firstMatch
        tap(first)
        tap(button("inspector.toggle", in: app))
        for source in ["Morning source", "Evening source"] {
            app.typeKey("f", modifierFlags: .command)
            search.typeKey("a", modifierFlags: .command)
            search.typeText("fixture-01")
            let edit = button("inspector.replace-where-from", in: app)
            tap(edit)
            let editor = element("inspector.replace-where-from.editor", in: app)
            tap(editor)
            editor.typeKey("a", modifierFlags: .command)
            editor.typeText(source)
            tap(edit)
            XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
            XCTAssertTrue(waitUntilChosen(first))

            app.typeKey("f", modifierFlags: .command)
            search.typeKey("a", modifierFlags: .command)
            search.typeText(source)
            XCTAssertTrue(first.waitForExistence(timeout: 5))
            XCTAssertTrue(second.waitForNonExistence(timeout: 5))
            XCTAssertTrue(waitUntilChosen(first))
            tap(button("library.clear-filters", in: app))
            XCTAssertTrue(second.waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testSourceDraftsSaveWhenInspectorClosesRepeatedly() throws {
        let app = configuredApp()
        app.launch()
        let first = waitForFixtureImage(1, in: app)
        let second = waitForFixtureImage(2, in: app)
        let search = app.searchFields.firstMatch
        tap(first)
        for source in ["Uncommitted morning", "Uncommitted evening"] {
            tap(button("inspector.toggle", in: app))
            tap(button("inspector.replace-where-from", in: app))
            let editor = element("inspector.replace-where-from.editor", in: app)
            tap(editor)
            editor.typeKey("a", modifierFlags: .command)
            editor.typeText(source)
            let comment = "Comment \(source)"
            tap(button("inspector.replace-comments", in: app))
            let commentsEditor = element("inspector.replace-comments.editor", in: app)
            tap(commentsEditor)
            commentsEditor.typeKey("a", modifierFlags: .command)
            commentsEditor.typeText(comment)
            tap(button("inspector.toggle", in: app))
            XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
            XCTAssertTrue(waitUntilChosen(first))
            // Confirm the asynchronous draft save by reopening the inspector
            // before searching for the newly committed value.
            tap(button("inspector.toggle", in: app))
            let displayedSource = element("inspector.replace-where-from.value", in: app)
            let displayedComment = element("inspector.replace-comments.value", in: app)
            XCTAssertTrue(waitUntil(timeout: 5) {
                displayedSource.label == source || displayedSource.value as? String == source
            })
            XCTAssertTrue(waitUntil(timeout: 5) {
                displayedComment.label == comment || displayedComment.value as? String == comment
            })
            tap(button("inspector.toggle", in: app))
            app.typeKey("f", modifierFlags: .command)
            search.typeText(source)
            XCTAssertTrue(first.waitForExistence(timeout: 5))
            XCTAssertTrue(second.waitForNonExistence(timeout: 5))
            XCTAssertTrue(waitUntilChosen(first))
            tap(button("library.clear-filters", in: app))
            XCTAssertTrue(second.waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testToolbarSearchCanCancelRepeatedly() throws {
        let app = configuredApp()
        app.launch()
        let second = waitForFixtureImage(2, in: app)
        let search = app.searchFields.firstMatch

        for _ in 0..<2 {
            app.typeKey("f", modifierFlags: .command)
            search.typeText("fixture-01")
            XCTAssertTrue(second.waitForNonExistence(timeout: 5))
            search.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(waitUntil(timeout: 5) { (search.value as? String) == "" })
            XCTAssertTrue(second.waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testLibrarySortCanChangeFieldAndDirectionRepeatedly() throws {
        let app = configuredApp()
        app.launch()

        let sortMenu = element("library.sort", in: app)
        XCTAssertTrue(sortMenu.waitForExistence(timeout: 8))

        for _ in 1...2 {
            tap(sortMenu)
            XCTAssertTrue(app.menuItems["Capture Date"].waitForExistence(timeout: 5))
            app.menuItems["Capture Date"].click()

            tap(sortMenu)
            XCTAssertTrue(app.menuItems["Newest First"].waitForExistence(timeout: 5))
            app.menuItems["Newest First"].click()

            tap(sortMenu)
            XCTAssertTrue(app.menuItems["Name"].waitForExistence(timeout: 5))
            app.menuItems["Name"].click()

            tap(sortMenu)
            XCTAssertTrue(app.menuItems["A to Z"].waitForExistence(timeout: 5))
            app.menuItems["A to Z"].click()

            let first = waitForFixtureImage(1, in: app)
            let second = waitForFixtureImage(2, in: app)
            tap(first)
            tap(second)
            XCTAssertTrue(waitUntilChosen(second))
        }
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
        for mode in ["grid", "list"] {
            selectViewMode(mode, in: app)
            let fourth = waitForFixtureImage(4, in: app)

            for _ in 0..<2 {
                for image in [first, second, third, fourth, fifth] {
                    XCTAssertTrue(waitUntilNotChosen(image))
                }
                XCTAssertFalse(button("inspector.toggle", in: app).isEnabled)

                tap(first)
                XCTAssertTrue(waitUntilChosen(first))
                tap(second)
                XCTAssertTrue(waitUntilChosen(second))
                XCTAssertTrue(waitUntilNotChosen(first))
                tap(second)
                XCTAssertTrue(waitUntilChosen(second))

                XCUIElement.perform(withKeyModifiers: .command) { tap(third) }
                XCTAssertTrue(waitUntilChosen(second))
                XCTAssertTrue(waitUntilChosen(third))
                XCUIElement.perform(withKeyModifiers: .command) { tap(third) }
                XCTAssertTrue(waitUntilNotChosen(third))
                XCTAssertTrue(waitUntilChosen(second))

                XCUIElement.perform(withKeyModifiers: .shift) { tap(fifth) }
                for image in [second, third, fourth, fifth] {
                    XCTAssertTrue(waitUntilChosen(image))
                }
                XCTAssertTrue(waitUntilNotChosen(first))

                for _ in 0..<5 {
                    tap(first)
                }
                XCTAssertTrue(waitUntilChosen(first))
                for image in [second, third, fourth, fifth] {
                    XCTAssertTrue(waitUntilNotChosen(image))
                }
                XCTAssertTrue(element("image.detail", in: app).waitForNonExistence(timeout: 5))

                app.typeKey(.rightArrow, modifierFlags: [])
                XCTAssertTrue(waitUntilChosen(second))
                XCTAssertTrue(waitUntilNotChosen(first))
                app.typeKey(.rightArrow, modifierFlags: .shift)
                XCTAssertTrue(waitUntilChosen(second))
                XCTAssertTrue(waitUntilChosen(third))
                app.typeKey(.leftArrow, modifierFlags: [])
                XCTAssertTrue(waitUntilChosen(second))
                XCTAssertTrue(waitUntilNotChosen(third))

                XCUIElement.perform(withKeyModifiers: .command) { tap(second) }
                XCTAssertTrue(waitUntilNotChosen(second))
                XCTAssertFalse(button("inspector.toggle", in: app).isEnabled)
                app.typeKey(.rightArrow, modifierFlags: [])
                XCTAssertTrue(waitUntilChosen(first))
                app.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(waitUntilNotChosen(first))
            }
        }
    }

    @MainActor
    func testViewModeSwitchingPreservesSelectionAndKeyboardFocusRepeatedly() throws {
        let app = configuredApp()
        app.launch()
        let third = waitForFixtureImage(3, in: app)
        let fourth = waitForFixtureImage(4, in: app)
        let fifth = waitForFixtureImage(5, in: app)
        let inspector = button("inspector.toggle", in: app)

        func clickMode(_ mode: String) {
            let control = button("viewMode.\(mode)", in: app)
            tap(control)
            XCTAssertTrue(waitUntilChosen(control), "Pointer click must switch views without a keyboard fallback")
        }

        for _ in 0..<2 {
            // The floating control must not select an image underneath it.
            for mode in ["list", "grid", "list"] {
                clickMode(mode)
                XCTAssertFalse(inspector.isEnabled, "Switching views must preserve an empty selection")
            }

            tap(third)
            tap(inspector)
            waitForInspectorFile("fixture-03.png", in: app)
            for mode in ["grid", "list"] {
                clickMode(mode)
                XCTAssertTrue(waitUntilChosen(third))
                waitForInspectorFile("fixture-03.png", in: app)
            }
            tap(inspector)
            app.typeKey(.rightArrow, modifierFlags: [])
            XCTAssertTrue(waitUntilChosen(fourth), "Keyboard navigation must continue from the preserved focus")
            XCTAssertTrue(waitUntilNotChosen(third))

            XCUIElement.perform(withKeyModifiers: .command) { tap(fifth) }
            for mode in ["grid", "list"] {
                clickMode(mode)
                XCTAssertTrue(waitUntilChosen(fourth))
                XCTAssertTrue(waitUntilChosen(fifth))
            }
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(waitUntilNotChosen(fourth))
            XCTAssertTrue(waitUntilNotChosen(fifth))

            // Exercise rows created after scrolling and both view directions.
            element("image.list", in: app).scroll(byDeltaX: 0, deltaY: -1000)
            let last = waitForFixtureImage(24, in: app)
            tap(last)
            for mode in ["grid", "list"] {
                clickMode(mode)
                XCTAssertTrue(waitUntilChosen(last))
            }
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(waitUntilNotChosen(last))
            element("image.list", in: app).scroll(byDeltaX: 0, deltaY: 1000)
        }
    }

    @MainActor
    func testSelectedAndUnselectedDoubleClicksOpenTheCorrectImageTwice() throws {
        let app = configuredApp()
        app.launch()

        let first = waitForFixtureImage(1, in: app)
        let second = waitForFixtureImage(2, in: app)
        let detail = element("image.detail", in: app)
        for mode in ["grid", "list"] {
            selectViewMode(mode, in: app)
            for initiallySelected in [false, true] {
                for _ in 0..<2 {
                    tap(first)
                    XCTAssertTrue(waitUntilChosen(first))
                    if initiallySelected {
                        tap(second)
                        XCTAssertTrue(waitUntilChosen(second))
                    } else {
                        XCTAssertTrue(waitUntilNotChosen(second))
                    }
                    second.doubleClick()
                    XCTAssertTrue(detail.waitForExistence(timeout: 5))
                    XCTAssertEqual(detail.label, "fixture-02.png")
                    XCTAssertTrue(app.searchFields.firstMatch.exists)
                    app.typeKey(.escape, modifierFlags: [])
                    XCTAssertTrue(detail.waitForNonExistence(timeout: 5))
                    XCTAssertTrue(waitUntilChosen(second))
                    XCTAssertTrue(waitUntilNotChosen(first))
                }
            }
        }
    }

    @MainActor
    func testDetailFitActualSizeAndPanningResetRepeatedly() throws {
        let app = configuredApp(additionalArguments: ["--ui-testing-zoom-images"])
        app.launch()
        for mode in ["grid", "list"] {
            selectViewMode(mode, in: app)
            for index in [1, 2] {
                for _ in 0..<2 {
                    let image = waitForFixtureImage(index, in: app)
                    tap(image)
                    image.doubleClick()
                    let canvas = element("detail.zoom.canvas", in: app)
                    XCTAssertTrue(canvas.waitForExistence(timeout: 10))
                    XCTAssertTrue(waitUntil(timeout: 5) {
                        canvas.value as? String == "Fit, horizontal offset 0, vertical offset 0"
                    })
                    let fit = button("detail.zoom.fit", in: app)
                    let actualSize = button("detail.zoom.actualSize", in: app)
                    for _ in 0..<2 {
                        tap(actualSize)
                        XCTAssertEqual(actualSize.value as? String, "Selected")
                        let centered = "100%, horizontal offset 0, vertical offset 0"
                        XCTAssertTrue(waitUntil(timeout: 5) { canvas.value as? String == centered })
                        XCTAssertTrue(canvas.isHittable)
                        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6))
                            .click(forDuration: 0.1, thenDragTo:
                                canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35)))
                        XCTAssertTrue(waitUntil(timeout: 5) { canvas.value as? String != centered })
                        XCTAssertTrue((canvas.value as? String)?.hasPrefix("100%") == true)
                        tap(button("detail.inspector.toggle", in: app))
                        XCTAssertTrue((canvas.value as? String)?.hasPrefix("100%") == true)
                        tap(button("detail.inspector.toggle", in: app))
                        tap(fit)
                        XCTAssertEqual(fit.value as? String, "Selected")
                        XCTAssertTrue(waitUntil(timeout: 5) {
                            canvas.value as? String == "Fit, horizontal offset 0, vertical offset 0"
                        })
                    }
                    // Inspector changes exercise viewport resizing without resetting the image.
                    for _ in 0..<2 {
                        tap(button("detail.inspector.toggle", in: app))
                        XCTAssertEqual(canvas.value as? String, "Fit, horizontal offset 0, vertical offset 0")
                    }
                    tap(actualSize)
                    app.typeKey(.escape, modifierFlags: [])
                    XCTAssertTrue(canvas.waitForNonExistence(timeout: 5))
                }
            }
        }
        let small = waitForFixtureImage(3, in: app)
        tap(small)
        small.doubleClick()
        let canvas = element("detail.zoom.canvas", in: app)
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        tap(button("detail.zoom.actualSize", in: app))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6))
            .click(forDuration: 0.1, thenDragTo:
                canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35)))
        XCTAssertEqual(canvas.value as? String, "100%, horizontal offset 0, vertical offset 0")
    }

    @MainActor
    func testDragAndContextMenuDoNotDisableLaterClicksTwiceInBothViews() throws {
        let app = configuredApp()
        app.launch()
        let destination = element("sidebar.contact-sheet.Second Review", in: app)
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        var expectedCount = 4

        for (modeIndex, mode) in ["grid", "list"].enumerated() {
            selectViewMode(mode, in: app)
            for attempt in 0..<2 {
                // Use a new source each time so the sheet's count proves a
                // real drag occurred, not just a mouse-down inside the cell.
                let source = waitForFixtureImage(modeIndex * 2 + attempt + 1, in: app)
                tap(source)
                XCTAssertTrue(waitUntilChosen(source))
                let start = source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                let end = destination.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                start.click(forDuration: 0.2, thenDragTo: end)
                expectedCount += 1
                XCTAssertTrue(waitUntil(timeout: 8) {
                    let value = destination.value as? String
                    return value == "\(expectedCount) images"
                        || value == "Selected, \(expectedCount) images"
                }, "A completed drop must add exactly one fixture image")

                let next = waitForFixtureImage(9, in: app)
                tap(next)
                XCTAssertTrue(waitUntilChosen(next))
                XCTAssertTrue(waitUntilNotChosen(source))
                next.rightClick()
                let contextMenu = app.menus.containing(.menuItem, identifier: "Open in Finder").firstMatch
                XCTAssertTrue(contextMenu.waitForExistence(timeout: 5))
                let archive = contextMenu.menuItems["Move to Archive"]
                XCTAssertTrue(archive.waitForExistence(timeout: 5))
                XCTAssertTrue(archive.isHittable)
                app.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(contextMenu.waitForNonExistence(timeout: 5))
                let later = waitForFixtureImage(10, in: app)
                tap(later)
                XCTAssertTrue(waitUntilChosen(later))
                XCTAssertTrue(waitUntilNotChosen(next))
            }
        }
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
        let toggle = sidebarControl(in: app)
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
        let more = app.menuButtons["detail.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        // Native macOS menu buttons expose their accessible name as AXTitle.
        XCTAssertEqual(more.title, "More actions for fixture-02.png")
        for _ in 0..<2 {
            tap(more)
            XCTAssertTrue(app.menuItems["Reveal in Finder"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.menuItems["Copy Path"].exists)
            app.typeKey(.escape, modifierFlags: [])
        }
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
            // Editable NSTextView reports AXEnabled=false, unlike NSControl.
            // Require a real pointer target and prove editing by reading it back.
            XCTAssertTrue(waitUntil(timeout: 5) { editor.isHittable })
            editor.click()
            editor.typeText("Keyboard audit \(attempt)")
            XCTAssertTrue((editor.value as? String)?.contains("Keyboard audit \(attempt)") == true)
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
    func testQuickPreviewDismissalRestoresBrowsingFocusRepeatedly() throws {
        let app = configuredApp()
        app.launch()

        for mode in ["grid", "list"] {
            selectViewMode(mode, in: app)
            for dismissal in ["button", "escape", "space", "backdrop"] {
                tap(waitForFixtureImage(1, in: app))
                app.typeKey(.space, modifierFlags: [])
                let preview = element("preview.quick", in: app)
                XCTAssertTrue(preview.waitForExistence(timeout: 5))
                XCTAssertTrue(button("preview.close", in: app).isHittable)

                app.typeKey(.rightArrow, modifierFlags: [])
                XCTAssertTrue(waitUntil(timeout: 5) {
                    preview.label == "Quick preview of fixture-02.png"
                })
                app.typeKey(.leftArrow, modifierFlags: [])
                XCTAssertTrue(waitUntil(timeout: 5) {
                    preview.label == "Quick preview of fixture-01.png"
                })

                switch dismissal {
                case "button": tap(button("preview.close", in: app))
                case "escape": app.typeKey(.escape, modifierFlags: [])
                case "space": app.typeKey(.space, modifierFlags: [])
                default:
                    preview.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).click()
                }
                XCTAssertTrue(preview.waitForNonExistence(timeout: 5))
                XCTAssertTrue(waitUntilChosen(waitForFixtureImage(1, in: app)))
                app.typeKey(.rightArrow, modifierFlags: [])
                XCTAssertTrue(waitUntilChosen(waitForFixtureImage(2, in: app)))
                app.typeKey(.leftArrow, modifierFlags: [])
                XCTAssertTrue(waitUntilChosen(waitForFixtureImage(1, in: app)))
            }
        }
    }

    @MainActor
    func testNarrowInspectorLabelsRemainReachableRepeatedly() throws {
        let app = configuredApp(additionalArguments: ["--ui-testing-minimum-window"])
        app.launch()
        tap(waitForFixtureImage(1, in: app))
        tap(button("inspector.toggle", in: app))
        let inspector = element("inspector.content", in: app)
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))

        for _ in 0..<2 {
            for index in 0...7 {
                let label = button("inspector.label.\(index)", in: app)
                XCTAssertTrue(label.waitForExistence(timeout: 5))
                XCTAssertTrue(label.isHittable)
                XCTAssertGreaterThanOrEqual(label.frame.minX, inspector.frame.minX)
                XCTAssertLessThanOrEqual(label.frame.maxX, inspector.frame.maxX)
                tap(label)
                XCTAssertTrue(waitUntilChosen(label))
            }
        }
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "Finder labels in minimum-size window"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testFloatingViewControlNeverCoversLastItemRepeatedly() throws {
        for arguments in [[], ["--ui-testing-minimum-window"]] {
            let app = configuredApp(additionalArguments: arguments)
            app.launch()
            for attempt in 0..<2 {
                for mode in ["list", "grid"] {
                    let control = button("viewMode.\(mode)", in: app)
                    XCTAssertTrue(control.waitForExistence(timeout: 5))
                    XCTAssertTrue(control.isHittable)
                    tap(control)
                    XCTAssertTrue(waitUntilChosen(control))
                    if mode == "grid" {
                        let slider = app.sliders.firstMatch
                        XCTAssertTrue(slider.isHittable)
                        let thumb = slider.valueIndicators.firstMatch
                        XCTAssertTrue(thumb.exists)
                        let start = thumb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                        let end = slider.coordinate(withNormalizedOffset: CGVector(dx: attempt == 0 ? 0.99 : 0.01, dy: 0.5))
                        start.click(forDuration: 0.1, thenDragTo: end)
                        XCTAssertEqual(slider.value as? String, "\(attempt == 0 ? 180 : 80) points")
                    }
                    element("image.\(mode)", in: app).scroll(byDeltaX: 0, deltaY: -3000)
                    let last = waitForFixtureImage(24, in: app)
                    XCTAssertTrue(last.isHittable)
                    XCTAssertLessThanOrEqual(last.frame.maxY, control.frame.minY)
                    tap(last)
                    XCTAssertTrue(waitUntilChosen(last))
                }
            }
            app.terminate()
        }
    }

    @MainActor
    func testNativeSidebarButtonsAndContactSheetRenameRepeatedly() throws {
        let app = configuredApp()
        app.launch()
        let allImages = button("sidebar.all-images", in: app)
        XCTAssertTrue(allImages.waitForExistence(timeout: 5))

        for attempt in 1...2 {
            tap(allImages)
            let sheet = button("sidebar.contact-sheet.First Review", in: app)
            XCTAssertTrue(sheet.waitForExistence(timeout: 5))
            tap(sheet)
            XCTAssertTrue(waitUntilChosen(sheet))
            sheet.rightClick()
            app.menuItems["Rename"].click()
            let editor = app.textFields["sidebar.contact-sheet-name"]
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            editor.typeKey("a", modifierFlags: .command)
            editor.typeText("Review \(attempt)")
            editor.typeKey(.return, modifierFlags: [])

            let renamed = button("sidebar.contact-sheet.Review \(attempt)", in: app)
            XCTAssertTrue(renamed.waitForExistence(timeout: 5))
            renamed.rightClick()
            app.menuItems["Rename"].click()
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            editor.typeKey("a", modifierFlags: .command)
            editor.typeText("First Review")
            editor.typeKey(.return, modifierFlags: [])
            XCTAssertTrue(sheet.waitForExistence(timeout: 5))
            tap(allImages)
            XCTAssertTrue(waitUntilChosen(allImages))
            tap(waitForFixtureImage(1, in: app))
            app.typeKey(.rightArrow, modifierFlags: [])
            XCTAssertTrue(waitUntilChosen(waitForFixtureImage(2, in: app)))
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
    private func sidebarControl(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "label == %@ OR label == %@", "Show Sidebar", "Hide Sidebar"
        )).firstMatch
    }

    @MainActor
    private func assertPanelControlsAtEdges(in app: XCUIApplication) {
        let sidebarToggle = sidebarControl(in: app)
        let inspectorToggle = button("inspector.toggle", in: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(app.searchFields.count, 1)
        let controlsAtEdges = waitUntil(timeout: 5) {
            let window = app.windows.firstMatch.frame
            return sidebarToggle.frame.maxX < window.minX + window.width * 0.25
                // AppKit includes a one-point bezel outside the search view.
                && inspectorToggle.frame.minX >= search.frame.maxX - 1
        }
        if !controlsAtEdges {
            add(XCTAttachment(screenshot: app.windows.firstMatch.screenshot()))
        }
        XCTAssertTrue(controlsAtEdges,
            "Sidebar must be at the leading edge and inspector after search. "
            + "Window: \(app.windows.firstMatch.frame), sidebar: \(sidebarToggle.frame), "
            + "search: \(search.frame), inspector: \(inspectorToggle.frame)"
        )
        XCTAssertEqual(
            app.buttons.matching(NSPredicate(
                format: "identifier == %@ OR label ==[c] %@ OR label ==[c] %@ OR label ==[c] %@",
                "sidebar.toggle", "Toggle Sidebar", "Show Sidebar", "Hide Sidebar"
            )).count,
            1,
            "The toolbar must not contain both native and custom sidebar toggles"
        )
    }

    @MainActor
    private func chooseFilter(_ option: String, in group: String, app: XCUIApplication) {
        app.activate()
        tap(app.menuButtons["library.filter"])
        XCTAssertTrue(app.menuItems[group].waitForExistence(timeout: 5))
        app.menuItems[group].hover()
        XCTAssertTrue(app.menuItems[option].waitForExistence(timeout: 5))
        app.menuItems[option].click()
        XCTAssertTrue(app.menuItems["Clear Filters"].waitForNonExistence(timeout: 5))
    }

    private func setFinderTags(_ tags: [String], at url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: tags, format: .binary, options: 0)
        let result = data.withUnsafeBytes {
            setxattr(url.path, "com.apple.metadata:_kMDItemUserTags", $0.baseAddress, $0.count, 0, 0)
        }
        XCTAssertEqual(result, 0, "Unable to update fixture Finder tags, errno \(errno)")
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
        if waitUntil(timeout: 3, { image.exists && image.isHittable }) {
            return image
        }

        for _ in 0..<6 {
            for identifier in ["image.grid", "image.list"] {
                let scroller = element(identifier, in: app)
                if scroller.exists {
                    scroller.scroll(byDeltaX: 0, deltaY: index > 12 ? -400 : 400)
                }
            }
            if image.exists && image.isHittable { break }
        }

        XCTAssertTrue(
            waitUntil(timeout: 8, { image.exists && image.isHittable }),
            "Expected a visible, hittable fixture image \(index) in the isolated library"
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
        guard waitUntil(timeout: 5, { element.isEnabled && element.isHittable }) else {
            XCTFail("Expected an enabled, hittable click target: \(element.debugDescription)")
            return
        }
        element.click()
    }

    @MainActor
    private func selectViewMode(_ mode: String, in app: XCUIApplication) {
        let control = button("viewMode.\(mode)", in: app)
        XCTAssertTrue(control.waitForExistence(timeout: 5), "Missing viewMode.\(mode)")
        tap(control)
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
            element.exists && (element.isSelected || (element.value as? String) == "Selected")
        }
    }

    @MainActor
    private func waitUntilNotChosen(
        _ element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        waitUntil(timeout: timeout) {
            element.exists && !element.isSelected && (element.value as? String) == "Not selected"
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
