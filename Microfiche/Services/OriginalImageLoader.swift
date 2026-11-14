import AppKit
import ImageIO

// Original images are held by the detail view, not the shared preview cache.
enum OriginalImageLoader {
    static func image(for url: URL) async throws -> NSImage {
        try await ICloudItemDownloadCoordinator.shared.prepareForReading(url)
        try Task.checkCancellation()
        let image = try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(width, height),
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else {
                throw PreviewImageLoadError.unreadable(url.lastPathComponent)
            }
            return NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
        }.value
        try Task.checkCancellation()
        return image
    }
}
