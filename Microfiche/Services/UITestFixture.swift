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
        do {
            try fileManager.createDirectory(at: photos, withIntermediateDirectories: true)
        } catch {
            preconditionFailure("Unable to create UI test fixture: \(error)")
        }

        let pngData = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
        let imageURLs = (1...24).map { index in
            let url = photos.appendingPathComponent(
                String(format: "fixture-%02d.png", index)
            )
            do {
                try pngData.write(to: url)
            } catch {
                preconditionFailure("Unable to write UI test image: \(error)")
            }
            return url
        }
        precondition(imageURLs.allSatisfy {
            fileManager.fileExists(atPath: $0.path)
        })

        let arguments = ProcessInfo.processInfo.arguments
        let defaultsName: String
        if let markerIndex = arguments.firstIndex(of: "--ui-testing-defaults-suite"),
           arguments.indices.contains(markerIndex + 1) {
            defaultsName = arguments[markerIndex + 1]
        } else {
            defaultsName = "MicroficheUITests.\(UUID().uuidString)"
        }
        let defaults = UserDefaults(suiteName: defaultsName)!
        defaults.set(false, forKey: "isOnboardingEnabled")
        defaults.set(true, forKey: "hasCompletedOnboarding")

        let libraryStorage = LibraryStorage(
            persistenceURL: root.appendingPathComponent("library.json"),
            fileManager: fileManager,
            observesWorkspace: false
        )
        let addedLocations = libraryStorage.addFolders([photos])
        precondition(
            addedLocations.folders.count == 1,
            "UI test fixture folder could not be linked"
        )

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
        precondition(
            contactSheetStorage.contactSheets.count == 2
                && contactSheetStorage.getImages(for: firstSheet.id).count == 4
                && contactSheetStorage.getImages(for: secondSheet.id).count == 4,
            "UI test contact sheets were not seeded"
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
