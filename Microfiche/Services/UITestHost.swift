//
//  UITestHost.swift
//  Microfiche
//
//  Host-side hooks so UI tests launch a consistent window instead of
//  depending on a developer’s saved frame, iCloud, or personal folders.
//

import AppKit
import Foundation

enum UITestHost {
    static var isLaunchedForUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing")
    }

    static var usesFixtureLibrary: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-fixtures")
    }

    static var reduceMotion: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-reduce-motion")
    }

    static var increasedContrast: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-increased-contrast")
    }

    static var reduceTransparency: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-reduce-transparency")
    }

    @MainActor
    static func applyWindowLayoutIfNeeded() {
        guard isLaunchedForUITesting else { return }

        let size = NSSize(width: 1440, height: 900)
        for window in NSApplication.shared.windows where window.isVisible {
            window.setContentSize(size)
            window.center()
        }
    }
}
