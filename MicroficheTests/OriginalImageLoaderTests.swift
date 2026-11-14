import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Microfiche

final class OriginalImageLoaderTests: XCTestCase {
    @MainActor
    func testOriginalDecodePreservesResolutionAndAppliesOrientation() async throws {
        for orientation in [1, 6] {
            let url = try makeImage(orientation: orientation)
            defer { try? FileManager.default.removeItem(at: url) }
            let image = try await OriginalImageLoader.image(for: url)
            let expected = orientation == 1
                ? CGSize(width: 3200, height: 1600)
                : CGSize(width: 1600, height: 3200)
            XCTAssertEqual(image.size, expected)
            let representation = try XCTUnwrap(image.representations.first)
            XCTAssertEqual(representation.pixelsWide, Int(expected.width))
            XCTAssertEqual(representation.pixelsHigh, Int(expected.height))
        }
    }

    @MainActor
    func testUnreadableOriginalFailsAndCanBeRetriedAfterReplacement() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("original-\(UUID()).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        for _ in 0..<2 {
            try Data("invalid image".utf8).write(to: url)
            do {
                _ = try await OriginalImageLoader.image(for: url)
                XCTFail("Unreadable originals must fail")
            } catch {
                XCTAssertTrue(error is PreviewImageLoadError)
            }
            let valid = try makeImage(orientation: 1)
            try FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: valid, to: url)
            let recovered = try await OriginalImageLoader.image(for: url)
            XCTAssertEqual(recovered.size, CGSize(width: 3200, height: 1600))
        }
    }

    @MainActor
    func testCancelledOriginalLoadDoesNotReturnAnImage() async throws {
        let url = try makeImage(orientation: 1)
        defer { try? FileManager.default.removeItem(at: url) }
        let task = Task { try await OriginalImageLoader.image(for: url) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled load must not return an image")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    private func makeImage(orientation: Int) throws -> URL {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 3200, height: 1600, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 3200, height: 1600))
        let image = try XCTUnwrap(context.makeImage())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("original-\(UUID()).jpg")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}
