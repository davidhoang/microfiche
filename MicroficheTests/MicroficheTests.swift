//
//  MicroficheTests.swift
//  MicroficheTests
//
//  Created by David Hoang on 6/8/25.
//

import PDFKit
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

    func testImageIdentityCacheKeyIsStableAndPathNormalized() {
        let plain = URL(fileURLWithPath: "/Users/example/Pictures/photo.png")
        let withDot = URL(fileURLWithPath: "/Users/example/Pictures/./photo.png")

        let first = ImageIdentity.cacheKey(for: plain)
        let second = ImageIdentity.cacheKey(for: plain)
        let normalized = ImageIdentity.cacheKey(for: withDot)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first, normalized)
        XCTAssertEqual(first.count, 64)
        XCTAssertTrue(first.allSatisfy(\.isHexDigit))
    }

    func testPreviewImageCachePersistsToDiskAndClearsPerFile() throws {
        let pngData = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("microfiche-preview-cache-\(UUID().uuidString).png")
        try pngData.write(to: url)
        defer {
            try? FileManager.default.removeItem(at: url)
            PreviewImageCache.shared.clearCacheForFile(at: url)
        }

        PreviewImageCache.shared.clearCacheForFile(at: url)

        let loadExpectation = expectation(description: "preview load completes")
        PreviewImageCache.shared.preloadImage(for: url) { image in
            XCTAssertNotNil(image)
            XCTAssertNotNil(PreviewImageCache.shared.getImage(for: url))
            loadExpectation.fulfill()
        }
        wait(for: [loadExpectation], timeout: 3.0)

        let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let diskURL = cachesDirectory
            .appendingPathComponent("MicrofichePreviews")
            .appendingPathComponent(ImageIdentity.cacheKey(for: url))
            .appendingPathExtension("png")

        var diskReady = false
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: diskURL.path) {
                diskReady = true
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertTrue(diskReady, "Expected optimized preview PNG on disk")

        PreviewImageCache.shared.clearCacheForFile(at: url)
        XCTAssertNil(PreviewImageCache.shared.getImage(for: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: diskURL.path))
    }

    func testImageCacheClearCacheForFileRemovesMemoryEntry() throws {
        let pngData = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("microfiche-thumb-clear-\(UUID().uuidString).png")
        try pngData.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        ImageCache.shared.clearCache()

        let expectation = expectation(description: "thumbnail load completes")
        ImageCache.shared.loadImage(for: url, size: 40) { image in
            XCTAssertNotNil(image)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3.0)
        XCTAssertNotNil(ImageCache.shared.getImage(for: url, size: 40))

        ImageCache.shared.clearCacheForFile(at: url)
        XCTAssertNil(ImageCache.shared.getImage(for: url, size: 40))
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

    func testLibraryNavigationRoutesFirstAndSubsequentDetailSelections() {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        var path = LibraryNavigation.path(toImage: firstID)
        XCTAssertEqual(path, [.image(firstID)])
        XCTAssertEqual(LibraryNavigation.detailImageID(in: path), firstID)

        path.removeLast()
        XCTAssertNil(LibraryNavigation.detailImageID(in: path))

        path = LibraryNavigation.path(toImage: secondID)
        XCTAssertEqual(path, [.image(secondID)])
        XCTAssertEqual(LibraryNavigation.detailImageID(in: path), secondID)

        path.removeLast()
        XCTAssertNil(LibraryNavigation.detailImageID(in: path))

        path = LibraryNavigation.path(toImage: firstID)
        XCTAssertEqual(LibraryNavigation.detailImageID(in: path), firstID)
    }

    func testImageCellClickCountsProduceConsistentSelectionAndDetailActions() {
        XCTAssertEqual(ImageCellInteraction.actions(forClickCount: 0), [])
        XCTAssertEqual(ImageCellInteraction.actions(forClickCount: 1), [.select])
        XCTAssertEqual(
            ImageCellInteraction.actions(forClickCount: 2),
            [.select, .openDetail]
        )
        XCTAssertEqual(ImageCellInteraction.actions(forClickCount: 3), [.select])

        let repeatedDoubleClickActions = [1, 2, 1, 2]
            .flatMap { ImageCellInteraction.actions(forClickCount: $0) }
        XCTAssertEqual(repeatedDoubleClickActions.filter { $0 == .openDetail }.count, 2)
        XCTAssertEqual(repeatedDoubleClickActions.filter { $0 == .select }.count, 4)
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

    @MainActor
    func testLibraryIndexLoadsCachedEntriesBeforeReconcile() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("microfiche-index-cache-\(UUID().uuidString)")
        let photos = root.appendingPathComponent("Photos", isDirectory: true)
        let persistenceURL = root.appendingPathComponent("library-index.json")
        let imageURL = photos.appendingPathComponent("cached.jpg")
        try fileManager.createDirectory(at: photos, withIntermediateDirectories: true)
        try Data("image".utf8).write(to: imageURL)
        defer { try? fileManager.removeItem(at: root) }

        let folder = makeLinkedFolder(url: photos)
        let store = LibraryIndexStore(
            persistenceURL: persistenceURL,
            watchesFileSystem: false
        )
        store.configure(folders: [folder])
        await store.reconcile(folderID: folder.id)
        XCTAssertEqual(store.files(for: [folder.id]).map(\.url), [imageURL])

        try fileManager.removeItem(at: imageURL)
        let restored = LibraryIndexStore(
            persistenceURL: persistenceURL,
            watchesFileSystem: false
        )
        XCTAssertEqual(restored.files(for: [folder.id]).map(\.name), ["cached.jpg"])
    }

    @MainActor
    func testLibraryIndexReconcileAddsRemovesAndFiltersFiles() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("microfiche-index-reconcile-\(UUID().uuidString)")
        let photos = root.appendingPathComponent("Photos", isDirectory: true)
        let persistenceURL = root.appendingPathComponent("library-index.json")
        let firstImage = photos.appendingPathComponent("one.jpg")
        let ignoredFile = photos.appendingPathComponent("notes.txt")
        try fileManager.createDirectory(at: photos, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: firstImage)
        try Data("ignored".utf8).write(to: ignoredFile)
        defer { try? fileManager.removeItem(at: root) }

        let folder = makeLinkedFolder(url: photos)
        let store = LibraryIndexStore(
            persistenceURL: persistenceURL,
            watchesFileSystem: false
        )
        store.configure(folders: [folder])
        await store.reconcile(folderID: folder.id)
        XCTAssertEqual(store.files(for: [folder.id]).map(\.name), ["one.jpg"])

        try fileManager.removeItem(at: firstImage)
        let secondImage = photos.appendingPathComponent("two.png")
        try Data("two".utf8).write(to: secondImage)
        await store.reconcile(folderID: folder.id)

        XCTAssertEqual(store.files(for: [folder.id]).map(\.name), ["two.png"])
    }

    func testLibraryIndexScannerAppliesChangedSubtreeIncrementally() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("microfiche-index-delta-\(UUID().uuidString)")
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        let oldImage = nested.appendingPathComponent("old.jpg")
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: oldImage)
        defer { try? fileManager.removeItem(at: root) }

        let initial = LibraryIndexScanner.scan(root: root)
        XCTAssertEqual(initial.map(\.path), [oldImage.path])

        try fileManager.removeItem(at: oldImage)
        let newImage = nested.appendingPathComponent("new.png")
        try Data("new".utf8).write(to: newImage)
        let updated = LibraryIndexScanner.applying(
            changedPaths: [nested.path],
            to: initial,
            under: root
        )

        XCTAssertEqual(updated.map(\.path), [newImage.path])
    }

    @MainActor
    func testLibraryIndexLocalRenameUpdatesAndPersistsEntry() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("microfiche-index-rename-\(UUID().uuidString)")
        let photos = root.appendingPathComponent("Photos", isDirectory: true)
        let persistenceURL = root.appendingPathComponent("library-index.json")
        let oldURL = photos.appendingPathComponent("before.jpg")
        let newURL = photos.appendingPathComponent("after.jpg")
        try fileManager.createDirectory(at: photos, withIntermediateDirectories: true)
        try Data("image".utf8).write(to: oldURL)
        defer { try? fileManager.removeItem(at: root) }

        let folder = makeLinkedFolder(url: photos)
        let store = LibraryIndexStore(
            persistenceURL: persistenceURL,
            watchesFileSystem: false
        )
        store.configure(folders: [folder])
        await store.reconcile(folderID: folder.id)
        try fileManager.moveItem(at: oldURL, to: newURL)
        store.move(from: oldURL, to: newURL)

        XCTAssertEqual(store.files(for: [folder.id]).map(\.url), [newURL])
        let restored = LibraryIndexStore(
            persistenceURL: persistenceURL,
            watchesFileSystem: false
        )
        XCTAssertEqual(restored.files(for: [folder.id]).map(\.url), [newURL])
    }

    @MainActor
    func testLibraryIndexRepeatedReconcileDoesNotReplaceUnchangedState() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("microfiche-index-repeat-\(UUID().uuidString)")
        let photos = root.appendingPathComponent("Photos", isDirectory: true)
        let persistenceURL = root.appendingPathComponent("library-index.json")
        let imageURL = photos.appendingPathComponent("keep.jpg")
        try fileManager.createDirectory(at: photos, withIntermediateDirectories: true)
        try Data("image".utf8).write(to: imageURL)
        defer { try? fileManager.removeItem(at: root) }

        let folder = makeLinkedFolder(url: photos)
        let store = LibraryIndexStore(
            persistenceURL: persistenceURL,
            watchesFileSystem: false
        )
        store.configure(folders: [folder])
        await store.reconcile(folderID: folder.id)
        let revisionAfterFirst = store.revision

        await store.reconcile(folderID: folder.id)
        await store.reconcile(folderID: folder.id)

        XCTAssertEqual(store.revision, revisionAfterFirst)
        XCTAssertEqual(store.files(for: [folder.id]).map(\.url), [imageURL])
    }

    @MainActor
    func testLibraryIndexCancelsStaleReconcileAfterLocalMutation() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("microfiche-index-cancel-\(UUID().uuidString)")
        let photos = root.appendingPathComponent("Photos", isDirectory: true)
        let persistenceURL = root.appendingPathComponent("library-index.json")
        let imageURL = photos.appendingPathComponent("stay.jpg")
        try fileManager.createDirectory(at: photos, withIntermediateDirectories: true)
        try Data("image".utf8).write(to: imageURL)
        defer { try? fileManager.removeItem(at: root) }

        let folder = makeLinkedFolder(url: photos)
        let store = LibraryIndexStore(
            persistenceURL: persistenceURL,
            watchesFileSystem: false
        )
        store.configure(folders: [folder])
        await store.reconcile(folderID: folder.id)
        XCTAssertEqual(store.files(for: [folder.id]).map(\.url), [imageURL])

        store.testWillScan = {
            store.remove(urls: [imageURL])
            store.testWillScan = nil
        }
        await store.reconcile(folderID: folder.id)

        XCTAssertEqual(store.files(for: [folder.id]), [])
        XCTAssertTrue(fileManager.fileExists(atPath: imageURL.path))
    }

    @MainActor
    func testLibraryIndexKeepsCachedEntriesWhenFolderIsUnavailable() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("microfiche-index-offline-\(UUID().uuidString)")
        let photos = root.appendingPathComponent("Photos", isDirectory: true)
        let persistenceURL = root.appendingPathComponent("library-index.json")
        let imageURL = photos.appendingPathComponent("cached.jpg")
        try fileManager.createDirectory(at: photos, withIntermediateDirectories: true)
        try Data("image".utf8).write(to: imageURL)
        defer { try? fileManager.removeItem(at: root) }

        let folderID = UUID()
        let available = makeLinkedFolder(id: folderID, url: photos)
        let store = LibraryIndexStore(
            persistenceURL: persistenceURL,
            watchesFileSystem: false
        )
        store.configure(folders: [available])
        await store.reconcile(folderID: folderID)
        XCTAssertEqual(store.files(for: [folderID]).map(\.name), ["cached.jpg"])

        let unavailable = makeLinkedFolder(
            id: folderID,
            url: photos,
            isAvailable: false
        )
        try fileManager.removeItem(at: photos)
        store.configure(folders: [unavailable])
        await store.reconcileAll()

        XCTAssertEqual(store.files(for: [folderID]).map(\.name), ["cached.jpg"])

        try fileManager.createDirectory(at: photos, withIntermediateDirectories: true)
        let restoredImage = photos.appendingPathComponent("restored.jpg")
        try Data("restored".utf8).write(to: restoredImage)
        store.configure(folders: [available])
        await store.reconcile(folderID: folderID)

        XCTAssertEqual(store.files(for: [folderID]).map(\.name), ["restored.jpg"])
    }

    func testLibraryIndexScannerCreateAndDeleteAreIdempotent() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("microfiche-index-events-\(UUID().uuidString)")
        let created = root.appendingPathComponent("created.jpg")
        let deleted = root.appendingPathComponent("deleted.jpg")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("deleted".utf8).write(to: deleted)
        defer { try? fileManager.removeItem(at: root) }

        let initial = LibraryIndexScanner.scan(root: root)
        XCTAssertEqual(Set(initial.map(\.path)), [deleted.path])

        try Data("created".utf8).write(to: created)
        try fileManager.removeItem(at: deleted)

        let firstApply = LibraryIndexScanner.applying(
            changedPaths: [created.path, deleted.path],
            to: initial,
            under: root
        )
        let secondApply = LibraryIndexScanner.applying(
            changedPaths: [created.path, deleted.path],
            to: firstApply,
            under: root
        )

        XCTAssertEqual(Set(firstApply.map(\.path)), [created.path])
        XCTAssertEqual(Set(secondApply.map(\.path)), [created.path])
    }

    private func makeLinkedFolder(
        id: UUID = UUID(),
        url: URL,
        resolvedURL: URL? = nil,
        isAvailable: Bool = true
    ) -> LinkedLibraryFolder {
        LinkedLibraryFolder(
            id: id,
            name: url.lastPathComponent,
            originalPath: url.path,
            volumeIdentifier: nil,
            volumeName: nil,
            isExternal: false,
            addedAt: .now,
            resolvedURL: isAvailable ? (resolvedURL ?? url) : nil
        )
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

    func testLibraryFilteringMatchesNamesTypesAndMetadata() {
        let file = ImageFile(url: URL(fileURLWithPath: "/Photos/sunset.JPG"))
        let metadata = ImageMetadata(
            tags: ["Travel"],
            labels: ["Favorite"],
            comments: "Golden hour",
            whereFrom: "Seattle"
        )

        XCTAssertTrue(LibraryFiltering.matches(
            file: file, metadata: metadata, query: "golden", fileType: "jpg", tag: "travel"
        ))
        XCTAssertTrue(LibraryFiltering.matches(
            file: file, metadata: metadata, query: "Photos", fileType: "", tag: ""
        ))
        XCTAssertFalse(LibraryFiltering.matches(
            file: file, metadata: metadata, query: "golden", fileType: "png", tag: "travel"
        ))
        XCTAssertFalse(LibraryFiltering.matches(
            file: file, metadata: metadata, query: "desert", fileType: "jpg", tag: ""
        ))
    }

    func testLibraryLocationPresentationRecognizesICloudDrivePaths() {
        let url = URL(fileURLWithPath: "/Users/test/Library/Mobile Documents/com~apple~CloudDocs/Photos")
        XCTAssertTrue(LibraryLocationPresentation.isICloudDrivePath(url))
        XCTAssertFalse(LibraryLocationPresentation.isICloudDrivePath(
            URL(fileURLWithPath: "/Users/test/Pictures")
        ))
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

    func testImageLoadStateCoversPlaceholderLoadingFailureCancellationAndRetry() {
        var state = ImageLoadState()
        state.observe(.notDownloaded)
        XCTAssertEqual(state.phase, .placeholder)

        let download = state.begin(for: .notDownloaded)
        XCTAssertEqual(state.phase, .downloading)
        XCTAssertTrue(state.finish(.success(()), requestID: download))
        XCTAssertEqual(state.phase, .loaded)

        let failed = state.begin(for: .local)
        XCTAssertEqual(state.phase, .loading)
        XCTAssertTrue(state.finish(
            .failure(ICloudItemDownloadError.unavailable("Network unavailable")),
            requestID: failed
        ))
        XCTAssertEqual(state.phase, .failed("Network unavailable"))

        let retry = state.begin(for: .downloading)
        XCTAssertEqual(state.phase, .downloading)
        XCTAssertTrue(state.cancel(requestID: retry))
        XCTAssertEqual(state.phase, .cancelled)
        XCTAssertFalse(state.cancel(requestID: retry))

        let finalRetry = state.begin(for: .current)
        XCTAssertFalse(state.finish(.success(()), requestID: failed))
        XCTAssertTrue(state.finish(.success(()), requestID: finalRetry))
        XCTAssertEqual(state.phase, .loaded)
    }

    func testICloudDownloadCoordinatorHandlesSuccessFailureTimeoutAndCancellation() async throws {
        let url = URL(fileURLWithPath: "/tmp/microfiche-icloud-fixture.jpg")
        let successDownloader = StubICloudItemDownloader(states: [
            .notDownloaded, .downloading, .current
        ])
        let success = ICloudItemDownloadCoordinator(
            downloader: successDownloader,
            maxPollAttempts: 4,
            pollInterval: .zero,
            sleep: { _ in }
        )
        try await success.prepareForReading(url)
        try await success.prepareForReading(url)
        XCTAssertEqual(successDownloader.requestCount, 1)

        let failed = ICloudItemDownloadCoordinator(
            downloader: StubICloudItemDownloader(states: [
                .notDownloaded, .failed("iCloud is unavailable")
            ]),
            maxPollAttempts: 2,
            pollInterval: .zero,
            sleep: { _ in }
        )
        do {
            try await failed.prepareForReading(url)
            XCTFail("Expected an iCloud failure")
        } catch {
            XCTAssertEqual(
                error as? ICloudItemDownloadError,
                .unavailable("iCloud is unavailable")
            )
        }

        let timedOut = ICloudItemDownloadCoordinator(
            downloader: StubICloudItemDownloader(states: [.notDownloaded]),
            maxPollAttempts: 2,
            pollInterval: .zero,
            sleep: { _ in }
        )
        do {
            try await timedOut.prepareForReading(url)
            XCTFail("Expected an iCloud timeout")
        } catch {
            XCTAssertEqual(error as? ICloudItemDownloadError, .timedOut)
        }

        let cancelled = ICloudItemDownloadCoordinator(
            downloader: StubICloudItemDownloader(states: [.notDownloaded]),
            maxPollAttempts: 2,
            pollInterval: .zero,
            sleep: { _ in throw CancellationError() }
        )
        do {
            try await cancelled.prepareForReading(url)
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
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

    func testRepeatedAndBatchDropsDoNotDuplicateContactSheetImages() throws {
        let fileManager = FileManager.default
        let testDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("microfiche-contact-sheet-batch-\(UUID().uuidString)")
        let firstURL = testDirectory.appendingPathComponent("first.png")
        let secondURL = testDirectory.appendingPathComponent("second.png")
        let pngData = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!

        try fileManager.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        try pngData.write(to: firstURL)
        try pngData.write(to: secondURL)
        defer { try? fileManager.removeItem(at: testDirectory) }

        let storage = ContactSheetStorage(baseDirectory: testDirectory, fileManager: fileManager)
        let sheet = storage.createContactSheet(name: "Batch Drop")

        XCTAssertEqual(storage.addImages(from: [firstURL, secondURL, firstURL], to: sheet.id).count, 2)
        XCTAssertEqual(storage.addImages(from: [firstURL, secondURL], to: sheet.id).count, 2)
        XCTAssertEqual(storage.contactSheets.first?.imageIDs.count, 2)
        XCTAssertEqual(storage.getImages(for: sheet.id).count, 2)

        let reloadedStorage = ContactSheetStorage(baseDirectory: testDirectory, fileManager: fileManager)
        XCTAssertEqual(reloadedStorage.contactSheets.first?.imageIDs.count, 2)
        XCTAssertEqual(reloadedStorage.getImages(for: sheet.id).count, 2)
    }

    func testDraggingStoredContactSheetImageToAnotherSheetReusesItsRecord() throws {
        let fileManager = FileManager.default
        let testDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("microfiche-contact-sheet-reuse-\(UUID().uuidString)")
        let sourceURL = testDirectory.appendingPathComponent("source.png")
        let pngData = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!

        try fileManager.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        try pngData.write(to: sourceURL)
        defer { try? fileManager.removeItem(at: testDirectory) }

        let storage = ContactSheetStorage(baseDirectory: testDirectory, fileManager: fileManager)
        let firstSheet = storage.createContactSheet(name: "First")
        let secondSheet = storage.createContactSheet(name: "Second")
        let firstID = try XCTUnwrap(storage.addImage(from: sourceURL, to: firstSheet.id))
        let storedURL = try XCTUnwrap(storage.getImage(byID: firstID)?.storedURL)
        let secondID = try XCTUnwrap(storage.addImage(from: storedURL, to: secondSheet.id))

        XCTAssertEqual(secondID, firstID)
        XCTAssertEqual(storage.getImages(for: firstSheet.id).count, 1)
        XCTAssertEqual(storage.getImages(for: secondSheet.id).count, 1)
    }

    func testContactSheetExportRecordsPreserveOrderWhenStoredImageIsMissing() throws {
        let fileManager = FileManager.default
        let testDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("microfiche-contact-sheet-export-records-\(UUID().uuidString)")
        let firstURL = testDirectory.appendingPathComponent("first.png")
        let secondURL = testDirectory.appendingPathComponent("second.png")
        let pngData = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!

        try fileManager.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        try pngData.write(to: firstURL)
        try pngData.write(to: secondURL)
        defer { try? fileManager.removeItem(at: testDirectory) }

        let storage = ContactSheetStorage(baseDirectory: testDirectory, fileManager: fileManager)
        let sheet = storage.createContactSheet(name: "Export Order")
        XCTAssertEqual(storage.addImages(from: [firstURL, secondURL], to: sheet.id).count, 2)

        let records = storage.getImageRecords(for: sheet.id)
        XCTAssertEqual(records.map(\.fileName), ["first.png", "second.png"])
        try fileManager.removeItem(at: records[0].storedURL)

        let recordsAfterRemoval = storage.getImageRecords(for: sheet.id)
        XCTAssertEqual(recordsAfterRemoval.map(\.fileName), ["first.png", "second.png"])
        XCTAssertFalse(fileManager.fileExists(atPath: recordsAfterRemoval[0].storedURL.path))
    }

    func testContactSheetPDFLayoutSupportsPaperOrientationMarginsAndPagination() {
        var portraitOptions = ContactSheetExportOptions()
        portraitOptions.paperSize = .letter
        portraitOptions.orientation = .portrait
        portraitOptions.columns = 4
        portraitOptions.margin = 36
        let portrait = ContactSheetPDFLayout(itemCount: 1, options: portraitOptions)

        XCTAssertEqual(portrait.pageSize.width, 612, accuracy: 0.01)
        XCTAssertEqual(portrait.pageSize.height, 792, accuracy: 0.01)
        XCTAssertEqual(portrait.columns, 4)
        XCTAssertGreaterThanOrEqual(portrait.rowsPerPage, 1)

        let multiPage = ContactSheetPDFLayout(
            itemCount: portrait.itemsPerPage + 1,
            options: portraitOptions
        )
        XCTAssertEqual(multiPage.pageCount, 2)

        var landscapeOptions = portraitOptions
        landscapeOptions.paperSize = .a4
        landscapeOptions.orientation = .landscape
        landscapeOptions.columns = 6
        landscapeOptions.margin = 72
        let landscape = ContactSheetPDFLayout(itemCount: 1, options: landscapeOptions)

        XCTAssertEqual(landscape.pageSize.width, 841.89, accuracy: 0.01)
        XCTAssertEqual(landscape.pageSize.height, 595.28, accuracy: 0.01)
        XCTAssertEqual(landscape.columns, 6)
        XCTAssertEqual(landscape.contentRect.minX, 72, accuracy: 0.01)
        let firstItemRect = landscape.itemRect(at: 0)
        XCTAssertGreaterThanOrEqual(firstItemRect.minX, landscape.contentRect.minX - 0.01)
        XCTAssertLessThanOrEqual(firstItemRect.maxX, landscape.contentRect.maxX + 0.01)
        XCTAssertGreaterThanOrEqual(firstItemRect.minY, landscape.contentRect.minY - 0.01)
        XCTAssertLessThanOrEqual(firstItemRect.maxY, landscape.contentRect.maxY + 0.01)

        var normalizedOptions = portraitOptions
        normalizedOptions.margin = 500
        normalizedOptions.columns = 99
        XCTAssertEqual(normalizedOptions.normalized.margin, 72)
        XCTAssertEqual(normalizedOptions.normalized.columns, 6)
    }

    func testContactSheetPDFExporterRendersEmptyAndMissingImageStates() throws {
        let emptyExport = try ContactSheetPDFExporter.render(
            title: "Empty Sheet",
            items: [],
            options: ContactSheetExportOptions()
        )
        let emptyDocument = try XCTUnwrap(PDFDocument(data: emptyExport.data))

        XCTAssertEqual(emptyDocument.pageCount, 1)
        XCTAssertTrue(emptyDocument.string?.contains("No images in this contact sheet") == true)
        XCTAssertTrue(emptyExport.unavailableImageNames.isEmpty)

        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).jpg")
        let missingItem = ContactSheetExportItem(
            id: UUID(),
            fileName: "offline-photo.jpg",
            imageURL: missingURL,
            finderLabel: nil,
            tags: [],
            comments: "",
            source: ""
        )
        let missingExport = try ContactSheetPDFExporter.render(
            title: "Offline Sheet",
            items: [missingItem],
            options: ContactSheetExportOptions()
        )
        let missingDocument = try XCTUnwrap(PDFDocument(data: missingExport.data))

        XCTAssertEqual(missingDocument.pageCount, 1)
        XCTAssertEqual(missingExport.unavailableImageNames, ["offline-photo.jpg"])
        XCTAssertTrue(missingDocument.string?.contains("Image unavailable") == true)
        XCTAssertTrue(missingDocument.string?.contains("offline-photo.jpg") == true)
    }

    func testContactSheetPDFExporterIncludesMetadataAcrossRepeatedMultiPageExports() throws {
        let fileManager = FileManager.default
        let imageURL = fileManager.temporaryDirectory
            .appendingPathComponent("microfiche-pdf-export-\(UUID().uuidString).png")
        let pngData = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
        try pngData.write(to: imageURL)
        defer { try? fileManager.removeItem(at: imageURL) }

        var options = ContactSheetExportOptions()
        options.columns = 2
        options.captions = ContactSheetCaptionOptions(
            includesFilename: true,
            includesFinderLabel: true,
            includesTags: true,
            includesComments: true,
            includesSource: true
        )
        let layout = ContactSheetPDFLayout(itemCount: 1, options: options)
        let itemCount = layout.itemsPerPage + 1
        let items = (0..<itemCount).map { index in
            ContactSheetExportItem(
                id: UUID(),
                fileName: "photo-\(index).png",
                imageURL: imageURL,
                finderLabel: "Orange",
                tags: ["keeper", "portrait"],
                comments: "Looks\n good",
                source: "Camera roll"
            )
        }

        for _ in 0..<2 {
            let export = try ContactSheetPDFExporter.render(
                title: "Repeated Export",
                items: items,
                options: options
            )
            let document = try XCTUnwrap(PDFDocument(data: export.data))
            let extractedText = document.string ?? ""

            XCTAssertEqual(document.pageCount, 2)
            XCTAssertTrue(export.unavailableImageNames.isEmpty)
            XCTAssertTrue(extractedText.contains("photo-0.png"))
            XCTAssertTrue(extractedText.contains("Label: Orange"))
            XCTAssertTrue(extractedText.contains("Tags: keeper, portrait"))
            XCTAssertTrue(extractedText.contains("Comments: Looks good"))
            XCTAssertTrue(extractedText.contains("Source: Camera roll"))
        }
    }

    func testContactSheetExportPreviewStateRejectsStaleResultsAndSupportsRetryAndCancellation() {
        var state = ContactSheetExportPreviewState()
        let options = ContactSheetExportOptions()
        let export = ContactSheetPDFExport(
            data: Data([0x25, 0x50, 0x44, 0x46]),
            layout: ContactSheetPDFLayout(itemCount: 0, options: options),
            unavailableImageNames: []
        )

        let firstRequest = state.beginLoading()
        let secondRequest = state.beginLoading()
        XCTAssertFalse(state.finish(.success(export), requestID: firstRequest))
        XCTAssertEqual(state.phase, .loading)
        XCTAssertTrue(state.finish(.success(export), requestID: secondRequest))
        XCTAssertEqual(state.phase, .ready(export))

        let failedRequest = state.beginLoading()
        XCTAssertTrue(state.finish(.failure(.unableToCreateContext), requestID: failedRequest))
        guard case .failed(let message) = state.phase else {
            return XCTFail("Expected failed preview state")
        }
        XCTAssertFalse(message.isEmpty)

        let retryRequest = state.beginLoading()
        XCTAssertEqual(state.phase, .loading)
        XCTAssertTrue(state.cancel(requestID: retryRequest))
        XCTAssertEqual(state.phase, .idle)
        XCTAssertFalse(state.cancel(requestID: retryRequest))
    }

    func testContactSheetExportSuggestedFilenameIsPortable() {
        XCTAssertEqual(
            ContactSheetPDFExporter.suggestedFilename(for: "Client Review / Finals"),
            "Client-Review-Finals.pdf"
        )
        XCTAssertEqual(ContactSheetPDFExporter.suggestedFilename(for: "///"), "Contact-Sheet.pdf")
    }

    func testContactSheetCaptionOptionsCanHideOrShowEveryMetadataField() {
        let item = ContactSheetExportItem(
            id: UUID(),
            fileName: "selected.jpg",
            imageURL: URL(fileURLWithPath: "/tmp/selected.jpg"),
            finderLabel: "Purple",
            tags: ["hero", "approved"],
            comments: "Line one\nline two",
            source: "Campaign library"
        )
        let hidden = ContactSheetCaptionOptions(
            includesFilename: false,
            includesFinderLabel: false,
            includesTags: false,
            includesComments: false,
            includesSource: false
        )
        let shown = ContactSheetCaptionOptions(
            includesFilename: true,
            includesFinderLabel: true,
            includesTags: true,
            includesComments: true,
            includesSource: true
        )

        XCTAssertTrue(item.captionLines(using: hidden).isEmpty)
        XCTAssertEqual(
            item.captionLines(using: shown),
            [
                "selected.jpg",
                "Label: Purple",
                "Tags: hero, approved",
                "Comments: Line one line two",
                "Source: Campaign library"
            ]
        )

        var hiddenOptions = ContactSheetExportOptions()
        hiddenOptions.captions = hidden
        XCTAssertEqual(
            ContactSheetPDFLayout(itemCount: 1, options: hiddenOptions).captionHeight,
            0
        )
    }

    func testImageDropPayloadLoadsMultipleFileURLsOnceInProviderOrder() throws {
        let firstURL = URL(fileURLWithPath: "/tmp/microfiche-first.png")
        let secondURL = URL(fileURLWithPath: "/tmp/microfiche-second.png")
        let expectation = expectation(description: "drop payload loads")

        ImageDropSupport.loadFileURLs(
            from: [
                ImageDropSupport.itemProvider(for: firstURL),
                ImageDropSupport.itemProvider(for: secondURL),
                ImageDropSupport.itemProvider(for: firstURL)
            ]
        ) { urls in
            XCTAssertEqual(urls, [firstURL, secondURL])
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 3)
    }

    func testImageDropPayloadRejectsUnsupportedProvider() {
        let provider = NSItemProvider(object: "not a file URL" as NSString)
        XCTAssertFalse(ImageDropSupport.canLoadFileURL(from: [provider]))

        let expectation = expectation(description: "unsupported payload completes empty")
        ImageDropSupport.loadFileURLs(from: [provider]) { urls in
            XCTAssertTrue(urls.isEmpty)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3)
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

    func testFinderLabelMigratesLegacyColorNames() {
        XCTAssertEqual(FinderLabel.migrating(from: ["Red"]), .red)
        XCTAssertEqual(FinderLabel.migrating(from: ["  orange "]), .orange)
        XCTAssertEqual(FinderLabel.migrating(from: ["favorite", "Blue"]), .blue)
        XCTAssertNil(FinderLabel.migrating(from: ["favorite", "keeper"]))
        XCTAssertEqual(FinderLabel(labelNumber: 7), .red)
        XCTAssertEqual(FinderLabel(labelNumber: nil), .none)
    }

    func testNativeFileMetadataRoundTripsLabelTagsAndComment() throws {
        let fileManager = FileManager.default
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("microfiche-native-meta-\(UUID().uuidString).txt")
        try "sample".write(to: url, atomically: true, encoding: .utf8)
        defer { try? fileManager.removeItem(at: url) }

        let expected = NativeFileMetadata(
            label: .orange,
            tagNames: ["keeper", "portrait"],
            comment: "Looks good"
        )
        try NativeFileMetadataService.save(expected, for: url)

        let loaded = NativeFileMetadataService.load(from: url)
        XCTAssertEqual(loaded.label, .orange)
        XCTAssertEqual(loaded.tagNames, ["keeper", "portrait"])
        XCTAssertEqual(loaded.comment, "Looks good")

        try NativeFileMetadataService.setLabel(.none, for: url)
        try NativeFileMetadataService.setTagNames([], for: url)
        try NativeFileMetadataService.setComment("", for: url)

        let cleared = NativeFileMetadataService.load(from: url)
        XCTAssertEqual(cleared.label, .none)
        XCTAssertTrue(cleared.tagNames.isEmpty)
        XCTAssertTrue(cleared.comment.isEmpty)
    }

    func testBatchMetadataSummaryDetectsSharedMixedAndEmptyValues() {
        let empty = ResolvedImageMetadata(
            label: .none, tags: [], comments: "", whereFrom: ""
        )
        let red = ResolvedImageMetadata(
            label: .red,
            tags: ["Travel", "Keep"],
            comments: "Golden hour",
            whereFrom: "Seattle"
        )
        let blue = ResolvedImageMetadata(
            label: .blue,
            tags: ["Travel"],
            comments: "Golden hour",
            whereFrom: "Portland"
        )

        let one = BatchMetadataAggregation.summarize([red])
        XCTAssertEqual(one.fileCount, 1)
        XCTAssertEqual(one.label, .shared(.red))
        XCTAssertEqual(one.sharedTags, ["Keep", "Travel"])
        XCTAssertTrue(one.mixedTags.isEmpty)
        XCTAssertEqual(one.comments, .shared("Golden hour"))
        XCTAssertEqual(one.whereFrom, .shared("Seattle"))

        let mixed = BatchMetadataAggregation.summarize([red, blue])
        XCTAssertEqual(mixed.label, .mixed)
        XCTAssertEqual(mixed.sharedTags, ["Travel"])
        XCTAssertEqual(mixed.mixedTags, ["Keep"])
        XCTAssertEqual(mixed.comments, .shared("Golden hour"))
        XCTAssertEqual(mixed.whereFrom, .mixed)

        let empties = BatchMetadataAggregation.summarize([empty, empty])
        XCTAssertEqual(empties.label, .empty)
        XCTAssertTrue(empties.sharedTags.isEmpty)
        XCTAssertEqual(empties.comments, .empty)
        XCTAssertEqual(empties.whereFrom, .empty)
    }

    @MainActor
    func testBatchMetadataWriterCoversSingleMultipleRepeatedPartialFailureAndCancellation() async throws {
        enum WriteError: Error { case boom }

        let first = URL(fileURLWithPath: "/tmp/batch-a.jpg")
        let second = URL(fileURLWithPath: "/tmp/batch-b.jpg")
        let missing = URL(fileURLWithPath: "/tmp/batch-missing.jpg")
        let firstPath = ImageIdentity.normalizedPath(for: first)
        let secondPath = ImageIdentity.normalizedPath(for: second)

        var records: [String: ResolvedImageMetadata] = [
            firstPath: ResolvedImageMetadata(
                label: .none, tags: ["Keep"], comments: "One", whereFrom: "A"
            ),
            secondPath: ResolvedImageMetadata(
                label: .red, tags: ["Travel"], comments: "Two", whereFrom: "B"
            )
        ]
        var failing = Set<String>()
        var missingPaths = Set<String>()
        var writer = BatchMetadataWriter(
            loadResolved: { url in
                records[ImageIdentity.normalizedPath(for: url)]
                    ?? ResolvedImageMetadata(
                        label: .none, tags: [], comments: "", whereFrom: ""
                    )
            },
            save: { resolved, url in
                let path = ImageIdentity.normalizedPath(for: url)
                if failing.contains(path) {
                    throw WriteError.boom
                }
                records[path] = resolved
            },
            fileExists: { url in
                !missingPaths.contains(ImageIdentity.normalizedPath(for: url))
            }
        )

        let single = await writer.apply(.setLabel(.blue), to: [first])
        XCTAssertEqual(single.succeededPaths, [firstPath])
        XCTAssertEqual(records[firstPath]?.label, .blue)

        let added = await writer.apply(.addTag("Travel"), to: [first, second])
        XCTAssertEqual(Set(added.succeededPaths), [firstPath, secondPath])
        XCTAssertEqual(records[firstPath]?.tags.sorted(), ["Keep", "Travel"])
        XCTAssertEqual(records[secondPath]?.tags, ["Travel"])

        let repeated = await writer.apply(.addTag("Travel"), to: [first, second])
        XCTAssertEqual(Set(repeated.succeededPaths), [firstPath, secondPath])
        XCTAssertEqual(records[firstPath]?.tags.sorted(), ["Keep", "Travel"])

        let removed = await writer.apply(.removeTag("Keep"), to: [first, second])
        XCTAssertEqual(Set(removed.succeededPaths), [firstPath, secondPath])
        XCTAssertEqual(records[firstPath]?.tags, ["Travel"])
        XCTAssertEqual(records[secondPath]?.tags, ["Travel"])

        let replaced = await writer.apply(.replaceComments("Shared"), to: [first, second])
        XCTAssertEqual(replaced.succeededPaths.count, 2)
        XCTAssertEqual(records[firstPath]?.comments, "Shared")
        XCTAssertEqual(records[secondPath]?.comments, "Shared")
        XCTAssertEqual(records[firstPath]?.whereFrom, "A")

        failing = [secondPath]
        let partial = await writer.apply(.replaceWhereFrom("Studio"), to: [first, second])
        XCTAssertEqual(partial.succeededPaths, [firstPath])
        XCTAssertEqual(partial.failures.map(\.path), [secondPath])
        XCTAssertEqual(records[firstPath]?.whereFrom, "Studio")
        XCTAssertEqual(records[secondPath]?.whereFrom, "B")
        XCTAssertNotNil(partial.errorMessage)

        missingPaths = [ImageIdentity.normalizedPath(for: missing)]
        let skipped = await writer.apply(.setLabel(.green), to: [first, missing])
        XCTAssertEqual(skipped.succeededPaths, [firstPath])
        XCTAssertEqual(skipped.skippedMissingPaths, [ImageIdentity.normalizedPath(for: missing)])
        XCTAssertEqual(records[firstPath]?.label, .green)

        var cancelRequested = false
        writer.beforeSave = { _ in
            cancelRequested = true
        }
        writer.isCancelled = { cancelRequested }
        let cancelled = await writer.apply(.setLabel(.orange), to: [first, second])
        XCTAssertTrue(cancelled.wasCancelled)
        XCTAssertTrue(cancelled.succeededPaths.isEmpty)
        XCTAssertEqual(records[firstPath]?.label, .green)
        XCTAssertEqual(records[secondPath]?.label, .red)
    }

    func testPhotoMetadataReaderReadsPNGDimensionsAndReportsMissingFiles() throws {
        let pngData = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("microfiche-photo-metadata-\(UUID().uuidString).png")
        try pngData.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let metadata = try XCTUnwrap(PhotoMetadataReader.read(from: url))
        XCTAssertEqual(metadata.dimensions, "1 × 1")

        try FileManager.default.removeItem(at: url)
        XCTAssertThrowsError(try PhotoMetadataReader.read(from: url)) { error in
            XCTAssertEqual(error as? PhotoMetadataReaderError, .fileUnavailable)
        }
    }

    func testPhotoMetadataLoadStateCoversRepeatedStaleEmptyFailureAndCancellation() {
        let available = PhotoTechnicalMetadata(
            dimensions: "100 × 200",
            captured: nil,
            camera: nil,
            lens: nil,
            iso: nil,
            aperture: nil,
            shutterSpeed: nil
        )
        var state = PhotoTechnicalMetadataLoadState()

        let staleRequest = state.beginLoading()
        XCTAssertEqual(state.phase, .loading)

        let currentRequest = state.beginLoading()
        XCTAssertFalse(state.finish(.success(available), requestID: staleRequest))
        XCTAssertEqual(state.phase, .loading)
        XCTAssertTrue(state.finish(.success(available), requestID: currentRequest))
        XCTAssertEqual(state.phase, .available(available))

        let emptyRequest = state.beginLoading()
        XCTAssertTrue(state.finish(.success(nil), requestID: emptyRequest))
        XCTAssertEqual(state.phase, .unavailable)

        let failedRequest = state.beginLoading()
        XCTAssertTrue(state.finish(.failure("Unreadable"), requestID: failedRequest))
        XCTAssertEqual(state.phase, .failed("Unreadable"))

        let cancelledRequest = state.beginLoading()
        XCTAssertTrue(state.cancel(requestID: cancelledRequest))
        XCTAssertEqual(state.phase, .idle)
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

    @MainActor
    func testUserPreferencesDefaultsEnableOnboardingUntilCompleted() {
        let suiteName = "microfiche.tests.onboarding.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = UserPreferences(defaults: defaults)

        XCTAssertTrue(preferences.isOnboardingEnabled)
        XCTAssertFalse(preferences.hasCompletedOnboarding)
        XCTAssertTrue(preferences.shouldPresentOnboarding)

        preferences.evaluateLaunchPresentation()
        XCTAssertTrue(preferences.isPresentingOnboarding)

        preferences.completeOnboarding()
        XCTAssertTrue(preferences.hasCompletedOnboarding)
        XCTAssertFalse(preferences.isPresentingOnboarding)
        XCTAssertFalse(preferences.shouldPresentOnboarding)
    }

    @MainActor
    func testUserPreferencesTestingToggleAndReplay() {
        let suiteName = "microfiche.tests.onboarding-toggle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = UserPreferences(defaults: defaults)
        preferences.completeOnboarding()

        preferences.isOnboardingEnabled = false
        XCTAssertFalse(preferences.isPresentingOnboarding)
        preferences.replayOnboarding()
        XCTAssertFalse(preferences.isPresentingOnboarding)
        XCTAssertTrue(preferences.hasCompletedOnboarding)

        preferences.isOnboardingEnabled = true
        preferences.replayOnboarding()
        XCTAssertFalse(preferences.hasCompletedOnboarding)
        XCTAssertTrue(preferences.isPresentingOnboarding)
        XCTAssertTrue(preferences.shouldPresentOnboarding)
    }

    func testOnboardingSequenceCoversValueProposition() {
        let steps = OnboardingStep.all
        XCTAssertEqual(steps.count, 4)
        XCTAssertEqual(steps.map(\.id), ["welcome", "folders", "contact-sheets", "metadata"])
        XCTAssertEqual(steps.map(\.title), [
            "Your library, left in place",
            "Link folders and drives",
            "Keep selects on Contact Sheets",
            "Labels, tags, and comments"
        ])
        XCTAssertTrue(steps[0].message.contains("No import, no copies"))
        XCTAssertTrue(steps[1].message.contains("iCloud Drive"))
        XCTAssertTrue(steps[2].message.contains("offline"))
        XCTAssertTrue(steps[3].message.contains("Finder"))
        XCTAssertTrue(steps.allSatisfy { !$0.title.isEmpty && !$0.message.isEmpty && !$0.symbolName.isEmpty })
    }

    func testFileArchiverUniqueDestinationAvoidsCollisions() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("microfiche-archive-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent("archive", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let source = root.appendingPathComponent("photo.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: source)

        let first = FileArchiver.uniqueDestination(for: source, in: directory, fileManager: fileManager)
        XCTAssertEqual(first.lastPathComponent, "photo.png")

        try Data([0x01]).write(to: first)
        let second = FileArchiver.uniqueDestination(for: source, in: directory, fileManager: fileManager)
        XCTAssertEqual(second.lastPathComponent, "photo-1.png")

        try Data([0x02]).write(to: second)
        let third = FileArchiver.uniqueDestination(for: source, in: directory, fileManager: fileManager)
        XCTAssertEqual(third.lastPathComponent, "photo-2.png")
    }

    func testFileArchiverMovesIntoArchiveFolder() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("microfiche-archive-move-\(UUID().uuidString)", isDirectory: true)
        let library = root.appendingPathComponent("library", isDirectory: true)
        let archive = root.appendingPathComponent("archive", isDirectory: true)
        try fileManager.createDirectory(at: library, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: archive, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let source = library.appendingPathComponent("keep.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: source)

        let destination = try FileArchiver.move(source, intoArchive: archive, fileManager: fileManager)
        XCTAssertEqual(destination.deletingLastPathComponent(), archive)
        XCTAssertFalse(fileManager.fileExists(atPath: source.path))
        XCTAssertTrue(fileManager.fileExists(atPath: destination.path))
    }

    @MainActor
    func testArchiveFolderStorePersistsChosenFolder() throws {
        let suiteName = "microfiche.tests.archive-folder.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory
            .appendingPathComponent("microfiche-archive-store-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: folder) }

        let store = ArchiveFolderStore(defaults: defaults, fileManager: fileManager)
        XCTAssertFalse(store.hasConfiguredFolder)

        XCTAssertTrue(store.setFolder(folder))
        XCTAssertTrue(store.hasConfiguredFolder)
        XCTAssertTrue(store.isAvailable)
        XCTAssertEqual(store.displayName, folder.lastPathComponent)
        XCTAssertEqual(
            store.resolvedURL()?.standardizedFileURL.resolvingSymlinksInPath(),
            folder.standardizedFileURL.resolvingSymlinksInPath()
        )

        let restored = ArchiveFolderStore(defaults: defaults, fileManager: fileManager)
        XCTAssertTrue(restored.hasConfiguredFolder)
        XCTAssertEqual(
            restored.resolvedURL()?.standardizedFileURL.resolvingSymlinksInPath(),
            folder.standardizedFileURL.resolvingSymlinksInPath()
        )

        restored.clearFolder()
        XCTAssertFalse(restored.hasConfiguredFolder)
        XCTAssertNil(restored.resolvedURL())
    }

}

private final class StubICloudItemDownloader: ICloudItemDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private var states: [ICloudItemState]
    private(set) var requestCount = 0

    init(states: [ICloudItemState]) {
        self.states = states
    }

    func state(for url: URL) -> ICloudItemState {
        lock.withLock {
            guard states.count > 1 else { return states.first ?? .local }
            return states.removeFirst()
        }
    }

    func requestDownload(for url: URL) throws {
        lock.withLock {
            requestCount += 1
        }
    }
}
