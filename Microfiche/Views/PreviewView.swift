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
                Color.black.opacity(0.8)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture(perform: onDismiss)

                VStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(NSColor.controlBackgroundColor))
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 4)
                        Group {
                            if file.url.pathExtension.lowercased() == "pdf" {
                                PDFKitView(url: file.url)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else if file.url.pathExtension.lowercased() == "svg" {
                                SVGImageView(url: file.url)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .aspectRatio(contentMode: .fit)
                            } else {
                                if let image = previewImage {
                                    Image(nsImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else if isLoading {
                                    ProgressView()
                                }
                            }
                        }
                        .padding(32)
                    }
                    .frame(width: geometry.size.width * 0.75, height: geometry.size.height * 0.75)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            loadPreviewImage()
        }
    }

    private func loadPreviewImage() {
        if let cached = PreviewImageCache.shared.getImage(for: file.url) {
            self.previewImage = cached
            self.isLoading = false
            return
        }

        PreviewImageCache.shared.preloadImage(for: file.url) { image in
            self.previewImage = image
            self.isLoading = false
        }
    }
}
