//
//  NativeFileMetadataService.swift
//  Microfiche
//
//  Read/write Finder-native file metadata (color labels, tags, comments).
//

import Foundation

struct NativeFileMetadata: Equatable, Sendable {
    var label: FinderLabel
    var tagNames: [String]
    var comment: String

    static let empty = NativeFileMetadata(label: .none, tagNames: [], comment: "")
}

enum NativeFileMetadataService {
    private static let finderCommentAttribute = "com.apple.metadata:kMDItemFinderComment"
    private static let finderInfoAttribute = "com.apple.FinderInfo"
    private static let finderTagsAttribute = "com.apple.metadata:_kMDItemUserTags"

    static func load(from url: URL) -> NativeFileMetadata {
        var label = FinderLabel.none
        var tagNames: [String] = []

        if let values = try? url.resourceValues(forKeys: [.labelNumberKey, .tagNamesKey]) {
            if let labelNumber = values.labelNumber {
                label = FinderLabel(labelNumber: labelNumber)
            } else if let finderLabel = readLabelFromFinderInfo(at: url) {
                label = finderLabel
            }
            tagNames = Self.normalizeList(values.tagNames ?? [])
        } else if let finderLabel = readLabelFromFinderInfo(at: url) {
            label = finderLabel
        }

        let comment = (try? readFinderComment(from: url)) ?? ""
        return NativeFileMetadata(label: label, tagNames: tagNames, comment: comment)
    }

    static func save(_ metadata: NativeFileMetadata, for url: URL) throws {
        try setLabel(metadata.label, for: url)
        try setTagNames(metadata.tagNames, for: url)
        try setComment(metadata.comment, for: url)
    }

    static func setLabel(_ label: FinderLabel, for url: URL) throws {
        try writeLabelToFinderInfo(label, at: url)
    }

    static func setTagNames(_ tagNames: [String], for url: URL) throws {
        let normalizedTagNames = normalizeList(tagNames)

        if #available(macOS 26.0, *) {
            var mutableURL = url
            var values = URLResourceValues()
            values.tagNames = normalizedTagNames
            try mutableURL.setResourceValues(values)
        } else if normalizedTagNames.isEmpty {
            try? url.removeExtendedAttribute(forName: finderTagsAttribute)
        } else {
            let data = try PropertyListSerialization.data(
                fromPropertyList: normalizedTagNames,
                format: .binary,
                options: 0
            )
            try url.setExtendedAttribute(data, forName: finderTagsAttribute)
        }
    }

    static func setComment(_ comment: String, for url: URL) throws {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? url.removeExtendedAttribute(forName: finderCommentAttribute)
            return
        }

        let data = try PropertyListSerialization.data(
            fromPropertyList: trimmed,
            format: .binary,
            options: 0
        )
        try url.setExtendedAttribute(data, forName: finderCommentAttribute)
    }

    // MARK: - Helpers

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

    private static func readFinderComment(from url: URL) throws -> String {
        let data = try url.extendedAttribute(forName: finderCommentAttribute)
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        if let string = object as? String {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let strings = object as? [String] {
            return strings.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    /// Fallback for volumes that reject `labelNumber` resource values.
    private static func readLabelFromFinderInfo(at url: URL) -> FinderLabel? {
        guard let data = try? url.extendedAttribute(forName: finderInfoAttribute),
              data.count >= 10 else {
            return nil
        }
        let flags = data[9]
        let labelBits = Int((flags >> 1) & 0x07)
        return FinderLabel(rawValue: labelBits)
    }

    private static func writeLabelToFinderInfo(_ label: FinderLabel, at url: URL) throws {
        var data = (try? url.extendedAttribute(forName: finderInfoAttribute)) ?? Data(count: 32)
        if data.count < 32 {
            data.append(contentsOf: [UInt8](repeating: 0, count: 32 - data.count))
        }

        var flags = data[9]
        flags = (flags & 0xF1) | (UInt8(label.rawValue << 1) & 0x0E)
        data[9] = flags
        try url.setExtendedAttribute(data, forName: finderInfoAttribute)
    }
}
