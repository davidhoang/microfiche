//
//  RecoverablePreviewImage.swift
//  Microfiche
//

import SwiftUI

struct RecoverablePreviewImage: View {
    let url: URL
    var loadingLabel = "Loading image…"

    @StateObject private var model = PreviewImageLoadModel()

    var body: some View {
        Group {
            if let image = model.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .accessibilityIdentifier("image-load.loaded")
            } else {
                statusContent
            }
        }
        .task(id: url) {
            model.prepare(url: url)
        }
        .onDisappear {
            model.cancel()
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch model.state.phase {
        case .idle, .loading:
            ProgressView(loadingLabel)
                .accessibilityIdentifier("image-load.loading")
        case .placeholder:
            recoveryMessage(
                title: "Stored in iCloud",
                message: "Download this image to view it in Microfiche.",
                buttonTitle: "Download",
                identifier: "image-load.download"
            )
        case .downloading:
            ProgressView("Downloading from iCloud…")
                .accessibilityIdentifier("image-load.downloading")
        case .failed(let message):
            recoveryMessage(
                title: "Image unavailable",
                message: message,
                buttonTitle: "Try Again",
                identifier: "image-load.retry"
            )
        case .cancelled:
            recoveryMessage(
                title: "Loading cancelled",
                message: "The image was not changed.",
                buttonTitle: "Try Again",
                identifier: "image-load.retry"
            )
        case .loaded:
            EmptyView()
        }
    }

    private func recoveryMessage(
        title: String,
        message: String,
        buttonTitle: String,
        identifier: String
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(buttonTitle) {
                model.load()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: 320)
        .padding()
    }
}
