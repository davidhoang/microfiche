//
//  ImageThumbnailGenerator.swift
//  Microfiche
//
//  Shared CGImageSource-based thumbnail generation for fast, memory-efficient decoding.
//

import AppKit
import Foundation

enum ImageThumbnailGenerator {
    /// Generates a downsampled thumbnail without loading the full image into memory.
    static func thumbnail(from url: URL, maxPixelSize: CGFloat) -> NSImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCache: false
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    /// Produces a square-cropped thumbnail suitable for grid/list cells.
    static func squareThumbnail(from url: URL, size: CGFloat) -> NSImage? {
        guard let source = thumbnail(from: url, maxPixelSize: size * 2) else { return nil }

        let targetSize = NSSize(width: size, height: size)
        let thumbnail = NSImage(size: targetSize)

        let imageAspect = source.size.width / max(source.size.height, 1)
        let targetAspect: CGFloat = 1
        var drawRect = NSRect(origin: .zero, size: targetSize)

        if imageAspect > targetAspect {
            let scaledHeight = targetSize.width / imageAspect
            drawRect.origin.y = (targetSize.height - scaledHeight) / 2
            drawRect.size = NSSize(width: targetSize.width, height: scaledHeight)
        } else {
            let scaledWidth = targetSize.height * imageAspect
            drawRect.origin.x = (targetSize.width - scaledWidth) / 2
            drawRect.size = NSSize(width: scaledWidth, height: targetSize.height)
        }

        thumbnail.lockFocus()
        source.draw(
            in: drawRect,
            from: NSRect(origin: .zero, size: source.size),
            operation: .copy,
            fraction: 1.0
        )
        thumbnail.unlockFocus()
        return thumbnail
    }
}
