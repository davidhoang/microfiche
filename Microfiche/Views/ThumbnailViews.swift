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
    var decodeSize: CGFloat? = nil
    var isResizing: Bool = false

    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var hasError = false
    @State private var activeDecodeSize: CGFloat?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(isResizing ? .low : .medium)
                    .aspectRatio(contentMode: .fit)
            } else if hasError {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
                    .font(.system(size: size * 0.3))
            } else {
                thumbnailPlaceholder
            }
        }
        .onAppear(perform: syncActiveDecodeSize)
        .onChange(of: size) { _, _ in
            syncActiveDecodeSize()
        }
        .onChange(of: decodeSize) { _, _ in
            syncActiveDecodeSize()
        }
        .onChange(of: isResizing) { _, _ in
            syncActiveDecodeSize()
        }
        .task(id: cacheIdentity) {
            await MainActor.run {
                loadImage()
            }
        }
    }

    private var resolvedDecodeSize: CGFloat {
        activeDecodeSize ?? decodeSize ?? size
    }

    private var cacheIdentity: String {
        "\(url.path)|\(Int(resolvedDecodeSize.rounded()))"
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.gray.opacity(isLoading ? 0.12 : 0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
            )
    }

    private func syncActiveDecodeSize() {
        let target = decodeSize ?? size

        if isResizing {
            if activeDecodeSize == nil {
                activeDecodeSize = target
            }
            return
        }

        if activeDecodeSize != target {
            activeDecodeSize = target
        }
    }

    private func loadImage() {
        let requestSize = resolvedDecodeSize

        if let cachedImage = ImageCache.shared.getImage(for: url, size: requestSize) {
            image = cachedImage
            hasError = false
            isLoading = false
            return
        }

        guard !isLoading else { return }

        isLoading = true
        hasError = false

        ImageCache.shared.loadImage(for: url, size: requestSize) { loadedImage in
            isLoading = false

            if let loadedImage {
                image = loadedImage
            } else if image == nil {
                hasError = true
            }
        }
    }
}

// MARK: - File Thumbnail

struct FileThumbnailView: View {
    let file: ImageFile
    let size: CGFloat
    let decodeSize: CGFloat?
    let aspectRatio: CGFloat
    let isResizing: Bool
    let onRename: (URL, String) -> Void

    init(
        file: ImageFile,
        size: CGFloat,
        decodeSize: CGFloat? = nil,
        aspectRatio: CGFloat = 1,
        isResizing: Bool = false,
        onRename: @escaping (URL, String) -> Void
    ) {
        self.file = file
        self.size = size
        self.decodeSize = decodeSize
        self.aspectRatio = aspectRatio
        self.isResizing = isResizing
        self.onRename = onRename
    }

    var body: some View {
        let height = size / aspectRatio

        ZStack {
            Color(NSColor.controlBackgroundColor)

            OptimizedAsyncImage(
                url: file.url,
                size: size,
                decodeSize: decodeSize,
                isResizing: isResizing
            )
            .frame(width: size, height: height)
        }
        .frame(width: size, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
