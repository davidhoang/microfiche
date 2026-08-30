//
//  UITestFixture.swift
//  Microfiche
//

#if DEBUG
import Foundation

@MainActor
struct UITestFixture {
    let libraryStorage: LibraryStorage
    let contactSheetStorage: ContactSheetStorage
    let userPreferences: UserPreferences
    let archiveFolderStore: ArchiveFolderStore
    let libraryIndex: LibraryIndexStore

    static func make() -> UITestFixture {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("microfiche-ui-fixture-\(UUID().uuidString)", isDirectory: true)
        let photos = root.appendingPathComponent("Photos", isDirectory: true)
        try? fileManager.createDirectory(at: photos, withIntermediateDirectories: true)

        let pngData = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
        let imageURLs = (1...24).map { index in
            let url = photos.appendingPathComponent(
                String(format: "fixture-%02d.png", index)
            )
            try? pngData.write(to: url)
            return url
        }

        let defaultsName = "MicroficheUITests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsName)!
        defaults.removePersistentDomain(forName: defaultsName)
        defaults.set(false, forKey: "isOnboardingEnabled")
        defaults.set(true, forKey: "hasCompletedOnboarding")

        let libraryStorage = LibraryStorage(
            persistenceURL: root.appendingPathComponent("library.json"),
            fileManager: fileManager,
            observesWorkspace: false
        )
        _ = libraryStorage.addFolders([photos])

        let contactSheetStorage = ContactSheetStorage(
            baseDirectory: root.appendingPathComponent("ContactSheets"),
            fileManager: fileManager
        )
        let firstSheet = contactSheetStorage.createContactSheet(name: "First Review")
        let secondSheet = contactSheetStorage.createContactSheet(name: "Second Review")
        _ = contactSheetStorage.addImages(
            from: Array(imageURLs.prefix(4)),
            to: firstSheet.id
        )
        _ = contactSheetStorage.addImages(
            from: Array(imageURLs[4..<8]),
            to: secondSheet.id
        )

        return UITestFixture(
            libraryStorage: libraryStorage,
            contactSheetStorage: contactSheetStorage,
            userPreferences: UserPreferences(defaults: defaults),
            archiveFolderStore: ArchiveFolderStore(
                defaults: defaults,
                fileManager: fileManager
            ),
            libraryIndex: LibraryIndexStore(
                persistenceURL: root.appendingPathComponent("library-index.json"),
                fileManager: fileManager,
                watchesFileSystem: false
            )
        )
    }
}
#endif
