//
//  LibraryIndexStore.swift
//  Microfiche
//

import Combine
import Foundation

struct LibraryIndexEntry: Codable, Equatable, Sendable {
    let path: String
    let modificationDate: Date?
    let fileSize: Int?

    var imageFile: ImageFile {
        ImageFile(url: URL(fileURLWithPath: path))
    }
}

enum LibraryIndexScanner {
    static func scan(
        root: URL,
        fileManager: FileManager = .default
    ) -> [LibraryIndexEntry] {
        var entries: [LibraryIndexEntry] = []
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .contentModificationDateKey,
            .fileSizeKey
        ]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return entries
        }

        for case let fileURL as URL in enumerator {
            if let entry = entry(for: fileURL, fileManager: fileManager) {
                entries.append(entry)
            }
        }
        return entries
    }

    static func applying(
        changedPaths: Set<String>,
        to existing: [LibraryIndexEntry],
        under root: URL,
        fileManager: FileManager = .default
    ) -> [LibraryIndexEntry] {
        let rootPath = normalizedPath(root)
        var entriesByPath = Dictionary(
            uniqueKeysWithValues: existing.map { ($0.path, $0) }
        )

        for rawPath in changedPaths {
            let changedURL = URL(fileURLWithPath: rawPath)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            let changedPath = changedURL.path
            guard isWithin(changedPath, rootPath: rootPath) else { continue }

            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(
                atPath: changedPath,
                isDirectory: &isDirectory
            )

            if exists, isDirectory.boolValue {
                removeEntries(atOrBelow: changedPath, from: &entriesByPath)
                for entry in scan(root: changedURL, fileManager: fileManager) {
                    entriesByPath[entry.path] = entry
                }
            } else if exists,
                      let entry = entry(for: changedURL, fileManager: fileManager) {
                entriesByPath[entry.path] = entry
            } else {
                removeEntries(atOrBelow: changedPath, from: &entriesByPath)
            }
        }

        return Array(entriesByPath.values)
    }

    private static func entry(
        for url: URL,
        fileManager: FileManager
    ) -> LibraryIndexEntry? {
        guard SupportedImageExtensions.contains(url) else { return nil }
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentModificationDateKey,
            .fileSizeKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isRegularFile == true else {
            return nil
        }

        return LibraryIndexEntry(
            path: normalizedPath(url),
            modificationDate: values.contentModificationDate,
            fileSize: values.fileSize
        )
    }

    private static func removeEntries(
        atOrBelow path: String,
        from entriesByPath: inout [String: LibraryIndexEntry]
    ) {
        entriesByPath = entriesByPath.filter {
            $0.key != path && !$0.key.hasPrefix(path + "/")
        }
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func isWithin(_ path: String, rootPath: String) -> Bool {
        path == rootPath || path.hasPrefix(rootPath + "/")
    }
}

@MainActor
final class LibraryIndexStore: ObservableObject {
    static let shared = LibraryIndexStore()

    @Published private(set) var revision: UInt64 = 0

    private struct FolderSlice: Codable, Equatable {
        let folderID: UUID
        var entries: [LibraryIndexEntry]
        var lastScannedAt: Date?
    }

    private struct PersistedIndex: Codable {
        let version: Int
        var folders: [FolderSlice]
    }

    private let fileManager: FileManager
    private let persistenceURL: URL
    private let watcher: FolderWatchService?
    private var slices: [UUID: FolderSlice] = [:]
    private var availableRoots: [UUID: URL] = [:]
    private var reconcileGenerations: [UUID: UUID] = [:]
    private var mutationVersions: [UUID: UInt64] = [:]
    private var fileSystemChangeTasks: [UUID: Task<Void, Never>] = [:]
    private var fileSystemChangeGenerations: [UUID: UUID] = [:]

    init(
        persistenceURL customPersistenceURL: URL? = nil,
        fileManager: FileManager = .default,
        watchesFileSystem: Bool = true
    ) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let directory = applicationSupport.appendingPathComponent(
            "Microfiche",
            isDirectory: true
        )
        persistenceURL = customPersistenceURL
            ?? directory.appendingPathComponent("library-index.json")
        watcher = watchesFileSystem ? FolderWatchService() : nil

        try? fileManager.createDirectory(
            at: persistenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        load()

        watcher?.onChanges = { [weak self] changes in
            guard let self else { return }
            Task { @MainActor in
                self.enqueueFileSystemChanges(changes)
            }
        }
    }

    func configure(folders: [LinkedLibraryFolder]) {
        let folderIDs = Set(folders.map(\.id))
        let staleIDs = Set(slices.keys).subtracting(folderIDs)
        if !staleIDs.isEmpty {
            staleIDs.forEach {
                slices.removeValue(forKey: $0)
                reconcileGenerations.removeValue(forKey: $0)
                mutationVersions.removeValue(forKey: $0)
                fileSystemChangeGenerations.removeValue(forKey: $0)
                fileSystemChangeTasks.removeValue(forKey: $0)?.cancel()
            }
            persist()
            bumpRevision()
        }

        availableRoots = Dictionary(
            uniqueKeysWithValues: folders.compactMap { folder in
                folder.resolvedURL.map { (folder.id, $0) }
            }
        )
        watcher?.setWatchedRoots(
            availableRoots.map { (folderID: $0.key, url: $0.value) }
        )
    }

    func reconcileAll() async {
        for folderID in availableRoots.keys {
            await reconcile(folderID: folderID)
        }
    }

    func files(for folderIDs: [UUID]) -> [ImageFile] {
        var seenPaths = Set<String>()
        return folderIDs
            .flatMap { slices[$0]?.entries ?? [] }
            .filter { seenPaths.insert($0.path).inserted }
            .map(\.imageFile)
            .sorted {
                let result = $0.name.localizedStandardCompare($1.name)
                return result == .orderedSame
                    ? $0.url.path < $1.url.path
                    : result == .orderedAscending
            }
    }

    func reconcile(folderID: UUID) async {
        guard let root = availableRoots[folderID] else { return }
        let generation = UUID()
        let mutationVersion = mutationVersions[folderID, default: 0]
        reconcileGenerations[folderID] = generation

        let entries = await Task.detached(priority: .userInitiated) {
            LibraryIndexScanner.scan(root: root)
        }.value

        guard reconcileGenerations[folderID] == generation,
              mutationVersions[folderID, default: 0] == mutationVersion,
              availableRoots[folderID] == root else {
            return
        }
        apply(entries: entries, to: folderID, scannedAt: Date())
    }

    func remove(urls: [URL]) {
        let paths = Set(urls.map { ImageIdentity.normalizedPath(for: $0) })
        var didChange = false
        for folderID in Array(slices.keys) {
            let oldCount = slices[folderID]?.entries.count ?? 0
            slices[folderID]?.entries.removeAll { paths.contains($0.path) }
            if slices[folderID]?.entries.count != oldCount {
                invalidateInFlightReconcile(for: folderID)
                didChange = true
            }
        }
        if didChange {
            persist()
            bumpRevision()
        }
    }

    func move(from oldURL: URL, to newURL: URL) {
        let oldPath = ImageIdentity.normalizedPath(for: oldURL)
        var didChange = false
        for folderID in Array(slices.keys) {
            guard let existing = slices[folderID]?.entries,
                  existing.contains(where: { $0.path == oldPath }) else {
                continue
            }
            var updated = existing.filter { $0.path != oldPath }
            if let root = availableRoots[folderID] {
                updated = LibraryIndexScanner.applying(
                    changedPaths: [newURL.path],
                    to: updated,
                    under: root,
                    fileManager: fileManager
                )
            }
            slices[folderID]?.entries = updated
            invalidateInFlightReconcile(for: folderID)
            didChange = true
        }
        guard didChange else { return }
        persist()
        bumpRevision()
    }

    func removeFolder(id: UUID) {
        availableRoots.removeValue(forKey: id)
        reconcileGenerations.removeValue(forKey: id)
        mutationVersions.removeValue(forKey: id)
        fileSystemChangeGenerations.removeValue(forKey: id)
        fileSystemChangeTasks.removeValue(forKey: id)?.cancel()
        guard slices.removeValue(forKey: id) != nil else { return }
        persist()
        bumpRevision()
    }

    private func enqueueFileSystemChanges(_ changes: [FolderWatchService.Change]) {
        for change in changes {
            guard availableRoots[change.folderID] != nil else { continue }
            reconcileGenerations[change.folderID] = UUID()
            let previousTask = fileSystemChangeTasks[change.folderID]
            let taskGeneration = UUID()
            fileSystemChangeGenerations[change.folderID] = taskGeneration
            let task = Task { @MainActor [weak self] in
                _ = await previousTask?.value
                guard !Task.isCancelled else { return }
                await self?.applyFileSystemChange(change)
                guard self?.fileSystemChangeGenerations[change.folderID]
                    == taskGeneration else {
                    return
                }
                self?.fileSystemChangeTasks.removeValue(forKey: change.folderID)
                self?.fileSystemChangeGenerations.removeValue(forKey: change.folderID)
            }
            fileSystemChangeTasks[change.folderID] = task
        }
    }

    private func applyFileSystemChange(
        _ change: FolderWatchService.Change
    ) async {
        guard let root = availableRoots[change.folderID] else { return }
        if change.requiresFullScan
            || slices[change.folderID]?.lastScannedAt == nil {
            await reconcile(folderID: change.folderID)
            return
        }

        while !Task.isCancelled {
            let mutationVersion = mutationVersions[change.folderID, default: 0]
            let existing = slices[change.folderID]?.entries ?? []
            let entries = await Task.detached(priority: .utility) {
                LibraryIndexScanner.applying(
                    changedPaths: change.paths,
                    to: existing,
                    under: root
                )
            }.value
            guard availableRoots[change.folderID] == root else { return }
            guard mutationVersions[change.folderID, default: 0] == mutationVersion else {
                continue
            }
            apply(entries: entries, to: change.folderID, scannedAt: nil)
            mutationVersions[change.folderID, default: 0] &+= 1
            return
        }
    }

    private func invalidateInFlightReconcile(for folderID: UUID) {
        reconcileGenerations[folderID] = UUID()
        mutationVersions[folderID, default: 0] &+= 1
    }

    private func apply(
        entries: [LibraryIndexEntry],
        to folderID: UUID,
        scannedAt: Date?
    ) {
        let normalizedEntries = entries.sorted { $0.path < $1.path }
        let existing = slices[folderID]
        let next = FolderSlice(
            folderID: folderID,
            entries: normalizedEntries,
            lastScannedAt: scannedAt ?? existing?.lastScannedAt
        )
        guard next != existing else { return }
        slices[folderID] = next
        persist()
        bumpRevision()
    }

    private func bumpRevision() {
        revision &+= 1
    }

    private func persist() {
        do {
            let state = PersistedIndex(
                version: 1,
                folders: slices.values.sorted {
                    $0.folderID.uuidString < $1.folderID.uuidString
                }
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(state).write(to: persistenceURL, options: .atomic)
        } catch {
            print("Unable to save library index: \(error)")
        }
    }

    private func load() {
        guard fileManager.fileExists(atPath: persistenceURL.path) else { return }
        do {
            let data = try Data(contentsOf: persistenceURL)
            let state = try JSONDecoder().decode(PersistedIndex.self, from: data)
            guard state.version == 1 else { return }
            slices = Dictionary(
                uniqueKeysWithValues: state.folders.map { ($0.folderID, $0) }
            )
        } catch {
            print("Unable to load library index: \(error)")
            slices = [:]
        }
    }
}
