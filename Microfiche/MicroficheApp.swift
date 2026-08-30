//
//  MicroficheApp.swift
//  Microfiche
//
//  Created by David Hoang on 6/8/25.
//

import SwiftUI

@main
struct MicroficheApp: App {
    private enum WindowLayout {
        static let defaultWidth: CGFloat = 1371
        static let defaultHeight: CGFloat = 811
        static let minimumWidth: CGFloat = 1100
        static let minimumHeight: CGFloat = 700
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(
                    minWidth: WindowLayout.minimumWidth,
                    minHeight: WindowLayout.minimumHeight
                )
                .transformEnvironment(\.accessibilityReduceMotion) { reduceMotion in
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ui-testing-reduce-motion") {
                        reduceMotion = true
                    }
                    #endif
                }
                .transformEnvironment(\.colorSchemeContrast) { contrast in
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ui-testing-increased-contrast") {
                        contrast = .increased
                    }
                    #endif
                }
        }
        .defaultSize(width: WindowLayout.defaultWidth, height: WindowLayout.defaultHeight)
        .defaultPosition(.center)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .newItem) {
                Button("Move to Archive") {
                    NotificationCenter.default.post(name: .microficheMoveSelectionToArchive, object: nil)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Divider()
                Button("Clear Image Cache") {
                    ImageCache.shared.clearCache()
                    PreviewImageCache.shared.clearCache()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button("Cache Info") {
                    showCacheInfo()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }

            CommandGroup(after: .help) {
                Divider()
                Button("Replay Welcome Onboarding") {
                    UserPreferences.shared.replayOnboarding()
                }
                .disabled(!UserPreferences.shared.isOnboardingEnabled)
            }
        }

        Settings {
            SettingsView()
        }
    }

    private func showCacheInfo() {
        let monitor = PerformanceMonitor.shared
        let hitRate = String(format: "%.1f%%", monitor.cacheHitRate * 100)
        let totalRequests = monitor.totalRequests
        let cacheHits = monitor.cacheHits

        let alert = NSAlert()
        alert.messageText = "Cache Performance"
        alert.informativeText = """
        Cache Hit Rate: \(hitRate)
        Total Requests: \(totalRequests)
        Cache Hits: \(cacheHits)

        Thumbnails and optimized previews are stored in the app's cache directory and will be automatically managed. You can clear them manually if needed.
        """
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Reset Stats")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            monitor.reset()
        }
    }
}
