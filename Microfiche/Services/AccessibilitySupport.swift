//
//  AccessibilitySupport.swift
//  Microfiche
//

import AppKit
import Foundation

enum MicroficheAccessibility {
    static func selectionAnnouncement(
        selectedFiles: [ImageFile],
        focusedFile: ImageFile?
    ) -> String {
        switch selectedFiles.count {
        case 0:
            return "No images selected"
        case 1:
            return "\((focusedFile ?? selectedFiles[0]).name) selected"
        default:
            if let focusedFile {
                return "\(selectedFiles.count) images selected, \(focusedFile.name) focused"
            }
            return "\(selectedFiles.count) images selected"
        }
    }

    static func dropAnnouncement(addedCount: Int, contactSheetName: String) -> String {
        switch addedCount {
        case 0:
            return "No new images added to \(contactSheetName)"
        case 1:
            return "1 image added to \(contactSheetName)"
        default:
            return "\(addedCount) images added to \(contactSheetName)"
        }
    }

    static func imageLoadAnnouncement(
        phase: ImageLoadPhase,
        fileName: String
    ) -> String? {
        switch phase {
        case .idle:
            return nil
        case .placeholder:
            return "\(fileName) is stored in iCloud and needs to be downloaded"
        case .downloading:
            return "Downloading \(fileName) from iCloud"
        case .retrying:
            return "Retrying \(fileName)"
        case .loading:
            return "Loading \(fileName)"
        case .loaded:
            return nil
        case .failed(let message):
            return "\(fileName) unavailable. \(message)"
        case .cancelled:
            return "Loading \(fileName) cancelled"
        }
    }

    @MainActor
    static func announce(_ message: String, priority: NSAccessibilityPriorityLevel = .medium) {
        guard !message.isEmpty else { return }
        let element: Any
        if let window = NSApp.mainWindow ?? NSApp.keyWindow {
            element = window
        } else {
            element = NSApp
        }
        NSAccessibility.post(
            element: element,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: priority.rawValue
            ]
        )
    }
}
