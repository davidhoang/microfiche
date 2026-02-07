//
//  ImagePrefetcher.swift
//  Microfiche
//
//  Created by David Hoang on 2/7/26.
//

import Foundation

enum ImagePrefetcher {
    /// Prefetch nearby thumbnail and preview images for smooth scrolling and instant previews.
    static func prefetchNearby(
        for file: ImageFile,
        in imageFiles: [ImageFile],
        thumbnailSize: CGFloat,
        thumbnailRange: Int = 5,
        previewRange: Int = 5
    ) {
        guard let currentIndex = imageFiles.firstIndex(where: { $0.id == file.id }) else { return }

        // Prefetch thumbnails
        let thumbEnd = min(currentIndex + 1 + thumbnailRange, imageFiles.count)
        for index in (currentIndex + 1)..<thumbEnd {
            let prefetchFile = imageFiles[index]
            let ext = prefetchFile.url.pathExtension.lowercased()
            if ext != "pdf" && ext != "svg" {
                DispatchQueue.global(qos: .background).async {
                    _ = ImageCache.shared.getImage(for: prefetchFile.url, size: thumbnailSize)
                }
            }
        }

        // Prefetch full previews
        let previewEnd = min(currentIndex + 1 + previewRange, imageFiles.count)
        for index in currentIndex..<previewEnd {
            let prefetchFile = imageFiles[index]
            let ext = prefetchFile.url.pathExtension.lowercased()
            if ext != "pdf" && ext != "svg" {
                PreviewImageCache.shared.preloadImage(for: prefetchFile.url)
            }
        }
    }
}
