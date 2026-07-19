//
//  LibraryLocation.swift
//  Microfiche
//

import Foundation

struct LinkedLibraryFolder: Identifiable, Equatable {
    let id: UUID
    let name: String
    let originalPath: String
    let volumeIdentifier: String?
    let volumeName: String?
    let isExternal: Bool
    let addedAt: Date
    let resolvedURL: URL?

    var isAvailable: Bool { resolvedURL != nil }

    var displayName: String {
        LibraryLocationPresentation.displayName(
            for: resolvedURL ?? URL(fileURLWithPath: originalPath),
            fallback: name
        )
    }
}

struct RememberedExternalVolume: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var lastKnownMountPath: String
    let addedAt: Date
    var lastSeenAt: Date
    var isConnected: Bool
}

struct AddedLibraryLocations {
    let folders: [LinkedLibraryFolder]
    let newlyRememberedVolumes: [RememberedExternalVolume]
}

enum LibraryVolumeClassification {
    static func isExternal(
        isRemovable: Bool,
        isEjectable: Bool,
        mountPath: String
    ) -> Bool {
        isRemovable
            || isEjectable
            || (mountPath.hasPrefix("/Volumes/") && mountPath != "/")
    }
}

enum LibraryLocationPresentation {
    private static let iCloudDriveDirectoryName = "com~apple~CloudDocs"

    static func displayName(for url: URL, fallback: String) -> String {
        let standardizedURL = url.standardizedFileURL
        let pathComponents = standardizedURL.pathComponents

        guard let iCloudDriveIndex = pathComponents.firstIndex(of: iCloudDriveDirectoryName) else {
            return standardizedURL.lastPathComponent.isEmpty
                ? fallback
                : standardizedURL.lastPathComponent
        }

        let relativeComponents = pathComponents.dropFirst(iCloudDriveIndex + 1)
        return relativeComponents.last ?? "iCloud Drive"
    }
}
