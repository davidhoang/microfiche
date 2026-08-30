//
//  PreviewImageCache.swift
//  Microfiche
//
//  Created by Claude on 12/28/25.
//

import AppKit
import Foundation
import ImageIO

final class PreviewImageCache {
    static let shared = PreviewImageCache()

    typealias Completion = (NSImage?) -> Void

    private let cache = NSCache<NSURL, NSImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let interactiveQueue = DispatchQueue(label: "com.microfiche.previewcache.interactive", qos: .userInitiated, attributes: .concurrent)
    private let prefetchQueue = DispatchQueue(label: "com.microfiche.previewcache.prefetch", qos: .utility, attributes: .concurrent)
    private let stateQueue = DispatchQueue(label: "com.microfiche.previewcache.state")
    private let ioQueue = DispatchQueue(label: "com.microfiche.previewcache.io", qos: .utility, attributes: .concurrent)
    private var inFlight: [String: [Completion]] = [:]

    private init() {
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDirectory.appendingPathComponent("MicrofichePreviews")
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        cache.countLimit = 100
        cache.totalCostLimit = 5 * 1024 * 1024 * 1024
    }

    func getImage(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func image(
        for url: URL,
        priority: DispatchQoS.QoSClass = .userInitiated
    ) async throws -> NSImage {
        if let cached = getImage(for: url) {
            return cached
        }

        try await ICloudItemDownloadCoordinator.shared.prepareForReading(url)
        try Task.checkCancellation()

        let image: NSImage = try await withCheckedThrowingContinuation { continuation in
            enqueueImageLoad(for: url, priority: priority) { image in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(
                        throwing: PreviewImageLoadError.unreadable(url.lastPathComponent)
                    )
                }
            }
        }
        try Task.checkCancellation()
        return image
    }

    func preloadImage(
        for url: URL,
        priority: DispatchQoS.QoSClass = .userInitiated,
        completion: ((NSImage?) -> Void)? = nil
    ) {
        if let cached = cache.object(forKey: url as NSURL) {
            if let completion {
                DispatchQueue.main.async {
                    completion(cached)
                }
            }
            return
        }

        Task {
            try? await ICloudItemDownloadCoordinator.shared.prepareForReading(url)
            enqueueImageLoad(for: url, priority: priority, completion: completion)
        }
    }

    private func enqueueImageLoad(
        for url: URL,
        priority: DispatchQoS.QoSClass,
        completion: ((NSImage?) -> Void)?
    ) {
        if let cached = cache.object(forKey: url as NSURL) {
            if let completion {
                DispatchQueue.main.async {
                    completion(cached)
                }
            }
            return
        }

        let key = ImageIdentity.cacheKey(for: url)

        stateQueue.async {
            if self.inFlight[key] != nil {
                if let completion {
                    self.inFlight[key]?.append(completion)
                }
                return
            }

            self.inFlight[key] = completion.map { [$0] } ?? []

            let queue = self.queue(for: priority)
            queue.async {
                let image = autoreleasepool {
                    self.loadImageFromDiskOrSource(for: url, key: key)
                }

                let completions = self.stateQueue.sync {
                    let completions = self.inFlight.removeValue(forKey: key) ?? []
                    return completions
                }

                guard !completions.isEmpty else { return }

                DispatchQueue.main.async {
                    completions.forEach { $0(image) }
                }
            }
        }
    }

    func clearCache() {
        cache.removeAllObjects()
        stateQueue.sync {
            inFlight.removeAll()
        }
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func clearCacheForFile(at url: URL) {
        cache.removeObject(forKey: url as NSURL)

        let key = ImageIdentity.cacheKey(for: url)
        _ = stateQueue.sync {
            inFlight.removeValue(forKey: key)
        }

        let cacheURL = cacheURL(forKey: key)
        try? fileManager.removeItem(at: cacheURL)
    }

    func preloadLibrary(urls: [URL], priority: DispatchQoS.QoSClass = .background) {
        let imageURLs = urls.filter { url in
            let ext = url.pathExtension.lowercased()
            return ext != "pdf" && ext != "svg"
        }

        for url in imageURLs {
            if cache.object(forKey: url as NSURL) != nil {
                continue
            }

            preloadImage(for: url, priority: priority)
        }
    }

    private func queue(for priority: DispatchQoS.QoSClass) -> DispatchQueue {
        switch priority {
        case .userInteractive, .userInitiated:
            return interactiveQueue
        default:
            return prefetchQueue
        }
    }

    private func loadImageFromDiskOrSource(for url: URL, key: String) -> NSImage? {
        if let diskImage = loadImageFromDisk(for: url, key: key) {
            cache.setObject(diskImage, forKey: url as NSURL, cost: cacheCost(for: diskImage))
            return diskImage
        }

        guard let image = loadAndOptimizeImage(from: url) else {
            return nil
        }

        cache.setObject(image, forKey: url as NSURL, cost: cacheCost(for: image))
        persistImage(image, forKey: key)
        return image
    }

    private func loadImageFromDisk(for sourceURL: URL, key: String) -> NSImage? {
        let cacheURL = cacheURL(forKey: key)

        guard fileManager.fileExists(atPath: cacheURL.path) else {
            return nil
        }

        if let cacheAttributes = try? fileManager.attributesOfItem(atPath: cacheURL.path),
           let sourceAttributes = try? fileManager.attributesOfItem(atPath: sourceURL.path),
           let cacheModDate = cacheAttributes[.modificationDate] as? Date,
           let sourceModDate = sourceAttributes[.modificationDate] as? Date,
           sourceModDate > cacheModDate {
            try? fileManager.removeItem(at: cacheURL)
            return nil
        }

        return NSImage(contentsOf: cacheURL)
    }

    private func loadAndOptimizeImage(from url: URL) -> NSImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight as String] as? CGFloat else {
            return NSImage(contentsOf: url)
        }

        let maxDimension: CGFloat = 2000
        let scale = max(width, height) > maxDimension ? maxDimension / max(width, height) : 1.0
        let targetWidth = width * scale
        let targetHeight = height * scale

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(targetWidth, targetHeight),
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return NSImage(contentsOf: url)
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: targetWidth, height: targetHeight))
    }

    private func persistImage(_ image: NSImage, forKey key: String) {
        let cacheURL = cacheURL(forKey: key)

        ioQueue.async {
            guard let data = image.pngData else { return }
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    private func cacheURL(forKey key: String) -> URL {
        cacheDirectory
            .appendingPathComponent(key)
            .appendingPathExtension("png")
    }

    private func cacheCost(for image: NSImage) -> Int {
        Int(image.size.width * image.size.height * 4)
    }
}
