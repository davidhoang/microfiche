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

    var isICloudDrive: Bool {
        LibraryLocationPresentation.isICloudDrivePath(
            resolvedURL ?? URL(fileURLWithPath: originalPath)
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

struct LibraryLocationRecovery: Equatable {
    let title: String
    let message: String
    let systemImage: String

    static func current(
        selectedFolder: LinkedLibraryFolder?,
        viewingAllImages: Bool,
        folders: [LinkedLibraryFolder],
        hasVisibleImages: Bool
    ) -> LibraryLocationRecovery? {
        if let selectedFolder, !selectedFolder.isAvailable {
            return presentation(for: [selectedFolder])
        }

        guard viewingAllImages, !hasVisibleImages else { return nil }

        let unavailableFolders = folders.filter { !$0.isAvailable }
        guard !unavailableFolders.isEmpty else { return nil }
        return presentation(for: unavailableFolders)
    }

    private static func presentation(
        for folders: [LinkedLibraryFolder]
    ) -> LibraryLocationRecovery {
        if folders.count == 1, let folder = folders.first {
            if folder.isICloudDrive {
                return LibraryLocationRecovery(
                    title: "iCloud Drive unavailable",
                    message: "Check your network connection and iCloud Drive status, then try again.",
                    systemImage: "icloud.slash"
                )
            }

            let driveName = folder.volumeName ?? folder.name
            return LibraryLocationRecovery(
                title: "Reconnect the drive",
                message: "Reconnect \(driveName) to restore \(folder.displayName) automatically.",
                systemImage: "externaldrive.badge.xmark"
            )
        }

        if folders.allSatisfy(\.isICloudDrive) {
            return LibraryLocationRecovery(
                title: "iCloud Drive unavailable",
                message: "Check your network connection and iCloud Drive status, then try again.",
                systemImage: "icloud.slash"
            )
        }

        let names = folders.map(\.displayName).joined(separator: ", ")
        return LibraryLocationRecovery(
            title: "Locations unavailable",
            message: "Reconnect the offline folders to restore \(names) automatically.",
            systemImage: "externaldrive.badge.xmark"
        )
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

    static func isICloudDrivePath(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.contains(iCloudDriveDirectoryName)
    }
}
