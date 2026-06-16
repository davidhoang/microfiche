//
//  ImageCache.swift
//  Microfiche
//
//  Created by David Hoang on 6/8/25.
//

import Foundation
import SwiftUI

class ImageCache {
    static let shared = ImageCache()
    private var cache = NSCache<NSString, NSImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    private init() {
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDirectory.appendingPathComponent("MicroficheThumbnails")
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        cache.countLimit = 200
        cache.totalCostLimit = 50 * 1024 * 1024
    }

    func clearCache() {
        cache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func getImage(for url: URL, size: CGFloat) -> NSImage? {
        if let image = cachedImage(for: url, size: size) {
            PerformanceMonitor.shared.recordCacheHit()
            return image
        }
        PerformanceMonitor.shared.recordCacheMiss()
        return nil
    }

    private func cachedImage(for url: URL, size: CGFloat) -> NSImage? {
        let key = cacheKey(for: url, size: size)

        if let cachedImage = cache.object(forKey: key as NSString) {
            return cachedImage
        }

        let cacheURL = cacheDirectory.appendingPathComponent(key)
        if let image = NSImage(contentsOf: cacheURL) {
            if let cacheAttributes = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
               let sourceAttributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let cacheModDate = cacheAttributes[.modificationDate] as? Date,
               let sourceModDate = sourceAttributes[.modificationDate] as? Date,
               sourceModDate > cacheModDate {
                try? FileManager.default.removeItem(at: cacheURL)
                return nil
            }

            cache.setObject(image, forKey: key as NSString)
            return image
        }

        return nil
    }

    func setImage(_ image: NSImage, for url: URL, size: CGFloat) {
        let key = cacheKey(for: url, size: size)
        cache.setObject(image, forKey: key as NSString)

        let cacheURL = cacheDirectory.appendingPathComponent(key)
        if let data = image.tiffRepresentation {
            try? data.write(to: cacheURL)
        }
    }

    /// Loads and caches a thumbnail if not already present.
    func preloadImage(for url: URL, size: CGFloat) {
        if cachedImage(for: url, size: size) != nil { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            guard let image = ImageThumbnailGenerator.squareThumbnail(from: url, size: size) else { return }
            self.setImage(image, for: url, size: size)
        }
    }

    private func cacheKey(for url: URL, size: CGFloat) -> String {
        let pathHash = url.path.hash
        let sizeString = String(format: "%.0f", size)
        return "\(pathHash)_\(sizeString)"
    }

    func clearCacheForFile(at url: URL) {
        let key = cacheKey(for: url, size: 0)
        let baseKey = key.components(separatedBy: "_").first ?? ""

        cache.removeObject(forKey: key as NSString)

        if let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for file in contents {
                if file.lastPathComponent.hasPrefix(baseKey) {
                    try? fileManager.removeItem(at: file)
                }
            }
        }
    }
}
