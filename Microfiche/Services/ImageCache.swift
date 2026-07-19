//
//  ImageCache.swift
//  Microfiche
//
//  Created by David Hoang on 6/8/25.
//

import AppKit
import Foundation
import ImageIO
import PDFKit

final class ImageCache {
    static let shared = ImageCache()

    typealias Completion = (NSImage?) -> Void

    private let cache = NSCache<NSString, NSImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let stateQueue = DispatchQueue(label: "com.microfiche.thumbnailcache.state")
    private let ioQueue = DispatchQueue(label: "com.microfiche.thumbnailcache.io", qos: .utility, attributes: .concurrent)
    private var inFlight: [String: [Completion]] = [:]

    private init() {
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDirectory.appendingPathComponent("MicroficheThumbnails")
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        cache.countLimit = 300
        cache.totalCostLimit = 80 * 1024 * 1024
    }

    func clearCache() {
        cache.removeAllObjects()
        stateQueue.sync {
            inFlight.removeAll()
        }
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func getImage(for url: URL, size: CGFloat) -> NSImage? {
        let key = cacheKey(for: url, size: size)
        return cache.object(forKey: key as NSString)
    }

    func loadImage(for url: URL, size: CGFloat, completion: @escaping Completion) {
        let key = cacheKey(for: url, size: size)

        if let cachedImage = cache.object(forKey: key as NSString) {
            DispatchQueue.main.async {
                completion(cachedImage)
            }
            return
        }

        stateQueue.async {
            if self.inFlight[key] != nil {
                self.inFlight[key]?.append(completion)
                return
            }

            self.inFlight[key] = [completion]

            self.ioQueue.async {
                let image = autoreleasepool {
                    self.loadImageFromDiskOrSource(for: url, size: size, key: key)
                }

                let completions = self.stateQueue.sync {
                    let completions = self.inFlight.removeValue(forKey: key) ?? []
                    return completions
                }

                DispatchQueue.main.async {
                    completions.forEach { $0(image) }
                }
            }
        }
    }

    func prefetchImage(for url: URL, size: CGFloat) {
        loadImage(for: url, size: size) { _ in }
    }

    func clearCacheForFile(at url: URL) {
        let baseKey = String(url.path.hash)

        if let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for file in contents where file.deletingPathExtension().lastPathComponent.hasPrefix(baseKey) {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    private func loadImageFromDiskOrSource(for url: URL, size: CGFloat, key: String) -> NSImage? {
        if let diskImage = loadImageFromDisk(for: url, key: key) {
            cache.setObject(diskImage, forKey: key as NSString, cost: cacheCost(for: diskImage))
            return diskImage
        }

        guard let image = createThumbnail(for: url, size: size) else {
            return nil
        }

        cache.setObject(image, forKey: key as NSString, cost: cacheCost(for: image))
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

    private func createThumbnail(for url: URL, size: CGFloat) -> NSImage? {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return createPDFThumbnail(for: url, size: size)
        case "svg":
            return NSImage(contentsOf: url)
        default:
            return createRasterThumbnail(for: url, size: size)
        }
    }

    private func createRasterThumbnail(for url: URL, size: CGFloat) -> NSImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return NSImage(contentsOf: url)
        }

        let maxPixelSize = max(1, Int(ceil(size * 2)))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return NSImage(contentsOf: url)
        }

        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        )
    }

    private func createPDFThumbnail(for url: URL, size: CGFloat) -> NSImage? {
        guard let pdfDocument = PDFDocument(url: url),
              let page = pdfDocument.page(at: 0) else {
            return nil
        }

        return page.thumbnail(of: .init(width: size * 2, height: size * 2), for: .cropBox)
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

    private func cacheKey(for url: URL, size: CGFloat) -> String {
        let pathHash = url.path.hash
        let sizeString = String(format: "%.0f", size)
        return "\(pathHash)_\(sizeString)"
    }

    private func cacheCost(for image: NSImage) -> Int {
        Int(image.size.width * image.size.height * 4)
    }
}

private extension NSImage {
    var pngData: Data? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let representation = NSBitmapImageRep(cgImage: cgImage)
        return representation.representation(using: .png, properties: [:])
    }
}
