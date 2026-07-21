//
//  ImageMetadata.swift
//  Microfiche
//
//  Locally stored organization metadata for a library image.
//

import Foundation

struct ImageMetadata: Codable, Equatable, Sendable {
    var tags: [String]
    var labels: [String]
    var comments: String
    var whereFrom: String

    static let empty = ImageMetadata(
        tags: [],
        labels: [],
        comments: "",
        whereFrom: ""
    )

    var isEmpty: Bool {
        tags.isEmpty
            && labels.isEmpty
            && comments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && whereFrom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    mutating func normalized() {
        tags = Self.normalizeList(tags)
        labels = Self.normalizeList(labels)
        comments = comments.trimmingCharacters(in: .whitespacesAndNewlines)
        whereFrom = whereFrom.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeList(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            result.append(trimmed)
        }
        return result
    }
}
