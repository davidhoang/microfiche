//
//  LibraryStorage.swift
//  Microfiche
//

import AppKit
import Combine
import Foundation

@MainActor
final class LibraryStorage: ObservableObject {
    static let shared = LibraryStorage()

    @Published private(set) var linkedFolders: [LinkedLibraryFolder] = []
    @Published private(set) var rememberedExternalVolumes: [RememberedExternalVolume] = []

    var availableFolderURLs: [URL] {
        linkedFolders.compactMap(\.resolvedURL)
    }

    private struct FolderRecord: Codable, Equatable {
        let id: UUID
        var bookmark: Data
        let name: String
        let originalPath: String
        let volumeIdentifier: String?
        let volumeName: String?
        let isExternal: Bool
        let addedAt: Date
    }

    private struct PersistedLibrary: Codable {
        var folders: [FolderRecord]
        var externalVolumes: [RememberedExternalVolume]
    }

    private struct VolumeDetails {
        let identifier: String
        let name: String
        let mountPath: String
        let isExternal: Bool
    }

    private let fileManager: FileManager
    private let persistenceURL: URL
    private var folderRecords: [FolderRecord] = []
    private var activeSecurityScopedURLs: [UUID: URL] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []

    init(
        persistenceURL customPersistenceURL: URL? = nil,
        fileManager: FileManager = .default,
        observesWorkspace: Bool = true
    ) {
        self.fileManager = fileManager

        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let libraryDirectory = applicationSupport.appendingPathComponent("Microfiche", isDirectory: true)
        persistenceURL = customPersistenceURL
            ?? libraryDirectory.appendingPathComponent("library.json")

        try? fileManager.createDirectory(
            at: persistenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        load()
        refreshLocations()

        if observesWorkspace {
            observeWorkspaceVolumes()
        }
    }

    deinit {
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        for url in activeSecurityScopedURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
    }

    func folder(id: UUID) -> LinkedLibraryFolder? {
        linkedFolders.first { $0.id == id }
    }

    func addFolders(_ urls: [URL]) -> AddedLibraryLocations {
        var addedFolderIDs: [UUID] = []
        var newlyRememberedVolumeIDs: [String] = []

        for sourceURL in urls {
            let url = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
            guard !folderRecords.contains(where: { $0.originalPath == url.path }) else { continue }

            do {
                let bookmark = try url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                let volume = volumeDetails(for: url)
                let record = FolderRecord(
                    id: UUID(),
                    bookmark: bookmark,
                    name: url.lastPathComponent,
                    originalPath: url.path,
                    volumeIdentifier: volume?.identifier,
                    volumeName: volume?.name,
                    isExternal: volume?.isExternal == true,
                    addedAt: Date()
                )
                folderRecords.append(record)
                addedFolderIDs.append(record.id)

                if let volume, volume.isExternal,
                   !rememberedExternalVolumes.contains(where: { $0.id == volume.identifier }) {
                    rememberedExternalVolumes.append(
                        RememberedExternalVolume(
                            id: volume.identifier,
                            name: volume.name,
                            lastKnownMountPath: volume.mountPath,
                            addedAt: Date(),
                            lastSeenAt: Date(),
                            isConnected: true
                        )
                    )
                    newlyRememberedVolumeIDs.append(volume.identifier)
                }
            } catch {
                print("Unable to remember folder \(url.path): \(error)")
            }
        }

        refreshLocations(saveAfterRefresh: true)

        return AddedLibraryLocations(
            folders: linkedFolders.filter { addedFolderIDs.contains($0.id) },
            newlyRememberedVolumes: rememberedExternalVolumes.filter {
                newlyRememberedVolumeIDs.contains($0.id)
            }
        )
    }

    func removeFolder(id: UUID) {
        if let url = activeSecurityScopedURLs.removeValue(forKey: id) {
            url.stopAccessingSecurityScopedResource()
        }
        folderRecords.removeAll { $0.id == id }
        refreshLocations(saveAfterRefresh: true)
    }

    func forgetExternalVolume(id: String) {
        rememberedExternalVolumes.removeAll { $0.id == id }
        save()
    }

    func refreshLocations(saveAfterRefresh: Bool = false) {
        var refreshedRecords = folderRecords
        var resolvedFolders: [LinkedLibraryFolder] = []
        var didRefreshBookmark = false

        for index in refreshedRecords.indices {
            var record = refreshedRecords[index]
            var isStale = false
            let resolvedURL = try? URL(
                resolvingBookmarkData: record.bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            let availableURL = resolvedURL.flatMap { url in
                fileManager.fileExists(atPath: url.path) ? url : nil
            }

            if let availableURL {
                if activeSecurityScopedURLs[record.id] == nil {
                    _ = availableURL.startAccessingSecurityScopedResource()
                    activeSecurityScopedURLs[record.id] = availableURL
                }
                if isStale,
                   let refreshedBookmark = try? availableURL.bookmarkData(
                       options: [.withSecurityScope],
                       includingResourceValuesForKeys: nil,
                       relativeTo: nil
                   ) {
                    record.bookmark = refreshedBookmark
                    refreshedRecords[index] = record
                    didRefreshBookmark = true
                }
            } else if let oldURL = activeSecurityScopedURLs.removeValue(forKey: record.id) {
                oldURL.stopAccessingSecurityScopedResource()
            }

            resolvedFolders.append(
                LinkedLibraryFolder(
                    id: record.id,
                    name: record.name,
                    originalPath: record.originalPath,
                    volumeIdentifier: record.volumeIdentifier,
                    volumeName: record.volumeName,
                    isExternal: record.isExternal,
                    addedAt: record.addedAt,
                    resolvedURL: availableURL
                )
            )
        }

        folderRecords = refreshedRecords
        linkedFolders = resolvedFolders
        refreshExternalVolumeStatuses()

        if saveAfterRefresh || didRefreshBookmark {
            save()
        }
    }

    private func observeWorkspaceVolumes() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification
        ]

        workspaceObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshLocations(saveAfterRefresh: true)
                }
            }
        }
    }

    private func refreshExternalVolumeStatuses() {
        let mountedVolumes = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: [
                .volumeNameKey,
                .volumeUUIDStringKey,
                .volumeURLKey,
                .volumeIsRemovableKey,
                .volumeIsEjectableKey
            ],
            options: [.skipHiddenVolumes]
        ) ?? []
        let mountedDetails = mountedVolumes.compactMap(volumeDetails(for:))
        let now = Date()

        for index in rememberedExternalVolumes.indices {
            let id = rememberedExternalVolumes[index].id
            if let mounted = mountedDetails.first(where: { $0.identifier == id }) {
                rememberedExternalVolumes[index].name = mounted.name
                rememberedExternalVolumes[index].lastKnownMountPath = mounted.mountPath
                rememberedExternalVolumes[index].lastSeenAt = now
                rememberedExternalVolumes[index].isConnected = true
            } else {
                rememberedExternalVolumes[index].isConnected = false
            }
        }
    }

    private func volumeDetails(for url: URL) -> VolumeDetails? {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeUUIDStringKey,
            .volumeURLKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let volumeURL = values.volume else { return nil }

        let name = values.volumeName ?? volumeURL.lastPathComponent
        let isExternal = LibraryVolumeClassification.isExternal(
            isRemovable: values.volumeIsRemovable == true,
            isEjectable: values.volumeIsEjectable == true,
            mountPath: volumeURL.path
        )
        let identifier = values.volumeUUIDString
            .map { "uuid:\($0)" }
            ?? "path:\(volumeURL.standardizedFileURL.path)"

        return VolumeDetails(
            identifier: identifier,
            name: name.isEmpty ? "External Drive" : name,
            mountPath: volumeURL.path,
            isExternal: isExternal
        )
    }

    private func save() {
        do {
            let state = PersistedLibrary(
                folders: folderRecords,
                externalVolumes: rememberedExternalVolumes
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(state).write(to: persistenceURL, options: .atomic)
        } catch {
            print("Unable to save library locations: \(error)")
        }
    }

    private func load() {
        guard fileManager.fileExists(atPath: persistenceURL.path) else { return }
        do {
            let state = try JSONDecoder().decode(
                PersistedLibrary.self,
                from: Data(contentsOf: persistenceURL)
            )
            folderRecords = state.folders
            rememberedExternalVolumes = state.externalVolumes
        } catch {
            print("Unable to load library locations: \(error)")
        }
    }
}
