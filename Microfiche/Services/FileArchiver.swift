//
//  FileArchiver.swift
//  Microfiche
//
//  Moves image files into a user-defined archive folder.
//

import Foundation

enum FileArchiver {
    /// Returns a destination URL in `directory` that does not collide with existing files.
    /// Uses `name.ext`, then `name-1.ext`, `name-2.ext`, …
    static func uniqueDestination(
        for source: URL,
        in directory: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let baseName = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var candidate = directory.appendingPathComponent(source.lastPathComponent)

        var suffix = 1
        while fileManager.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(baseName)-\(suffix)" : "\(baseName)-\(suffix).\(ext)"
            candidate = directory.appendingPathComponent(numbered)
            suffix += 1
        }
        return candidate
    }

    /// Moves `source` into `directory`, renaming on collision. Returns the final URL.
    @discardableResult
    static func move(
        _ source: URL,
        intoArchive directory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ArchiveError.destinationUnavailable
        }

        let destination = uniqueDestination(for: source, in: directory, fileManager: fileManager)
        try fileManager.moveItem(at: source, to: destination)
        return destination
    }

    enum ArchiveError: LocalizedError {
        case destinationUnavailable

        var errorDescription: String? {
            switch self {
            case .destinationUnavailable:
                return "The archive folder is unavailable."
            }
        }
    }
}
