import Foundation

struct LibrarySearchQuery: Hashable, Sendable {
    var text = ""
    var fileType = ""
    var tag = ""
    var label = FinderLabel.none
    var sortOption = LibrarySortOption.name
    var sortDirection = LibrarySortDirection.ascending

    var requiresMetadata: Bool {
        !text.isEmpty || !tag.isEmpty || label != .none || sortOption != .name
    }
}

enum LibrarySearch {
    /// Pure query evaluation. Cancellation is checked while filtering and before
    /// publishing, so superseded queries never replace the current results.
    static func results(
        in files: [ImageFile],
        metadata: [UUID: LibraryItemMetadata],
        query: LibrarySearchQuery,
        isCancelled: () -> Bool = { Task.isCancelled }
    ) -> [ImageFile]? {
        let empty = LibraryItemMetadata(resolved: .init(
            label: .none, tags: [], comments: "", whereFrom: ""
        ))
        var matches: [ImageFile] = []
        for file in files {
            guard !isCancelled() else { return nil }
            if LibraryFiltering.matches(
                file: file,
                metadata: metadata[file.id] ?? empty,
                query: query.text,
                fileType: query.fileType,
                tag: query.tag,
                label: query.label
            ) {
                matches.append(file)
            }
        }
        let sorted = LibrarySorting.sorted(
            matches, by: query.sortOption, direction: query.sortDirection
        ) { metadata[$0.id] ?? empty }
        return isCancelled() ? nil : sorted
    }

    static func evaluate(
        files: [ImageFile],
        metadata: [UUID: LibraryItemMetadata],
        query: LibrarySearchQuery
    ) async -> [ImageFile]? {
        // Coalesce typing, while clear/filter/sort actions can run immediately.
        if !query.text.isEmpty {
            do { try await Task.sleep(for: .milliseconds(120)) }
            catch { return nil }
        }
        guard !Task.isCancelled else { return nil }
        let task = Task.detached(priority: .userInitiated) {
            results(in: files, metadata: metadata, query: query)
        }
        return await withTaskCancellationHandler {
            let result = await task.value
            return Task.isCancelled ? nil : result
        } onCancel: {
            task.cancel()
        }
    }
}
