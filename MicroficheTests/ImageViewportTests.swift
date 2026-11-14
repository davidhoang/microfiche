import Foundation
import XCTest
@testable import Microfiche

final class ImageViewportTests: XCTestCase {
    func testFitPreservesAspectRatioForLandscapePortraitAndSmallImages() {
        let viewport = ImageViewport()
        let canvas = CGSize(width: 800, height: 600)
        XCTAssertEqual(viewport.imageSize(
            pixels: CGSize(width: 3200, height: 1600), viewport: canvas, displayScale: 2
        ), CGSize(width: 800, height: 400))
        XCTAssertEqual(viewport.imageSize(
            pixels: CGSize(width: 1600, height: 3200), viewport: canvas, displayScale: 2
        ), CGSize(width: 300, height: 600))
        XCTAssertEqual(viewport.imageSize(
            pixels: CGSize(width: 100, height: 50), viewport: canvas, displayScale: 2
        ), CGSize(width: 50, height: 25))
        XCTAssertEqual(viewport.imageSize(
            pixels: CGSize(width: 3200, height: 1600), viewport: .zero, displayScale: 2
        ), .zero)
    }

    func testActualSizeUsesDisplayPixelsAtBothScreenScales() {
        var viewport = ImageViewport()
        viewport.select(.actualSize)
        for scale in [CGFloat(1), CGFloat(2)] {
            XCTAssertEqual(viewport.imageSize(
                pixels: CGSize(width: 3200, height: 1600),
                viewport: CGSize(width: 800, height: 600), displayScale: scale
            ), CGSize(width: 3200 / scale, height: 1600 / scale))
        }
    }

    func testRepeatedPansClampToEveryEdgeAndFitRecenters() {
        var viewport = ImageViewport()
        let image = CGSize(width: 1600, height: 800)
        let canvas = CGSize(width: 800, height: 600)
        for _ in 0..<2 {
            viewport.select(.actualSize)
            viewport.pan(by: CGSize(width: 90, height: -40), image: image, viewport: canvas)
            XCTAssertEqual(viewport.offset, CGSize(width: 90, height: -40))
            viewport.pan(by: CGSize(width: 30, height: 10), image: image, viewport: canvas)
            XCTAssertEqual(viewport.offset, CGSize(width: 120, height: -30))
            viewport.pan(by: CGSize(width: 10000, height: 10000), image: image, viewport: canvas)
            XCTAssertEqual(viewport.offset, CGSize(width: 400, height: 100))
            viewport.pan(by: CGSize(width: -10000, height: -10000), image: image, viewport: canvas)
            XCTAssertEqual(viewport.offset, CGSize(width: -400, height: -100))
            viewport.select(.fit)
            XCTAssertEqual(viewport.offset, .zero)
            viewport.pan(by: CGSize(width: 90, height: 50), image: image, viewport: canvas)
            XCTAssertEqual(viewport.offset, .zero)
        }
    }

    func testResizeAndDisplayScaleChangesReclampWithoutStaleOffsets() {
        var viewport = ImageViewport()
        viewport.select(.actualSize)
        viewport.pan(
            by: CGSize(width: 1000, height: -1000),
            image: CGSize(width: 1600, height: 800), viewport: CGSize(width: 800, height: 600)
        )
        viewport.constrain(image: CGSize(width: 1600, height: 800), viewport: CGSize(width: 1500, height: 900))
        XCTAssertEqual(viewport.offset, CGSize(width: 50, height: 0))
        viewport.constrain(image: CGSize(width: 800, height: 400), viewport: CGSize(width: 1500, height: 900))
        XCTAssertEqual(viewport.offset, .zero)
        viewport.pan(
            by: CGSize(width: -20, height: 30),
            image: CGSize(width: 1600, height: 800), viewport: CGSize(width: 800, height: 600)
        )
        XCTAssertEqual(viewport.offset, CGSize(width: -20, height: 30))
    }

    func testSmallImagesCannotPanAndPortraitOnlyPansOnOverflowingAxis() {
        var viewport = ImageViewport()
        viewport.select(.actualSize)
        let canvas = CGSize(width: 800, height: 600)
        viewport.pan(by: CGSize(width: 100, height: 100), image: CGSize(width: 50, height: 25), viewport: canvas)
        XCTAssertEqual(viewport.offset, .zero)
        viewport.pan(by: CGSize(width: 100, height: 100), image: CGSize(width: 600, height: 1600), viewport: canvas)
        XCTAssertEqual(viewport.offset, CGSize(width: 0, height: 100))
        viewport.select(.actualSize)
        XCTAssertEqual(viewport.offset, .zero)
    }
}
