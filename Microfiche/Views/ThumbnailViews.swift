//
//  ThumbnailViews.swift
//  Microfiche
//
//  Created by David Hoang on 6/8/25.
//

import SwiftUI
import PDFKit

// MARK: - Optimized Image Loading

struct OptimizedAsyncImage: View {
    let url: URL
    let size: CGFloat
    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var hasError = false

    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                ProgressView()
                    .scaleEffect(0.5)
            } else if hasError {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
                    .font(.system(size: size * 0.3))
            } else {
                Color.gray.opacity(0.1)
            }
        }
        .onAppear {
            loadImage()
        }
    }

    private func loadImage() {
        if let cachedImage = ImageCache.shared.getImage(for: url, size: size) {
            self.image = cachedImage
            return
        }

        isLoading = true
        hasError = false

        DispatchQueue.global(qos: .userInitiated).async {
            let image = ImageThumbnailGenerator.squareThumbnail(from: url, size: size)
            DispatchQueue.main.async {
                self.isLoading = false
                if let image = image {
                    self.image = image
                    ImageCache.shared.setImage(image, for: url, size: size)
                } else {
                    self.hasError = true
                }
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
            Group {
                if file.url.pathExtension.lowercased() == "pdf" {
                    PDFThumbnailView(url: file.url, size: size)
                        .aspectRatio(contentMode: .fit)
                } else if file.url.pathExtension.lowercased() == "svg" {
                    SVGThumbnailView(url: file.url)
                        .aspectRatio(contentMode: .fit)
                } else {
                    OptimizedAsyncImage(url: file.url, size: size)
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - PDF Thumbnail

struct PDFThumbnailView: View {
    let url: URL
    let size: CGFloat
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let image = thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.gray.opacity(0.1)
            }
        }
        .onAppear(perform: generateThumbnail)
    }

    private func generateThumbnail() {
        if let cachedImage = ImageCache.shared.getImage(for: url, size: size) {
            self.thumbnail = cachedImage
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            guard let pdfDocument = PDFDocument(url: url),
                  let page = pdfDocument.page(at: 0) else {
                return
            }
            let image = page.thumbnail(of: .init(width: size * 2, height: size * 2), for: .cropBox)
            DispatchQueue.main.async {
                self.thumbnail = image
                ImageCache.shared.setImage(image, for: url, size: size)
            }
        }
    }
}

// MARK: - SVG Thumbnail

struct SVGThumbnailView: View {
    let url: URL

    var body: some View {
        if let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Color.gray.opacity(0.1)
        }
    }
}
