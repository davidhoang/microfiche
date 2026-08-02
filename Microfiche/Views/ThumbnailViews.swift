//
//  ThumbnailViews.swift
//  Microfiche
//
//  Created by David Hoang on 6/8/25.
//

import SwiftUI

enum ThumbnailFitSizing {
    static func size(content: CGSize, bounding: CGSize) -> CGSize {
        guard content.width > 0,
              content.height > 0,
              bounding.width > 0,
              bounding.height > 0 else { return bounding }

        let scale = min(bounding.width / content.width, bounding.height / content.height)
        return CGSize(width: content.width * scale, height: content.height * scale)
    }
}

// MARK: - Optimized Image Loading

struct OptimizedAsyncImage: View {
    let url: URL
    let size: CGFloat
    var decodeSize: CGFloat? = nil
    var isResizing: Bool = false
    var fitsAsset = false
    var isSelected = false
    var isHovered = false

    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var hasError = false

    var body: some View {
        Group {
            if fitsAsset {
                GeometryReader { geometry in
                    let fittedSize = ThumbnailFitSizing.size(
                        content: image?.size ?? geometry.size,
                        bounding: geometry.size
                    )

                    renderedContent
                        .frame(width: fittedSize.width, height: fittedSize.height)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                        }
                        .contentSelectionChrome(isSelected: isSelected)
                        .contentHoverDynamics(
                            isHovered: isResizing ? false : isHovered,
                            isSelected: isSelected
                        )
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .center
                        )
                }
            } else {
                renderedContent
            }
        }
        .task(id: cacheIdentity) {
            await MainActor.run {
                loadImage()
            }
        }
    }

    @ViewBuilder
    private var renderedContent: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(isResizing ? .low : .high)
                .aspectRatio(contentMode: .fit)
        } else if hasError {
            Image(systemName: "photo")
                .foregroundColor(.secondary)
                .font(.system(size: size * 0.3))
        } else {
            thumbnailPlaceholder
        }
    }

    private var resolvedDecodeSize: CGFloat {
        decodeSize ?? size
    }

    private var cacheIdentity: String {
        "\(url.path)|\(Int(resolvedDecodeSize.rounded()))"
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(NSColor.quaternaryLabelColor).opacity(isLoading ? 0.18 : 0.12))
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
    let fitsAsset: Bool
    let isSelected: Bool
    let isHovered: Bool
    let onRename: (URL, String) -> Void

    init(
        file: ImageFile,
        size: CGFloat,
        decodeSize: CGFloat? = nil,
        aspectRatio: CGFloat = 1,
        isResizing: Bool = false,
        fitsAsset: Bool = false,
        isSelected: Bool = false,
        isHovered: Bool = false,
        onRename: @escaping (URL, String) -> Void
    ) {
        self.file = file
        self.size = size
        self.decodeSize = decodeSize
        self.aspectRatio = aspectRatio
        self.isResizing = isResizing
        self.fitsAsset = fitsAsset
        self.isSelected = isSelected
        self.isHovered = isHovered
        self.onRename = onRename
    }

    var body: some View {
        let height = size / aspectRatio

        if fitsAsset {
            OptimizedAsyncImage(
                url: file.url,
                size: size,
                decodeSize: decodeSize,
                isResizing: isResizing,
                fitsAsset: true,
                isSelected: isSelected,
                isHovered: isHovered
            )
            .frame(width: size, height: height)
        } else {
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
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
    }
}
