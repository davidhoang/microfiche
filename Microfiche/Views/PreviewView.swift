//
//  PreviewView.swift
//  Microfiche
//
//  Created by David Hoang on 6/8/25.
//

import SwiftUI

struct PreviewView: View {
    let file: ImageFile
    let onDismiss: () -> Void
    @State private var previewImage: NSImage?
    @State private var isLoading = true

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.72)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)

                LiquidGlassPanel(cornerRadius: 16) {
                    Group {
                        if file.url.pathExtension.lowercased() == "pdf" {
                            PDFKitView(url: file.url)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if file.url.pathExtension.lowercased() == "svg" {
                            SVGImageView(url: file.url)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .aspectRatio(contentMode: .fit)
                        } else if let image = previewImage {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else if isLoading {
                            ProgressView()
                        }
                    }
                    .padding(32)
                }
                .frame(width: geometry.size.width * 0.75, height: geometry.size.height * 0.75)
            }
        }
        .task(id: file.id) {
            await loadPreviewImage()
        }
    }

    @MainActor
    private func loadPreviewImage() async {
        previewImage = nil
        isLoading = true

        guard !["pdf", "svg"].contains(file.url.pathExtension.lowercased()) else {
            isLoading = false
            return
        }

        if let cached = PreviewImageCache.shared.getImage(for: file.url) {
            previewImage = cached
            isLoading = false
            return
        }

        let loadedImage: NSImage? = await withCheckedContinuation { continuation in
            PreviewImageCache.shared.preloadImage(for: file.url) { image in
                continuation.resume(returning: image)
            }
        }

        guard !Task.isCancelled else { return }
        previewImage = loadedImage
        isLoading = false
    }
}
