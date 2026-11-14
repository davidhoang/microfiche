import Foundation

struct ImageViewport {
    enum Mode {
        case fit
        case actualSize
    }

    private(set) var mode: Mode = .fit
    private(set) var offset: CGSize = .zero

    mutating func select(_ mode: Mode) {
        self.mode = mode
        offset = .zero
    }

    func imageSize(pixels: CGSize, viewport: CGSize, displayScale: CGFloat) -> CGSize {
        guard pixels.width > 0, pixels.height > 0,
              viewport.width > 0, viewport.height > 0 else { return .zero }
        let scale: CGFloat
        switch mode {
        case .fit:
            scale = min(1 / displayScale, viewport.width / pixels.width, viewport.height / pixels.height)
        case .actualSize:
            scale = 1 / displayScale
        }
        return CGSize(width: pixels.width * scale, height: pixels.height * scale)
    }

    func constrainedOffset(_ proposed: CGSize, image: CGSize, viewport: CGSize) -> CGSize {
        guard mode == .actualSize else { return .zero }
        let limitX = max(0, (image.width - viewport.width) / 2)
        let limitY = max(0, (image.height - viewport.height) / 2)
        return CGSize(
            width: min(limitX, max(-limitX, proposed.width)),
            height: min(limitY, max(-limitY, proposed.height))
        )
    }

    mutating func pan(by translation: CGSize, image: CGSize, viewport: CGSize) {
        let start = constrainedOffset(offset, image: image, viewport: viewport)
        offset = constrainedOffset(
            CGSize(width: start.width + translation.width, height: start.height + translation.height),
            image: image,
            viewport: viewport
        )
    }

    mutating func constrain(image: CGSize, viewport: CGSize) {
        offset = constrainedOffset(offset, image: image, viewport: viewport)
    }
}
