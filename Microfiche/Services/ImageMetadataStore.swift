//
//  ImageMetadataStore.swift
//  Microfiche
//
//  Local JSON persistence for tags, labels, comments, and source notes.
//  Metadata is stored in Application Support (not written into image files).
//

import Foundation

@MainActor
final class ImageMetadataStore {
    static let shared = ImageMetadataStore()

    private let fileManager: FileManager
    private let persistenceURL: URL
    private var records: [String: ImageMetadata] = [:]

    init(
        persistenceURL customPersistenceURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager

        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let libraryDirectory = applicationSupport.appendingPathComponent(
            "Microfiche",
            isDirectory: true
        )
        persistenceURL = customPersistenceURL
            ?? libraryDirectory.appendingPathComponent("image-metadata.json")

        try? fileManager.createDirectory(
            at: persistenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        load()
    }

    func metadata(for url: URL) -> ImageMetadata {
        let key = ImageIdentity.normalizedPath(for: url)
        if let stored = records[key] {
            return stored
        }

        // One-time migration from earlier Microfiche xattr attempts.
        if let migrated = migrateLegacyExtendedAttributes(from: url) {
            records[key] = migrated
            persist()
            return migrated
        }

        return .empty
    }

    func save(_ metadata: ImageMetadata, for url: URL) {
        var normalized = metadata
        normalized.normalized()

        let key = ImageIdentity.normalizedPath(for: url)
        if normalized.isEmpty {
            records.removeValue(forKey: key)
        } else {
            records[key] = normalized
        }
        persist()
    }

    func move(from oldURL: URL, to newURL: URL) {
        let oldKey = ImageIdentity.normalizedPath(for: oldURL)
        let newKey = ImageIdentity.normalizedPath(for: newURL)
        guard oldKey != newKey else { return }

        if let metadata = records.removeValue(forKey: oldKey) {
            records[newKey] = metadata
            persist()
        }
    }

    func remove(for url: URL) {
        let key = ImageIdentity.normalizedPath(for: url)
        guard records.removeValue(forKey: key) != nil else { return }
        persist()
    }

    func remove(for urls: [URL]) {
        var didChange = false
        for url in urls {
            let key = ImageIdentity.normalizedPath(for: url)
            if records.removeValue(forKey: key) != nil {
                didChange = true
            }
        }
        if didChange {
            persist()
        }
    }

    // MARK: - Persistence

    private func load() {
        guard fileManager.fileExists(atPath: persistenceURL.path) else {
            records = [:]
            return
        }

        do {
            let data = try Data(contentsOf: persistenceURL)
            records = try JSONDecoder().decode([String: ImageMetadata].self, from: data)
        } catch {
            print("Error loading image metadata: \(error)")
            records = [:]
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            print("Error saving image metadata: \(error)")
        }
    }

    // MARK: - Legacy Migration

    private func migrateLegacyExtendedAttributes(from url: URL) -> ImageMetadata? {
        var metadata = ImageMetadata.empty
        var found = false

        if let data = try? url.extendedAttribute(forName: "com.microfiche.tags"),
           let string = String(data: data, encoding: .utf8) {
            metadata.tags = string.components(separatedBy: ",").filter { !$0.isEmpty }
            found = true
        }
        if let data = try? url.extendedAttribute(forName: "com.microfiche.labels"),
           let string = String(data: data, encoding: .utf8) {
            metadata.labels = string.components(separatedBy: ",").filter { !$0.isEmpty }
            found = true
        }
        if let data = try? url.extendedAttribute(forName: "com.microfiche.comments"),
           let string = String(data: data, encoding: .utf8) {
            metadata.comments = string
            found = true
        }
        if let data = try? url.extendedAttribute(forName: "com.microfiche.whereFrom"),
           let string = String(data: data, encoding: .utf8) {
            metadata.whereFrom = string
            found = true
        }

        guard found else { return nil }
        metadata.normalized()
        return metadata.isEmpty ? nil : metadata
    }
}
