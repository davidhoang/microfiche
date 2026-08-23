//
//  LibraryFiltering.swift
//  Microfiche
//

import Foundation

enum LibraryFiltering {
    static func matches(
        file: ImageFile,
        metadata: ImageMetadata,
        query: String,
        fileType: String,
        tag: String
    ) -> Bool {
        if !fileType.isEmpty,
           file.url.pathExtension.lowercased() != fileType.lowercased() {
            return false
        }

        if !tag.isEmpty {
            let normalizedTag = tag.lowercased()
            let hasTag = metadata.tags.contains { $0.lowercased() == normalizedTag }
            if !hasTag { return false }
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return true }

        let normalizedQuery = trimmedQuery.lowercased()
        if file.name.localizedStandardContains(normalizedQuery) { return true }
        if file.url.path.localizedStandardContains(normalizedQuery) { return true }
        if metadata.comments.localizedStandardContains(normalizedQuery) { return true }
        if metadata.whereFrom.localizedStandardContains(normalizedQuery) { return true }
        if metadata.tags.contains(where: { $0.localizedStandardContains(normalizedQuery) }) {
            return true
        }
        if metadata.labels.contains(where: { $0.localizedStandardContains(normalizedQuery) }) {
            return true
        }

        return false
    }
}
