//
//  LibraryFiltering.swift
//  Microfiche
//

import Foundation

struct LibraryItemMetadata: Equatable, Sendable {
    var resolved: ResolvedImageMetadata
    var camera: String?
    var lens: String?
    var captured: String?
    var capturedDate: Date?
    var modificationDate: Date?

    init(
        resolved: ResolvedImageMetadata,
        technical: PhotoTechnicalMetadata? = nil,
        modificationDate: Date? = nil
    ) {
        self.resolved = resolved
        camera = technical?.camera
        lens = technical?.lens
        captured = technical?.captured
        capturedDate = technical?.captured.flatMap(LibraryCaptureDate.parse)
        self.modificationDate = modificationDate
    }
}

enum LibraryCaptureDate {
    static func parse(_ value: String) -> Date? {
        let parts = value.split(whereSeparator: { $0 == ":" || $0 == " " })
            .compactMap { Int($0) }
        if parts.count == 6 {
            var components = DateComponents()
            components.calendar = Calendar(identifier: .gregorian)
            components.timeZone = .current
            components.year = parts[0]
            components.month = parts[1]
            components.day = parts[2]
            components.hour = parts[3]
            components.minute = parts[4]
            components.second = parts[5]
            if let date = components.date {
                return date
            }
        }
        return ISO8601DateFormatter().date(from: value)
    }
}

enum LibrarySortOption: String, CaseIterable, Identifiable {
    case name
    case captureDate
    case finderLabel
    case dateModified

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .name: "Name"
        case .captureDate: "Capture Date"
        case .finderLabel: "Finder Label"
        case .dateModified: "Date Modified"
        }
    }
}

enum LibrarySortDirection: String, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: String { rawValue }
}

enum LibrarySorting {
    static func sorted(
        _ files: [ImageFile],
        by option: LibrarySortOption,
        direction: LibrarySortDirection,
        metadata: (ImageFile) -> LibraryItemMetadata
    ) -> [ImageFile] {
        files.sorted { lhs, rhs in
            let lhsMetadata = metadata(lhs)
            let rhsMetadata = metadata(rhs)
            let lhsMissing = isMissing(lhsMetadata, for: option)
            let rhsMissing = isMissing(rhsMetadata, for: option)
            if lhsMissing != rhsMissing {
                return !lhsMissing
            }
            let result = compare(
                lhs: lhs,
                lhsMetadata: lhsMetadata,
                rhs: rhs,
                rhsMetadata: rhsMetadata,
                option: option
            )
            if result == .orderedSame {
                return stableCompare(lhs, rhs) == .orderedAscending
            }
            return direction == .ascending
                ? result == .orderedAscending
                : result == .orderedDescending
        }
    }

    private static func isMissing(
        _ metadata: LibraryItemMetadata,
        for option: LibrarySortOption
    ) -> Bool {
        switch option {
        case .name:
            false
        case .captureDate:
            metadata.capturedDate == nil
        case .finderLabel:
            metadata.resolved.label == .none
        case .dateModified:
            metadata.modificationDate == nil
        }
    }

    private static func compare(
        lhs: ImageFile,
        lhsMetadata: LibraryItemMetadata,
        rhs: ImageFile,
        rhsMetadata: LibraryItemMetadata,
        option: LibrarySortOption
    ) -> ComparisonResult {
        switch option {
        case .name:
            return stableCompare(lhs, rhs)
        case .captureDate:
            return compareOptional(lhsMetadata.capturedDate, rhsMetadata.capturedDate)
        case .finderLabel:
            return compareOptional(
                lhsMetadata.resolved.label == .none
                    ? nil
                    : lhsMetadata.resolved.label.displayName,
                rhsMetadata.resolved.label == .none
                    ? nil
                    : rhsMetadata.resolved.label.displayName
            )
        case .dateModified:
            return compareOptional(
                lhsMetadata.modificationDate,
                rhsMetadata.modificationDate
            )
        }
    }

    private static func stableCompare(
        _ lhs: ImageFile,
        _ rhs: ImageFile
    ) -> ComparisonResult {
        let nameResult = lhs.name.localizedStandardCompare(rhs.name)
        if nameResult != .orderedSame { return nameResult }
        return lhs.url.path.compare(rhs.url.path)
    }

    private static func compareOptional<Value: Comparable>(
        _ lhs: Value?,
        _ rhs: Value?
    ) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            if lhs == rhs { return .orderedSame }
            return lhs < rhs ? .orderedAscending : .orderedDescending
        case (.some, .none):
            return .orderedAscending
        case (.none, .some):
            return .orderedDescending
        case (.none, .none):
            return .orderedSame
        }
    }
}

enum LibraryFiltering {
    static func matches(
        file: ImageFile,
        metadata: ResolvedImageMetadata,
        query: String,
        fileType: String,
        tag: String,
        label: FinderLabel
    ) -> Bool {
        matches(
            file: file,
            metadata: LibraryItemMetadata(resolved: metadata),
            query: query,
            fileType: fileType,
            tag: tag,
            label: label
        )
    }

    static func matches(
        file: ImageFile,
        metadata: LibraryItemMetadata,
        query: String,
        fileType: String,
        tag: String,
        label: FinderLabel
    ) -> Bool {
        let resolved = metadata.resolved
        if !fileType.isEmpty,
           file.url.pathExtension.lowercased() != fileType.lowercased() {
            return false
        }

        if !tag.isEmpty {
            let normalizedTag = tag.lowercased()
            let hasTag = resolved.tags.contains { $0.lowercased() == normalizedTag }
            if !hasTag { return false }
        }

        if label != .none, resolved.label != label {
            return false
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return true }

        let normalizedQuery = trimmedQuery.lowercased()
        if file.name.localizedStandardContains(normalizedQuery) { return true }
        if file.url.path.localizedStandardContains(normalizedQuery) { return true }
        if resolved.comments.localizedStandardContains(normalizedQuery) { return true }
        if resolved.whereFrom.localizedStandardContains(normalizedQuery) { return true }
        if resolved.tags.contains(where: { $0.localizedStandardContains(normalizedQuery) }) {
            return true
        }
        if resolved.label != .none,
           resolved.label.displayName.localizedStandardContains(normalizedQuery) {
            return true
        }
        if metadata.camera?.localizedStandardContains(normalizedQuery) == true { return true }
        if metadata.lens?.localizedStandardContains(normalizedQuery) == true { return true }
        if metadata.captured?.localizedStandardContains(normalizedQuery) == true { return true }

        return false
    }
}
