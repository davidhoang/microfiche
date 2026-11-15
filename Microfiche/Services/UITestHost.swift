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

    /// Host displays (including GitHub Actions) can report a visible frame that is a
    /// few points shorter than the frame AppKit settles on after toolbar layout.
    private static let visibleFrameHeightSlack: CGFloat = 4

    static func fittingWindowFrame(preferredFrame: NSRect, visibleFrame: NSRect) -> NSRect {
        let maxHeight = max(0, visibleFrame.height - visibleFrameHeightSlack)
        let size = NSSize(
            width: min(preferredFrame.width, visibleFrame.width),
            height: min(preferredFrame.height, maxHeight)
        )
        var origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2
        )
        origin.x = min(
            max(origin.x, visibleFrame.minX),
            visibleFrame.maxX - size.width
        )
        origin.y = min(
            max(origin.y, visibleFrame.minY),
            visibleFrame.maxY - size.height
        )
        return NSRect(origin: origin, size: size)
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
