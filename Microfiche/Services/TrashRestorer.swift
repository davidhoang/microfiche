//
//  TrashRestorer.swift
//  Microfiche
//
//  Restores files from the system Trash to their original locations.
//

import Foundation

struct TrashedFileLocation: Equatable {
    let originalURL: URL
    let trashURL: URL
}

struct TrashRestorationResult {
    let restored: [TrashedFileLocation]
    let failed: [TrashedFileLocation]
}

enum TrashRestorer {
    static func restore(
        _ files: [TrashedFileLocation],
        fileManager: FileManager = .default
    ) -> TrashRestorationResult {
        var restored: [TrashedFileLocation] = []
        var failed: [TrashedFileLocation] = []

        for file in files {
            do {
                try fileManager.moveItem(at: file.trashURL, to: file.originalURL)
                restored.append(file)
            } catch {
                failed.append(file)
            }
        }

        return TrashRestorationResult(restored: restored, failed: failed)
    }
}
