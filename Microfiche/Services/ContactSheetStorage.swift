//
//  ContactSheetStorage.swift
//  Microfiche
//
//  Created by Claude on 12/28/25.
//

import Foundation
import Combine

class ContactSheetStorage: ObservableObject {
    static let shared = ContactSheetStorage()

    @Published private(set) var contactSheets: [ContactSheet] = []
    private var imageMap: [UUID: ContactSheetImage] = [:]

    private let fileManager: FileManager
    private let baseDirectory: URL
    private let imagesDirectory: URL
    private let metadataURL: URL
    private let imageMapURL: URL

    init(baseDirectory customBaseDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager

        // Set up directories in Application Support
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        baseDirectory = customBaseDirectory ?? appSupport.appendingPathComponent("Microfiche/ContactSheets")
        imagesDirectory = baseDirectory.appendingPathComponent("Images")
        metadataURL = baseDirectory.appendingPathComponent("metadata.json")
        imageMapURL = baseDirectory.appendingPathComponent("images.json")

        // Create directories if they don't exist
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)

        // Load persisted data
        load()
    }

    // MARK: - Contact Sheet Operations

    func createContactSheet(name: String? = nil) -> ContactSheet {
        let generatedName = name ?? generateNextName()
        let contactSheet = ContactSheet(name: generatedName)
        contactSheets.append(contactSheet)
        save()
        return contactSheet
    }

    func deleteContactSheet(id: UUID) {
        guard let index = contactSheets.firstIndex(where: { $0.id == id }) else { return }
        let contactSheet = contactSheets[index]

        // Remove contact sheet
        contactSheets.remove(at: index)

        // Clean up orphaned images
        cleanupOrphanedImages(excludingIDs: contactSheet.imageIDs)

        save()
    }

    func renameContactSheet(id: UUID, newName: String) {
        guard let index = contactSheets.firstIndex(where: { $0.id == id }) else { return }
        contactSheets[index].name = newName
        contactSheets[index].modifiedAt = Date()
        save()
    }

    // MARK: - Image Operations

    func addImage(from sourceURL: URL, to contactSheetID: UUID) -> UUID? {
        addImages(from: [sourceURL], to: contactSheetID).first
    }

    /// Adds a complete drag in one transaction. Existing source or stored URLs
    /// reuse their image record so repeated drops do not create duplicate files.
    func addImages(from sourceURLs: [URL], to contactSheetID: UUID) -> [UUID] {
        guard let index = contactSheets.firstIndex(where: { $0.id == contactSheetID }) else {
            return []
        }

        var importedIDs: [UUID] = []
        var seenPaths = Set<String>()
        var didChange = false
        var updatedContactSheet = contactSheets[index]

        for sourceURL in sourceURLs.map(\.standardizedFileURL) {
            guard seenPaths.insert(sourceURL.path).inserted else { continue }

            if let existingID = existingImageID(for: sourceURL) {
                if !updatedContactSheet.imageIDs.contains(existingID) {
                    updatedContactSheet.addImage(existingID)
                    didChange = true
                }
                importedIDs.append(existingID)
                continue
            }

            guard let contactSheetImage = copyImageToPermanentStorage(from: sourceURL) else {
                continue
            }

            updatedContactSheet.addImage(contactSheetImage.id)
            imageMap[contactSheetImage.id] = contactSheetImage
            importedIDs.append(contactSheetImage.id)
            didChange = true
        }

        if didChange {
            contactSheets[index] = updatedContactSheet
            save()
        }
        return importedIDs
    }

    func removeImage(imageID: UUID, from contactSheetID: UUID) {
        guard let index = contactSheets.firstIndex(where: { $0.id == contactSheetID }) else {
            return
        }

        contactSheets[index].removeImage(imageID)

        // Clean up if image is now orphaned
        cleanupOrphanedImages(excludingIDs: [imageID])

        save()
    }

    func getImage(byID id: UUID) -> ContactSheetImage? {
        return imageMap[id]
    }

    func getImages(for contactSheetID: UUID) -> [ImageFile] {
        guard let contactSheet = contactSheets.first(where: { $0.id == contactSheetID }) else {
            return []
        }

        return contactSheet.imageIDs.compactMap { imageID in
            imageMap[imageID]?.asImageFile
        }
    }

    /// Preserves contact-sheet order and original filenames for portable exports.
    /// Records remain present when a stored file is missing so the exporter can
    /// draw a placeholder and report the unavailable image.
    func getImageRecords(for contactSheetID: UUID) -> [ContactSheetImage] {
        guard let contactSheet = contactSheets.first(where: { $0.id == contactSheetID }) else {
            return []
        }

        return contactSheet.imageIDs.compactMap { imageMap[$0] }
    }

    // MARK: - Private Helpers

    private func existingImageID(for sourceURL: URL) -> UUID? {
        let source = sourceURL.standardizedFileURL
        return imageMap.first { _, image in
            image.originalURL.standardizedFileURL == source
                || image.storedURL.standardizedFileURL == source
        }?.key
    }

    private func copyImageToPermanentStorage(from sourceURL: URL) -> ContactSheetImage? {
        let imageID = UUID()
        let fileExtension = sourceURL.pathExtension
        let destinationURL = imagesDirectory.appendingPathComponent("\(imageID.uuidString).\(fileExtension)")

        do {
            // Copy file to permanent storage
            try fileManager.copyItem(at: sourceURL, to: destinationURL)

            // Create metadata
            let image = ContactSheetImage(
                id: imageID,
                originalURL: sourceURL,
                storedURL: destinationURL
            )

            return image

        } catch {
            print("Error copying image to permanent storage: \(error)")
            return nil
        }
    }

    private func cleanupOrphanedImages(excludingIDs: [UUID]) {
        // Find all image IDs that are referenced by any contact sheet
        var referencedIDs = Set<UUID>()
        for contactSheet in contactSheets {
            referencedIDs.formUnion(contactSheet.imageIDs)
        }

        // Find orphaned images
        let orphanedIDs = Set(imageMap.keys).subtracting(referencedIDs)

        // Delete orphaned image files
        for imageID in orphanedIDs {
            if let image = imageMap[imageID] {
                try? fileManager.removeItem(at: image.storedURL)
                imageMap.removeValue(forKey: imageID)
            }
        }
    }

    private func generateNextName() -> String {
        let existingNumbers = contactSheets.compactMap { sheet -> Int? in
            let name = sheet.name
            if name.hasPrefix("Contact Sheet "),
               let numberString = name.components(separatedBy: "Contact Sheet ").last,
               let number = Int(numberString) {
                return number
            }
            return nil
        }

        let nextNumber = (existingNumbers.max() ?? 0) + 1
        return "Contact Sheet \(nextNumber)"
    }

    // MARK: - Persistence

    func save() {
        do {
            // These files are small, and completing both writes before returning
            // prevents a dropped image from being lost if the app closes shortly
            // after the drop. It also keeps rapid consecutive drops in order.
            let metadataData = try JSONEncoder().encode(contactSheets)
            let imageMapData = try JSONEncoder().encode(Array(imageMap.values))

            try metadataData.write(to: metadataURL, options: .atomic)
            try imageMapData.write(to: imageMapURL, options: .atomic)
        } catch {
            print("Error saving contact sheet data: \(error)")
        }
    }

    private func load() {
        do {
            // Load contact sheets metadata
            if fileManager.fileExists(atPath: metadataURL.path) {
                let metadataData = try Data(contentsOf: metadataURL)
                contactSheets = try JSONDecoder().decode([ContactSheet].self, from: metadataData)
            }

            // Load image map
            if fileManager.fileExists(atPath: imageMapURL.path) {
                let imageMapData = try Data(contentsOf: imageMapURL)
                let images = try JSONDecoder().decode([ContactSheetImage].self, from: imageMapData)
                imageMap = Dictionary(uniqueKeysWithValues: images.map { ($0.id, $0) })
            }

        } catch {
            print("Error loading contact sheet data: \(error)")
            // Start fresh if loading fails
            contactSheets = []
            imageMap = [:]
        }
    }
}
