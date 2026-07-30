//
//  ArchiveFolderStore.swift
//  Microfiche
//
//  Persists a security-scoped bookmark for the user-defined archive folder.
//

import AppKit
import Combine
import Foundation

@MainActor
final class ArchiveFolderStore: ObservableObject {
    static let shared = ArchiveFolderStore()

    enum Keys {
        static let bookmark = "archiveFolderBookmark"
        static let displayName = "archiveFolderDisplayName"
    }

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private var activeSecurityScopedURL: URL?

    @Published private(set) var displayName: String?
    @Published private(set) var isAvailable: Bool = false

    var hasConfiguredFolder: Bool {
        defaults.data(forKey: Keys.bookmark) != nil
    }

    init(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.fileManager = fileManager
        refresh()
    }

    deinit {
        activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
    }

    /// Presents an open panel and stores the chosen folder bookmark.
    @discardableResult
    func chooseFolder() -> Bool {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.prompt = "Choose Archive Folder"
        openPanel.message = "Images moved to Archive are stored in this folder."

        guard openPanel.runModal() == .OK, let url = openPanel.url else {
            return false
        }
        return setFolder(url)
    }

    @discardableResult
    func setFolder(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL.resolvingSymlinksInPath()
        do {
            let bookmark = try standardized.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(bookmark, forKey: Keys.bookmark)
            defaults.set(standardized.lastPathComponent, forKey: Keys.displayName)
            refresh()
            return isAvailable
        } catch {
            print("Unable to remember archive folder \(standardized.path): \(error)")
            return false
        }
    }

    func clearFolder() {
        activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
        activeSecurityScopedURL = nil
        defaults.removeObject(forKey: Keys.bookmark)
        defaults.removeObject(forKey: Keys.displayName)
        displayName = nil
        isAvailable = false
    }

    /// Resolves the archive folder, refreshing a stale bookmark when needed.
    func resolvedURL() -> URL? {
        refresh()
        return activeSecurityScopedURL
    }

    func refresh() {
        guard let bookmark = defaults.data(forKey: Keys.bookmark) else {
            activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
            activeSecurityScopedURL = nil
            displayName = nil
            isAvailable = false
            return
        }

        var isStale = false
        let resolved = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        guard let resolved,
              fileManager.fileExists(atPath: resolved.path) else {
            activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
            activeSecurityScopedURL = nil
            displayName = defaults.string(forKey: Keys.displayName)
            isAvailable = false
            return
        }

        if activeSecurityScopedURL != resolved {
            activeSecurityScopedURL?.stopAccessingSecurityScopedResource()
            _ = resolved.startAccessingSecurityScopedResource()
            activeSecurityScopedURL = resolved
        }

        if isStale,
           let refreshed = try? resolved.bookmarkData(
               options: [.withSecurityScope],
               includingResourceValuesForKeys: nil,
               relativeTo: nil
           ) {
            defaults.set(refreshed, forKey: Keys.bookmark)
        }

        displayName = resolved.lastPathComponent
        defaults.set(displayName, forKey: Keys.displayName)
        isAvailable = true
    }
}
