import AppKit
import SwiftUI

struct ZoomableDetailImage: View {
    let image: NSImage
    @Environment(\.displayScale) private var displayScale
    @State private var viewport = ImageViewport()
    @GestureState private var dragTranslation: CGSize = .zero

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geometry in
                let size = viewport.imageSize(
                    pixels: image.size, viewport: geometry.size, displayScale: displayScale
                )
                let start = viewport.constrainedOffset(
                    viewport.offset, image: size, viewport: geometry.size
                )
                let offset = viewport.constrainedOffset(
                    CGSize(
                        width: start.width + dragTranslation.width,
                        height: start.height + dragTranslation.height
                    ),
                    image: size,
                    viewport: geometry.size
                )

                Color.clear
                    .overlay {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(viewport.mode == .actualSize ? .none : .high)
                            .frame(width: size.width, height: size.height)
                            .offset(offset)
                            .accessibilityIdentifier("image-load.loaded")
                    }
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .updating($dragTranslation) { value, translation, _ in
                                translation = value.translation
                            }
                            .onEnded { value in
                                viewport.pan(by: value.translation, image: size, viewport: geometry.size)
                            },
                        including: viewport.mode == .actualSize ? .all : .none
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Photo canvas")
                    .accessibilityValue(
                        "\(viewport.mode == .fit ? "Fit" : "100%"), horizontal offset \(Int(offset.width)), vertical offset \(Int(offset.height))"
                    )
                    .accessibilityHint("At 100%, drag to pan or use the scroll actions")
                    .accessibilityIdentifier("detail.zoom.canvas")
                    .accessibilityScrollAction { edge in
                        let translation: CGSize
                        switch edge {
                        case .leading: translation = CGSize(width: 100, height: 0)
                        case .trailing: translation = CGSize(width: -100, height: 0)
                        case .top: translation = CGSize(width: 0, height: 100)
                        case .bottom: translation = CGSize(width: 0, height: -100)
                        }
                        viewport.pan(by: translation, image: size, viewport: geometry.size)
                    }
                    .onChange(of: geometry.size) { _, newSize in
                        viewport.constrain(
                            image: viewport.imageSize(
                                pixels: image.size, viewport: newSize, displayScale: displayScale
                            ),
                            viewport: newSize
                        )
                    }
                    .onChange(of: displayScale) { _, newScale in
                        viewport.constrain(
                            image: viewport.imageSize(
                                pixels: image.size, viewport: geometry.size, displayScale: newScale
                            ),
                            viewport: geometry.size
                        )
                    }
            }

            HStack(spacing: 8) {
                zoomButton("Fit", mode: .fit, identifier: "detail.zoom.fit")
                zoomButton("100%", mode: .actualSize, identifier: "detail.zoom.actualSize")
            }
            .controlSize(.small)
        }
    }

    private func zoomButton(_ title: String, mode: ImageViewport.Mode, identifier: String) -> some View {
        Button(title) { viewport.select(mode) }
            .buttonStyle(.bordered)
            .tint(viewport.mode == mode ? Color.accentColor : Color.secondary)
            .accessibilityValue(viewport.mode == mode ? "Selected" : "Not selected")
            .accessibilityIdentifier(identifier)
            .help(mode == .fit ? "Fit image in the window" : "Actual size: one image pixel per display pixel")
    }
}
