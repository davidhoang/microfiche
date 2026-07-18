//
//  ThumbnailViews.swift
//  Microfiche
//
//  Created by David Hoang on 6/8/25.
//

import SwiftUI

// MARK: - Optimized Image Loading

struct OptimizedAsyncImage: View {
    let url: URL
    let size: CGFloat
    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var hasError = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
            } else if hasError {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
                    .font(.system(size: size * 0.3))
            } else {
                thumbnailPlaceholder
            }
        }
        .task(id: cacheIdentity) {
            await MainActor.run {
                loadImage()
            }
        }
    }

    private var cacheIdentity: String {
        "\(url.path)|\(Int(size.rounded()))"
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.gray.opacity(isLoading ? 0.12 : 0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
            )
    }

    private func loadImage() {
        if let cachedImage = ImageCache.shared.getImage(for: url, size: size) {
            image = cachedImage
            hasError = false
            isLoading = false
            return
        }

        guard !isLoading else { return }

        isLoading = true
        hasError = false

        ImageCache.shared.loadImage(for: url, size: size) { loadedImage in
            isLoading = false

            if let loadedImage {
                image = loadedImage
            } else {
                hasError = true
            }
        }
    }
}

// MARK: - File Thumbnail

struct FileThumbnailView: View {
    let file: ImageFile
    let size: CGFloat
    let onRename: (URL, String) -> Void

    var body: some View {
        ZStack {
            Color(NSColor.controlBackgroundColor)

            OptimizedAsyncImage(url: file.url, size: size)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(width: size, height: size)
    }
}
