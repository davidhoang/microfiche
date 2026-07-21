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

    func testGridColumnCountUsesAvailableWidthAndHandlesZeroWidth() {
        XCTAssertEqual(
            ImageGridView.Layout.columnCount(availableWidth: 900, thumbnailWidth: 120),
            6
        )
        XCTAssertEqual(
            ImageGridView.Layout.columnCount(availableWidth: 0, thumbnailWidth: 120),
            1
        )
    }

    func testGridThumbnailDecodeSizeIsStableAcrossSliderRange() {
        XCTAssertEqual(GridThumbnailSizing.decodeSize, GridThumbnailSizing.maximum)
        XCTAssertGreaterThanOrEqual(GridThumbnailSizing.decodeSize, GridThumbnailSizing.minimum)
        XCTAssertGreaterThanOrEqual(GridThumbnailSizing.decodeSize, GridThumbnailSizing.defaultValue)
    }

    func testGridNavigationMovesByCurrentColumnCount() {
        XCTAssertEqual(
            ImageNavigation.nextIndex(
                from: 7,
                itemCount: 20,
                direction: .up,
                viewMode: .grid,
                gridColumnCount: 4
            ),
            3
        )
        XCTAssertEqual(
            ImageNavigation.nextIndex(
                from: 7,
                itemCount: 20,
                direction: .down,
                viewMode: .grid,
                gridColumnCount: 4
            ),
            11
        )
    }

    func testListNavigationMovesOneRowVertically() {
        XCTAssertEqual(
            ImageNavigation.nextIndex(
                from: 7,
                itemCount: 20,
                direction: .up,
                viewMode: .list,
                gridColumnCount: 4
            ),
            6
        )
        XCTAssertNil(
            ImageNavigation.nextIndex(
                from: 0,
                itemCount: 20,
                direction: .up,
                viewMode: .list,
                gridColumnCount: 4
            )
        )
    }

    @MainActor
    func testLibraryStorageRestoresLinkedFolderFromBookmark() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("microfiche-library-\(UUID().uuidString)", isDirectory: true)
        let linkedFolder = root.appendingPathComponent("Photos", isDirectory: true)
        let persistenceURL = root.appendingPathComponent("library.json")
        try FileManager.default.createDirectory(at: linkedFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let storage = LibraryStorage(
            persistenceURL: persistenceURL,
            observesWorkspace: false
        )
        let result = storage.addFolders([linkedFolder])

        XCTAssertEqual(result.folders.count, 1)
        XCTAssertEqual(storage.availableFolderURLs.count, 1)
        XCTAssertEqual(storage.availableFolderURLs.first?.lastPathComponent, "Photos")
        if let availableURL = storage.availableFolderURLs.first {
            XCTAssertTrue(FileManager.default.fileExists(atPath: availableURL.path))
        }

        let restored = LibraryStorage(
            persistenceURL: persistenceURL,
            observesWorkspace: false
        )
        XCTAssertEqual(restored.linkedFolders.map(\.id), result.folders.map(\.id))
        XCTAssertEqual(restored.availableFolderURLs.count, 1)
        XCTAssertEqual(restored.availableFolderURLs.first?.lastPathComponent, "Photos")
        if let availableURL = restored.availableFolderURLs.first {
            XCTAssertTrue(FileManager.default.fileExists(atPath: availableURL.path))
        }
    }

    func testRememberedExternalVolumePersistsConnectionMetadata() throws {
        let volume = RememberedExternalVolume(
            id: "uuid:test-drive",
            name: "Photo Archive",
            lastKnownMountPath: "/Volumes/Photo Archive",
            addedAt: Date(timeIntervalSince1970: 100),
            lastSeenAt: Date(timeIntervalSince1970: 200),
            isConnected: false
        )

        let data = try JSONEncoder().encode(volume)
        XCTAssertEqual(try JSONDecoder().decode(RememberedExternalVolume.self, from: data), volume)
    }

    func testExternalVolumeClassificationRecognizesMountedAndRemovableDrives() {
        XCTAssertTrue(
            LibraryVolumeClassification.isExternal(
                isRemovable: false,
                isEjectable: false,
                mountPath: "/Volumes/Photo Archive"
            )
        )
        XCTAssertTrue(
            LibraryVolumeClassification.isExternal(
                isRemovable: true,
                isEjectable: false,
                mountPath: "/"
            )
        )
        XCTAssertFalse(
            LibraryVolumeClassification.isExternal(
                isRemovable: false,
                isEjectable: false,
                mountPath: "/"
            )
        )
    }

    func testICloudDriveRootUsesFriendlyDisplayName() {
        let folder = LinkedLibraryFolder(
            id: UUID(),
            name: "com~apple~CloudDocs",
            originalPath: "/Users/example/Library/Mobile Documents/com~apple~CloudDocs",
            volumeIdentifier: nil,
            volumeName: nil,
            isExternal: false,
            addedAt: .now,
            resolvedURL: nil
        )

        XCTAssertEqual(folder.displayName, "iCloud Drive")
    }

    func testICloudDriveSubfolderUsesFolderName() {
        let folder = LinkedLibraryFolder(
            id: UUID(),
            name: "Photos",
            originalPath: "/Users/example/Library/Mobile Documents/com~apple~CloudDocs/Projects/Photos",
            volumeIdentifier: nil,
            volumeName: nil,
            isExternal: false,
            addedAt: .now,
            resolvedURL: nil
        )

        XCTAssertEqual(folder.displayName, "Photos")
    }

    func testDroppedImagePersistsWhenContactSheetStorageReloads() throws {
        let fileManager = FileManager.default
        let testDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("microfiche-contact-sheet-\(UUID().uuidString)")
        let sourceURL = testDirectory.appendingPathComponent("source.png")
        let pngData = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!

        try fileManager.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        try pngData.write(to: sourceURL)
        defer { try? fileManager.removeItem(at: testDirectory) }

        let storage = ContactSheetStorage(baseDirectory: testDirectory, fileManager: fileManager)
        let sheet = storage.createContactSheet(name: "Saved Drop")
        XCTAssertNotNil(storage.addImage(from: sourceURL, to: sheet.id))

        let reloadedStorage = ContactSheetStorage(baseDirectory: testDirectory, fileManager: fileManager)
        XCTAssertEqual(reloadedStorage.contactSheets.first?.imageIDs.count, 1)
        XCTAssertEqual(reloadedStorage.getImages(for: sheet.id).count, 1)
    }

    func testImageFileIdentityIsStableAcrossRescans() {
        let url = URL(fileURLWithPath: "/Users/example/Pictures/sunset.jpg")
        let first = ImageFile(url: url)
        let second = ImageFile(url: url)

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first, second)
        XCTAssertEqual(
            first.id,
            ImageIdentity.stableID(for: url.standardizedFileURL)
        )
    }

    func testImageFileIdentityIgnoresRedundantPathComponents() {
        let plain = ImageFile(url: URL(fileURLWithPath: "/Users/example/Pictures/photo.png"))
        let withDot = ImageFile(
            url: URL(fileURLWithPath: "/Users/example/Pictures/./photo.png")
        )

        XCTAssertEqual(plain.id, withDot.id)
    }

    @MainActor
    func testImageMetadataStorePersistsAcrossReloads() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("microfiche-metadata-\(UUID().uuidString)", isDirectory: true)
        let persistenceURL = root.appendingPathComponent("image-metadata.json")
        let imageURL = URL(fileURLWithPath: "/Users/example/Pictures/catalog/frame-01.tif")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ImageMetadataStore(persistenceURL: persistenceURL)
        store.save(
            ImageMetadata(
                tags: ["keeper", "portrait"],
                labels: ["Red"],
                comments: "Looks good",
                whereFrom: "Studio session"
            ),
            for: imageURL
        )

        let reloaded = ImageMetadataStore(persistenceURL: persistenceURL)
        let metadata = reloaded.metadata(for: imageURL)
        XCTAssertEqual(metadata.tags, ["keeper", "portrait"])
        XCTAssertEqual(metadata.labels, ["Red"])
        XCTAssertEqual(metadata.comments, "Looks good")
        XCTAssertEqual(metadata.whereFrom, "Studio session")
    }

    @MainActor
    func testImageMetadataStoreMovesRecordsOnRename() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("microfiche-metadata-move-\(UUID().uuidString)", isDirectory: true)
        let persistenceURL = root.appendingPathComponent("image-metadata.json")
        let oldURL = URL(fileURLWithPath: "/Users/example/Pictures/old-name.jpg")
        let newURL = URL(fileURLWithPath: "/Users/example/Pictures/new-name.jpg")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ImageMetadataStore(persistenceURL: persistenceURL)
        store.save(
            ImageMetadata(tags: ["archive"], labels: [], comments: "Keep", whereFrom: ""),
            for: oldURL
        )
        store.move(from: oldURL, to: newURL)

        XCTAssertTrue(store.metadata(for: oldURL).isEmpty)
        XCTAssertEqual(store.metadata(for: newURL).tags, ["archive"])
        XCTAssertEqual(store.metadata(for: newURL).comments, "Keep")
    }

    @MainActor
    func testImageMetadataStoreRemovesEmptyRecords() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("microfiche-metadata-empty-\(UUID().uuidString)", isDirectory: true)
        let persistenceURL = root.appendingPathComponent("image-metadata.json")
        let imageURL = URL(fileURLWithPath: "/Users/example/Pictures/empty.jpg")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ImageMetadataStore(persistenceURL: persistenceURL)
        store.save(
            ImageMetadata(tags: ["temp"], labels: [], comments: "", whereFrom: ""),
            for: imageURL
        )
        store.save(.empty, for: imageURL)

        let reloaded = ImageMetadataStore(persistenceURL: persistenceURL)
        XCTAssertTrue(reloaded.metadata(for: imageURL).isEmpty)

        let data = try Data(contentsOf: persistenceURL)
        let decoded = try JSONDecoder().decode([String: ImageMetadata].self, from: data)
        XCTAssertTrue(decoded.isEmpty)
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
