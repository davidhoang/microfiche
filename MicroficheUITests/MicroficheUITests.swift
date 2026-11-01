//
//  MicroficheUITests.swift
//  MicroficheUITests
//
//  Created by David Hoang on 6/8/25.
//

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
                XCTAssertTrue(app.searchFields.firstMatch.exists)
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
