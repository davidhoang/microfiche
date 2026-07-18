//
//  MicroficheTests.swift
//  MicroficheTests
//
//  Created by David Hoang on 6/8/25.
//

import XCTest
@testable import Microfiche

final class MicroficheTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testSquareThumbnailFromPNG() throws {
        let pngData = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("microfiche-test.png")
        try pngData.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let thumbnail = ImageThumbnailGenerator.squareThumbnail(from: url, size: 40)
        XCTAssertNotNil(thumbnail)
        XCTAssertEqual(thumbnail?.size.width, 40)
        XCTAssertEqual(thumbnail?.size.height, 40)
    }

    func testImageCacheLoadPopulatesMemory() throws {
        let pngData = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("microfiche-cache-test.png")
        try pngData.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        ImageCache.shared.clearCache()

        let expectation = expectation(description: "load completes")
        ImageCache.shared.loadImage(for: url, size: 40) { image in
            XCTAssertNotNil(image)
            XCTAssertNotNil(ImageCache.shared.getImage(for: url, size: 40))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 3.0)
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
