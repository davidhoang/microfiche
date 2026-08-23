//
//  BatchMetadataEditing.swift
//  Microfiche
//
//  Shared/mixed/empty inspector state and per-file metadata writes
//  across a multi-image selection.
//

import Foundation

struct ResolvedImageMetadata: Equatable, Sendable {
    var label: FinderLabel
    var tags: [String]
    var comments: String
    var whereFrom: String
}

enum BatchFieldValue<Value: Equatable>: Equatable {
    case empty
    case shared(Value)
    case mixed
}

struct BatchMetadataSummary: Equatable {
    var fileCount: Int
    var label: BatchFieldValue<FinderLabel>
    var sharedTags: [String]
    var mixedTags: [String]
    var comments: BatchFieldValue<String>
    var whereFrom: BatchFieldValue<String>
}

enum BatchMetadataOperation: Equatable {
    case setLabel(FinderLabel)
    case addTag(String)
    case removeTag(String)
    case replaceComments(String)
    case replaceWhereFrom(String)
}

struct BatchMetadataFailure: Equatable {
    var path: String
    var message: String
}

struct BatchMetadataWriteResult: Equatable {
    var succeededPaths: [String]
    var skippedMissingPaths: [String]
    var failures: [BatchMetadataFailure]
    var wasCancelled: Bool

    var errorMessage: String? {
        if failures.isEmpty {
            return wasCancelled && succeededPaths.isEmpty
                ? "Update cancelled."
                : nil
        }

        let details = failures
            .map { "\(URL(fileURLWithPath: $0.path).lastPathComponent): \($0.message)" }
            .joined(separator: "\n")

        if failures.count == 1, skippedMissingPaths.isEmpty, !wasCancelled {
            let name = URL(fileURLWithPath: failures[0].path).lastPathComponent
            return "Couldn’t update \(name): \(failures[0].message)"
        }

        var prefix = "Updated \(succeededPaths.count)"
        if !failures.isEmpty {
            prefix += ", failed \(failures.count)"
        }
        if wasCancelled {
            prefix += ", cancelled"
        }
        return "\(prefix).\n\(details)"
    }
}

enum BatchMetadataAggregation {
    static func resolved(
        native: NativeFileMetadata,
        local: ImageMetadata
    ) -> ResolvedImageMetadata {
        var label = native.label
        if label == .none, let migrated = FinderLabel.migrating(from: local.labels) {
            label = migrated
        }

        return ResolvedImageMetadata(
            label: label,
            tags: native.tagNames.isEmpty ? local.tags : native.tagNames,
            comments: native.comment.isEmpty ? local.comments : native.comment,
            whereFrom: local.whereFrom
        )
    }

    static func summarize(_ items: [ResolvedImageMetadata]) -> BatchMetadataSummary {
        guard !items.isEmpty else {
            return BatchMetadataSummary(
                fileCount: 0,
                label: .empty,
                sharedTags: [],
                mixedTags: [],
                comments: .empty,
                whereFrom: .empty
            )
        }

        let labels = items.map(\.label)
        let comments = items.map {
            $0.comments.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let sources = items.map {
            $0.whereFrom.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let tagSets = items.map { Set($0.tags) }
        let sharedTags = tagSets.reduce(into: tagSets[0]) { $0.formIntersection($1) }
        let unionTags = tagSets.reduce(into: Set<String>()) { $0.formUnion($1) }
        let mixedTags = unionTags.subtracting(sharedTags)

        return BatchMetadataSummary(
            fileCount: items.count,
            label: reduce(labels, isEmpty: { $0 == .none }),
            sharedTags: sharedTags.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            mixedTags: mixedTags.sorted { $0.localizedStandardCompare($1) == .orderedAscending },
            comments: reduce(comments, isEmpty: { $0.isEmpty }),
            whereFrom: reduce(sources, isEmpty: { $0.isEmpty })
        )
    }

    private static func reduce<Value: Equatable>(
        _ values: [Value],
        isEmpty: (Value) -> Bool
    ) -> BatchFieldValue<Value> {
        guard let first = values.first else { return .empty }
        guard values.allSatisfy({ $0 == first }) else { return .mixed }
        return isEmpty(first) ? .empty : .shared(first)
    }
}

@MainActor
struct BatchMetadataWriter {
    var loadResolved: (URL) -> ResolvedImageMetadata
    var save: (ResolvedImageMetadata, URL) throws -> Void
    var fileExists: (URL) -> Bool
    var beforeSave: ((URL) -> Void)? = nil
    var isCancelled: () -> Bool = { Task.isCancelled }

    static func live(store: ImageMetadataStore = .shared) -> BatchMetadataWriter {
        BatchMetadataWriter(
            loadResolved: { url in
                BatchMetadataAggregation.resolved(
                    native: NativeFileMetadataService.load(from: url),
                    local: store.metadata(for: url)
                )
            },
            save: { resolved, url in
                try NativeFileMetadataService.save(
                    NativeFileMetadata(
                        label: resolved.label,
                        tagNames: resolved.tags,
                        comment: resolved.comments
                    ),
                    for: url
                )
                store.save(
                    ImageMetadata(
                        tags: resolved.tags,
                        labels: [],
                        comments: resolved.comments,
                        whereFrom: resolved.whereFrom
                    ),
                    for: url
                )
            },
            fileExists: { FileManager.default.fileExists(atPath: $0.path) }
        )
    }

    func apply(
        _ operation: BatchMetadataOperation,
        to urls: [URL]
    ) async -> BatchMetadataWriteResult {
        var result = BatchMetadataWriteResult(
            succeededPaths: [],
            skippedMissingPaths: [],
            failures: [],
            wasCancelled: false
        )

        for url in urls {
            if isCancelled() {
                result.wasCancelled = true
                break
            }

            let path = ImageIdentity.normalizedPath(for: url)
            guard fileExists(url) else {
                result.skippedMissingPaths.append(path)
                continue
            }

            var resolved = loadResolved(url)
            apply(operation, to: &resolved)
            beforeSave?(url)

            if isCancelled() {
                result.wasCancelled = true
                break
            }

            do {
                try save(resolved, url)
                result.succeededPaths.append(path)
            } catch {
                result.failures.append(
                    BatchMetadataFailure(path: path, message: error.localizedDescription)
                )
            }
        }

        if isCancelled() {
            result.wasCancelled = true
        }

        return result
    }

    private func apply(
        _ operation: BatchMetadataOperation,
        to resolved: inout ResolvedImageMetadata
    ) {
        switch operation {
        case .setLabel(let label):
            resolved.label = label
        case .addTag(let tag):
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !resolved.tags.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
            else { return }
            resolved.tags.append(trimmed)
        case .removeTag(let tag):
            resolved.tags.removeAll {
                $0.caseInsensitiveCompare(tag) == .orderedSame
            }
        case .replaceComments(let comments):
            resolved.comments = comments.trimmingCharacters(in: .whitespacesAndNewlines)
        case .replaceWhereFrom(let whereFrom):
            resolved.whereFrom = whereFrom.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
