//
//  FolderWatchService.swift
//  Microfiche
//

import CoreServices
import Foundation

/// Watches linked library roots recursively and coalesces filesystem changes.
final class FolderWatchService {
    struct Change: Equatable, Sendable {
        let folderID: UUID
        let paths: Set<String>
        let requiresFullScan: Bool
    }

    var onChanges: (([Change]) -> Void)?

    private struct Root {
        let folderID: UUID
        let path: String
    }

    private struct PendingChange {
        var paths: Set<String> = []
        var requiresFullScan = false
    }

    private let queue = DispatchQueue(label: "com.microfiche.library-watcher")
    private var roots: [Root] = []
    private var stream: FSEventStreamRef?
    private var pendingChanges: [UUID: PendingChange] = [:]
    private var deliveryWorkItem: DispatchWorkItem?

    deinit {
        stop()
    }

    func setWatchedRoots(_ watchedRoots: [(folderID: UUID, url: URL)]) {
        let roots = watchedRoots.map {
            Root(
                folderID: $0.folderID,
                path: $0.url.standardizedFileURL.resolvingSymlinksInPath().path
            )
        }

        queue.async { [weak self] in
            self?.replaceRoots(with: roots)
        }
    }

    func stop() {
        queue.sync {
            stopStream()
            deliveryWorkItem?.cancel()
            deliveryWorkItem = nil
            pendingChanges.removeAll()
        }
    }

    private func replaceRoots(with roots: [Root]) {
        stopStream()
        deliveryWorkItem?.cancel()
        deliveryWorkItem = nil
        self.roots = roots
        pendingChanges.removeAll()

        guard !roots.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = roots.map(\.path) as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagNoDefer
        )

        guard let stream = FSEventStreamCreate(
            nil,
            { _, contextInfo, eventCount, eventPaths, eventFlags, _ in
                guard let contextInfo else { return }
                let watcher = Unmanaged<FolderWatchService>
                    .fromOpaque(contextInfo)
                    .takeUnretainedValue()
                let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
                watcher.handle(paths: paths, flags: eventFlags, count: eventCount)
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            flags
        ) else {
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
            return
        }
    }

    private func stopStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func handle(
        paths: [String],
        flags: UnsafePointer<FSEventStreamEventFlags>,
        count: Int
    ) {
        guard !roots.isEmpty else { return }

        for index in 0..<min(count, paths.count) {
            let path = URL(fileURLWithPath: paths[index])
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .path
            let matchingRoots = roots.filter {
                path == $0.path || path.hasPrefix($0.path + "/")
            }
            guard !matchingRoots.isEmpty else {
                continue
            }

            let eventFlags = flags[index]
            let requiresFullScan =
                eventFlags & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0
                || eventFlags & FSEventStreamEventFlags(kFSEventStreamEventFlagUserDropped) != 0
                || eventFlags & FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped) != 0
                || eventFlags & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0
                || eventFlags & FSEventStreamEventFlags(kFSEventStreamEventFlagEventIdsWrapped) != 0

            for root in matchingRoots {
                var pending = pendingChanges[root.folderID] ?? PendingChange()
                pending.paths.insert(path)
                pending.requiresFullScan = pending.requiresFullScan || requiresFullScan
                pendingChanges[root.folderID] = pending
            }
        }

        scheduleDelivery()
    }

    private func scheduleDelivery() {
        deliveryWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let changes = self.pendingChanges.map { folderID, pending in
                Change(
                    folderID: folderID,
                    paths: pending.paths,
                    requiresFullScan: pending.requiresFullScan
                )
            }
            self.pendingChanges.removeAll()
            guard !changes.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onChanges?(changes)
            }
        }
        deliveryWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }
}
