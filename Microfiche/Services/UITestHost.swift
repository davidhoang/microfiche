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

    static func fittingWindowFrame(preferredFrame: NSRect, visibleFrame: NSRect) -> NSRect {
        let size = NSSize(
            width: min(preferredFrame.width, visibleFrame.width),
            height: min(preferredFrame.height, visibleFrame.height)
        )
        return NSRect(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    @MainActor
    static func applyWindowLayoutIfNeeded() {
        guard isLaunchedForUITesting else { return }

        let size = ProcessInfo.processInfo.arguments.contains("--ui-testing-minimum-window")
            ? NSSize(width: 1100, height: 700)
            : NSSize(width: 1440, height: 900)
        for window in NSApplication.shared.windows where window.isVisible {
            guard let screen = window.screen ?? NSScreen.main else { continue }
            let preferredFrame = window.frameRect(
                forContentRect: NSRect(origin: .zero, size: size)
            )
            // Include titlebar chrome and the menu bar/Dock safe area. A fixed
            // content size can put toolbar buttons outside a hosted display.
            window.setFrame(
                fittingWindowFrame(
                    preferredFrame: preferredFrame,
                    visibleFrame: screen.visibleFrame
                ),
                display: true
            )
        }
    }
}
