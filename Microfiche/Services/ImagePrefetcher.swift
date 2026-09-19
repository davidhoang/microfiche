//
//  ImagePrefetcher.swift
//  Microfiche
//
//  Created by David Hoang on 2/7/26.
//

import Combine
import Foundation

enum ImagePrefetchDirection: Equatable {
    case backward
    case stationary
    case forward
}

enum ImagePrefetchMemoryPressure: Equatable {
    case normal
    case constrained
    case critical
}

struct ImagePrefetchPlan: Equatable {
    let direction: ImagePrefetchDirection
    let thumbnailIndices: [Int]
    let previewIndices: [Int]
}

enum ImagePrefetchPolicy {
    static func plan(
        visibleRange: ClosedRange<Int>,
        previousVisibleRange: ClosedRange<Int>?,
        itemCount: Int,
        memoryPressure: ImagePrefetchMemoryPressure
    ) -> ImagePrefetchPlan {
        guard itemCount > 0 else {
            return ImagePrefetchPlan(
                direction: .stationary,
                thumbnailIndices: [],
                previewIndices: []
            )
        }

        let lowerBound = min(itemCount - 1, max(0, visibleRange.lowerBound))
        let upperBound = max(lowerBound, min(itemCount - 1, visibleRange.upperBound))
        let visible = lowerBound...upperBound
        let direction = direction(from: previousVisibleRange, to: visible)
        let limits = limits(for: memoryPressure)
        let anchor: Int
        switch direction {
        case .backward:
            anchor = visible.lowerBound
        case .forward:
            anchor = visible.upperBound
        case .stationary:
            anchor = (visible.lowerBound + visible.upperBound) / 2
        }

        return ImagePrefetchPlan(
            direction: direction,
            thumbnailIndices: orderedIndices(
                around: visible,
                anchor: anchor,
                itemCount: itemCount,
                direction: direction,
                ahead: limits.thumbnailAhead,
                behind: limits.thumbnailBehind,
                includeVisible: false
            ),
            previewIndices: orderedIndices(
                around: visible,
                anchor: anchor,
                itemCount: itemCount,
                direction: direction,
                ahead: limits.previewAhead,
                behind: limits.previewBehind,
                includeVisible: memoryPressure != .critical
            )
        )
    }

    private static func direction(
        from previous: ClosedRange<Int>?,
        to current: ClosedRange<Int>
    ) -> ImagePrefetchDirection {
        guard let previous else { return .stationary }
        let previousMidpoint = previous.lowerBound + previous.upperBound
        let currentMidpoint = current.lowerBound + current.upperBound
        if currentMidpoint > previousMidpoint {
            return .forward
        }
        if currentMidpoint < previousMidpoint {
            return .backward
        }
        return .stationary
    }

    private static func limits(
        for pressure: ImagePrefetchMemoryPressure
    ) -> (
        thumbnailAhead: Int,
        thumbnailBehind: Int,
        previewAhead: Int,
        previewBehind: Int
    ) {
        switch pressure {
        case .normal:
            return (18, 6, 4, 1)
        case .constrained:
            return (8, 3, 1, 0)
        case .critical:
            return (2, 0, 0, 0)
        }
    }

    private static func orderedIndices(
        around visible: ClosedRange<Int>,
        anchor: Int,
        itemCount: Int,
        direction: ImagePrefetchDirection,
        ahead: Int,
        behind: Int,
        includeVisible: Bool
    ) -> [Int] {
        guard itemCount > 0 else { return [] }

        let forwardCount = direction == .backward ? behind : ahead
        let backwardCount = direction == .backward ? ahead : behind
        let forwardStart = visible.upperBound + 1
        let forwardEnd = min(itemCount - 1, visible.upperBound + forwardCount)
        let forward = forwardStart <= forwardEnd
            ? Array(forwardStart...forwardEnd)
            : []
        let backward = Array(
            (max(0, visible.lowerBound - backwardCount)..<visible.lowerBound).reversed()
        )
        let visiblePriority = includeVisible ? [anchor] : []

        switch direction {
        case .backward:
            return visiblePriority + backward + forward
        case .forward:
            return visiblePriority + forward + backward
        case .stationary:
            return visiblePriority + interleaved(forward, backward)
        }
    }

    private static func interleaved(_ first: [Int], _ second: [Int]) -> [Int] {
        var result: [Int] = []
        for index in 0..<max(first.count, second.count) {
            if first.indices.contains(index) {
                result.append(first[index])
            }
            if second.indices.contains(index) {
                result.append(second[index])
            }
        }
        return result
    }
}

struct ImagePrefetchRequestSet {
    struct Change: Equatable {
        let cancelled: Set<String>
        let added: Set<String>
    }

    private(set) var identifiers: Set<String> = []

    mutating func replace(with replacement: Set<String>) -> Change {
        let change = Change(
            cancelled: identifiers.subtracting(replacement),
            added: replacement.subtracting(identifiers)
        )
        identifiers = replacement
        return change
    }
}

@MainActor
final class ViewportImagePrefetcher: ObservableObject {
    typealias ThumbnailLoader = (URL, CGFloat) -> Void
    typealias PreviewLoader = (URL) -> Void

    private struct ScheduledRequest {
        let token: CancellationToken
        let item: DispatchWorkItem
    }

    private final class CancellationToken: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
    }

    private let queue = DispatchQueue(
        label: "com.microfiche.viewport-prefetch",
        qos: .utility
    )
    private let thumbnailLoader: ThumbnailLoader
    private let previewLoader: PreviewLoader
    private var visibleIndices: Set<Int> = []
    private var previousVisibleRange: ClosedRange<Int>?
    private var requestSet = ImagePrefetchRequestSet()
    private var scheduled: [String: ScheduledRequest] = [:]
    private var memoryPressure: ImagePrefetchMemoryPressure = .normal
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var currentImageFiles: [ImageFile] = []
    private var currentThumbnailSize: CGFloat = 0

    init(
        thumbnailLoader: @escaping ThumbnailLoader = {
            ImageCache.shared.prefetchImage(for: $0, size: $1)
        },
        previewLoader: @escaping PreviewLoader = {
            PreviewImageCache.shared.preloadImage(for: $0, priority: .utility)
        },
        observesMemoryPressure: Bool = true
    ) {
        self.thumbnailLoader = thumbnailLoader
        self.previewLoader = previewLoader

        if observesMemoryPressure {
            let source = DispatchSource.makeMemoryPressureSource(
                eventMask: [.normal, .warning, .critical],
                queue: .main
            )
            source.setEventHandler { [weak self, weak source] in
                guard let self, let source else { return }
                self.handleMemoryPressure(source.data)
            }
            source.resume()
            memoryPressureSource = source
        }
    }

    deinit {
        memoryPressureSource?.cancel()
        scheduled.values.forEach {
            $0.token.cancel()
            $0.item.cancel()
        }
    }

    func itemDidAppear(
        at index: Int,
        in imageFiles: [ImageFile],
        thumbnailSize: CGFloat
    ) {
        visibleIndices.insert(index)
        update(imageFiles: imageFiles, thumbnailSize: thumbnailSize)
    }

    func itemDidDisappear(
        at index: Int,
        in imageFiles: [ImageFile],
        thumbnailSize: CGFloat
    ) {
        visibleIndices.remove(index)
        update(imageFiles: imageFiles, thumbnailSize: thumbnailSize)
    }

    func prioritize(
        id: UUID?,
        in imageFiles: [ImageFile],
        thumbnailSize: CGFloat
    ) {
        guard let id, let index = imageFiles.firstIndex(where: { $0.id == id }) else {
            return
        }
        let savedVisibleIndices = visibleIndices
        visibleIndices.insert(index)
        update(imageFiles: imageFiles, thumbnailSize: thumbnailSize)
        visibleIndices = savedVisibleIndices
    }

    func cancel() {
        visibleIndices.removeAll()
        previousVisibleRange = nil
        currentImageFiles = []
        apply(requests: [])
    }

    func refresh(imageFiles: [ImageFile], thumbnailSize: CGFloat) {
        update(imageFiles: imageFiles, thumbnailSize: thumbnailSize)
    }

    func setMemoryPressureForTesting(
        _ pressure: ImagePrefetchMemoryPressure,
        imageFiles: [ImageFile],
        thumbnailSize: CGFloat
    ) {
        memoryPressure = pressure
        update(imageFiles: imageFiles, thumbnailSize: thumbnailSize)
    }

    private func update(imageFiles: [ImageFile], thumbnailSize: CGFloat) {
        currentImageFiles = imageFiles
        currentThumbnailSize = thumbnailSize
        let validIndices = visibleIndices.filter(imageFiles.indices.contains)
        guard let first = validIndices.min(), let last = validIndices.max() else {
            apply(requests: [])
            return
        }

        let visibleRange = first...last
        let plan = ImagePrefetchPolicy.plan(
            visibleRange: visibleRange,
            previousVisibleRange: previousVisibleRange,
            itemCount: imageFiles.count,
            memoryPressure: memoryPressure
        )
        previousVisibleRange = visibleRange

        let thumbnailLoader = thumbnailLoader
        let previewLoader = previewLoader
        var requests: [(identifier: String, load: () -> Void)] = []
        for index in plan.thumbnailIndices {
            let file = imageFiles[index]
            requests.append((
                "thumbnail:\(file.id):\(thumbnailSize)",
                { thumbnailLoader(file.url, thumbnailSize) }
            ))
        }
        for index in plan.previewIndices {
            let file = imageFiles[index]
            let fileExtension = file.url.pathExtension.lowercased()
            guard fileExtension != "pdf", fileExtension != "svg" else { continue }
            requests.append((
                "preview:\(file.id)",
                { previewLoader(file.url) }
            ))
        }
        apply(requests: requests)
    }

    private func apply(requests: [(identifier: String, load: () -> Void)]) {
        let change = requestSet.replace(with: Set(requests.map(\.identifier)))
        for identifier in change.cancelled {
            scheduled[identifier]?.token.cancel()
            scheduled[identifier]?.item.cancel()
            scheduled.removeValue(forKey: identifier)
        }

        let addedRequests = requests.filter { change.added.contains($0.identifier) }
        for (offset, request) in addedRequests.enumerated() {
            let token = CancellationToken()
            let item = DispatchWorkItem {
                guard !token.isCancelled else { return }
                request.load()
            }
            scheduled[request.identifier] = ScheduledRequest(token: token, item: item)
            queue.asyncAfter(
                deadline: .now() + (.milliseconds(offset * 8)),
                execute: item
            )
        }
    }

    private func handleMemoryPressure(
        _ data: DispatchSource.MemoryPressureEvent
    ) {
        if data.contains(.critical) {
            memoryPressure = .critical
        } else if data.contains(.warning) {
            memoryPressure = .constrained
        } else {
            memoryPressure = .normal
        }
        update(
            imageFiles: currentImageFiles,
            thumbnailSize: currentThumbnailSize
        )
    }
}
