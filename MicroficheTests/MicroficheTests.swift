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
        XCTAssertEqual(store.resolvedURL()?.path, folder.path)

        let restored = ArchiveFolderStore(defaults: defaults, fileManager: fileManager)
        XCTAssertTrue(restored.hasConfiguredFolder)
        XCTAssertEqual(restored.resolvedURL()?.path, folder.path)

        restored.clearFolder()
        XCTAssertFalse(restored.hasConfiguredFolder)
        XCTAssertNil(restored.resolvedURL())
    }

}
