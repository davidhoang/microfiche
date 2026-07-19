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
    private let interactiveQueue = DispatchQueue(label: "com.microfiche.previewcache.interactive", qos: .userInitiated, attributes: .concurrent)
    private let prefetchQueue = DispatchQueue(label: "com.microfiche.previewcache.prefetch", qos: .utility, attributes: .concurrent)
    private let stateQueue = DispatchQueue(label: "com.microfiche.previewcache.state")
    private var inFlight: [String: [Completion]] = [:]

    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 5 * 1024 * 1024 * 1024
    }

    func getImage(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
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

        let key = url.path

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
                    self.loadAndOptimizeImage(from: url)
                }

                if let image = image {
                    let cost = Int(image.size.width * image.size.height * 4)
                    self.cache.setObject(image, forKey: url as NSURL, cost: cost)
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

    private func queue(for priority: DispatchQoS.QoSClass) -> DispatchQueue {
        switch priority {
        case .userInteractive, .userInitiated:
            return interactiveQueue
        default:
            return prefetchQueue
        }
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

    func clearCache() {
        cache.removeAllObjects()
        stateQueue.sync {
            inFlight.removeAll()
        }
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
}
