//
//  ContentView.swift
//  Microfiche
//
//  Created by David Hoang on 6/8/25.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Shared Enums

enum Selection: Hashable {
    case all
    case folder(URL)
    case contactSheet(UUID)
}

enum ViewMode: String, CaseIterable, Identifiable {
    case grid = "Grid"
    case list = "List"
    var id: String { rawValue }
}

enum GridThumbnailSize: String, CaseIterable, Identifiable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
    var id: String { rawValue }

    var pointSize: CGFloat {
        switch self {
        case .small: return 80
        case .medium: return 120
        case .large: return 180
        }
    }
}

enum ArrowDirection {
    case up, down, left, right
}

// MARK: - Content View

struct ContentView: View {
    private enum SidebarLayout {
        static let minimumWidth: CGFloat = 240
        static let idealWidth: CGFloat = 280
        static let maximumWidth: CGFloat = 360
        static let autoCollapseWidth: CGFloat = 220
    }

    @State private var folderURLs: [URL] = []
    @State private var selection: Selection?
    @State private var imageFiles: [ImageFile] = []
    @State private var viewMode: ViewMode = .grid
    @State private var gridThumbnailSize: GridThumbnailSize = .medium
    @State private var selectedImageFileIDs: Set<UUID> = []
    @State private var lastSelectedImageFileID: UUID?
    @State private var showDeleteAlert: Bool = false
    @State private var dontAskAgain: Bool = UserDefaults.standard.bool(forKey: "dontAskDeleteConfirm")
    @State private var pendingDeleteFiles: [ImageFile] = []
    @State private var previewedImageFile: ImageFile?
    @State private var scrollToID: UUID?
    @State private var gridColumnCount: Int = 1
    @State private var detailViewFile: ImageFile?
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all
    @StateObject private var contactSheetStorage = ContactSheetStorage.shared

    let supportedExtensions = ["jpg", "jpeg", "png", "pdf", "svg", "gif", "tiff"]

    var body: some View {
        ZStack {
            if let detailFile = detailViewFile {
                ImageDetailView(file: detailFile) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        detailViewFile = nil
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            } else {
                NavigationSplitView(columnVisibility: $splitViewVisibility) {
                    SidebarView(
                        folderURLs: folderURLs,
                        contactSheets: contactSheetStorage.contactSheets,
                        selection: selection,
                        onWidthChange: handleSidebarWidthChange,
                        onLinkFolder: linkFolder,
                        onSelect: { newSelection in
                            selection = newSelection
                        },
                        onRemoveFolder: removeFolder,
                        onCreateContactSheet: {
                            let newSheet = contactSheetStorage.createContactSheet()
                            selection = .contactSheet(newSheet.id)
                        },
                        onRenameContactSheet: { id, newName in
                            contactSheetStorage.renameContactSheet(id: id, newName: newName)
                        },
                        onDeleteContactSheet: { id in
                            contactSheetStorage.deleteContactSheet(id: id)
                            if selection == .contactSheet(id) {
                                selection = .all
                            }
                        },
                        onDropToContactSheet: { sheetID, urls in
                            handleDropToContactSheet(sheetID: sheetID, urls: urls)
                        }
                    )
                    .navigationSplitViewColumnWidth(
                        min: SidebarLayout.minimumWidth,
                        ideal: SidebarLayout.idealWidth,
                        max: SidebarLayout.maximumWidth
                    )
                } detail: {
                    MainContentView(
                        imageFiles: imageFiles,
                        viewMode: $viewMode,
                        gridThumbnailSize: $gridThumbnailSize,
                        gridColumnCount: $gridColumnCount,
                        selectedImageFileIDs: $selectedImageFileIDs,
                        onSelectImage: handleImageSelection,
                        onDoubleClickImage: handleDoubleClickImage,
                        scrollToID: $scrollToID,
                        onRename: renameFile,
                        contactSheets: contactSheetStorage.contactSheets,
                        onAddToContactSheet: handleAddToContactSheet
                    )
                }
                .navigationTitle("")
                .onChange(of: selection) { _, newValue in
                    switch newValue {
                    case .all:
                        loadImages(from: folderURLs)
                    case .folder(let url):
                        loadImages(from: [url])
                    case .contactSheet(let id):
                        imageFiles = contactSheetStorage.getImages(for: id)
                        let urls = imageFiles.map { $0.url }
                        PreviewImageCache.shared.preloadLibrary(urls: urls, priority: .utility)
                    case .none:
                        imageFiles = []
                    }
                    selectedImageFileIDs = []
                    lastSelectedImageFileID = nil
                }
                .onChange(of: showDeleteAlert) { _, isShowing in
                    if !isShowing {
                        pendingDeleteFiles = []
                    }
                }
                .background(KeyboardEventHandlingView(
                    onDeletePressed: { bypassConfirmation in
                        let filesToDelete = imageFiles.filter { selectedImageFileIDs.contains($0.id) }
                        if !filesToDelete.isEmpty {
                            if bypassConfirmation || dontAskAgain {
                                moveFilesToTrash(filesToDelete)
                            } else {
                                pendingDeleteFiles = filesToDelete
                                showDeleteAlert = true
                            }
                        }
                    },
                    onEscapePressed: {
                        if previewedImageFile != nil {
                            previewedImageFile = nil
                        } else if !selectedImageFileIDs.isEmpty {
                            selectedImageFileIDs = []
                            lastSelectedImageFileID = nil
                        }
                    },
                    onSpacebarPressed: {
                        if previewedImageFile != nil {
                            previewedImageFile = nil
                            return
                        }

                        guard !selectedImageFileIDs.isEmpty else { return }

                        let idToPreview = selectedImageFileIDs.count == 1 ? selectedImageFileIDs.first : lastSelectedImageFileID

                        if let id = idToPreview, let file = imageFiles.first(where: { $0.id == id }) {
                            previewedImageFile = file
                        }
                    },
                    onArrowPressed: handleArrowKey
                ))
                .alert("Move to Trash?", isPresented: $showDeleteAlert) {
                    Button("Move to Trash", role: .destructive) {
                        moveFilesToTrash(pendingDeleteFiles)
                        if dontAskAgain {
                            UserDefaults.standard.set(true, forKey: "dontAskDeleteConfirm")
                        }
                    }
                    .keyboardShortcut(.defaultAction)

                    Button("Cancel", role: .cancel) { }
                } message: {
                    let fileCount = pendingDeleteFiles.count
                    let messageText = fileCount == 1 ?
                        "Are you sure you want to move \(pendingDeleteFiles.first?.name ?? "this file") to the Trash?" :
                        "Are you sure you want to move \(fileCount) items to the Trash?"
                    Text(messageText)
                }

                if let file = previewedImageFile {
                    PreviewView(file: file) {
                        previewedImageFile = nil
                    }
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: detailViewFile)
        .animation(.easeInOut(duration: 0.08), value: previewedImageFile)
    }

    // MARK: - Folder Management

    private func linkFolder() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = true

        if openPanel.runModal() == .OK {
            var added = false
            for url in openPanel.urls {
                if !folderURLs.contains(url) {
                    folderURLs.append(url)
                    added = true
                }
            }
            if selection == nil, let firstURL = openPanel.urls.first {
                selection = .folder(firstURL)
            }
            if added {
                loadImages(from: folderURLs)
            }
        }
    }

    private func removeFolder(_ url: URL) {
        if let index = folderURLs.firstIndex(of: url) {
            let wasSelected = (selection == .folder(url))
            folderURLs.remove(at: index)

            if wasSelected {
                if !folderURLs.isEmpty {
                    let newIndex = min(index, folderURLs.count - 1)
                    selection = .folder(folderURLs[newIndex])
                } else {
                    selection = .all
                }
            }
        }
    }

    private func handleSidebarWidthChange(_ width: CGFloat) {
        guard splitViewVisibility != .detailOnly else { return }

        if width < SidebarLayout.autoCollapseWidth {
            withAnimation(.easeInOut(duration: 0.2)) {
                splitViewVisibility = .detailOnly
            }
        }
    }

    // MARK: - Contact Sheets

    private func handleDropToContactSheet(sheetID: UUID, urls: [URL]) {
        for url in urls {
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else { continue }
            _ = contactSheetStorage.addImage(from: url, to: sheetID)
        }

        if selection == .contactSheet(sheetID) {
            imageFiles = contactSheetStorage.getImages(for: sheetID)
        }
    }

    private func handleAddToContactSheet(sheetID: UUID, imageURL: URL) {
        guard supportedExtensions.contains(imageURL.pathExtension.lowercased()) else { return }
        _ = contactSheetStorage.addImage(from: imageURL, to: sheetID)

        if selection == .contactSheet(sheetID) {
            imageFiles = contactSheetStorage.getImages(for: sheetID)
        }
    }

    // MARK: - Image Loading

    private func loadImages(from folderURLs: [URL]) {
        imageFiles = []

        DispatchQueue.global(qos: .userInitiated).async {
            var newImageFiles: [ImageFile] = []
            let fileManager = FileManager.default

            for folderURL in folderURLs {
                if let enumerator = fileManager.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                    for case let fileURL as URL in enumerator {
                        if supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                            newImageFiles.append(ImageFile(url: fileURL))
                        }
                    }
                }
            }

            newImageFiles.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            DispatchQueue.main.async {
                self.imageFiles = newImageFiles
                let urls = newImageFiles.map { $0.url }
                PreviewImageCache.shared.preloadLibrary(urls: urls, priority: .utility)
            }
        }
    }

    // MARK: - Selection

    private func handleImageSelection(for fileID: UUID) {
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true,
           let lastID = lastSelectedImageFileID,
           let lastIndex = imageFiles.firstIndex(where: { $0.id == lastID }),
           let currentIndex = imageFiles.firstIndex(where: { $0.id == fileID }) {
            let range = min(lastIndex, currentIndex)...max(lastIndex, currentIndex)
            selectedImageFileIDs = Set(imageFiles[range].map { $0.id })
        } else if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            if selectedImageFileIDs.contains(fileID) {
                selectedImageFileIDs.remove(fileID)
            } else {
                selectedImageFileIDs.insert(fileID)
            }
        } else {
            selectedImageFileIDs = [fileID]
        }
        lastSelectedImageFileID = fileID

        if let file = imageFiles.first(where: { $0.id == fileID }) {
            PreviewImageCache.shared.preloadImage(for: file.url)
        }
    }

    private func handleDoubleClickImage(for fileID: UUID) {
        if let file = imageFiles.first(where: { $0.id == fileID }) {
            withAnimation(.easeOut(duration: 0.18)) {
                detailViewFile = file
            }
        }
    }

    // MARK: - Delete

    private func moveFilesToTrash(_ files: [ImageFile]) {
        let deletedIDs = Set(files.map { $0.id })
        let wasPreviewedDeleted = previewedImageFile != nil && deletedIDs.contains(previewedImageFile!.id)
        var previewIndex: Int? = nil
        if wasPreviewedDeleted, let current = previewedImageFile, let idx = imageFiles.firstIndex(of: current) {
            previewIndex = idx
        }
        let originalFilesSnapshot = imageFiles
        let anchorIndexBeforeDeletion: Int? = files
            .compactMap { file in originalFilesSnapshot.firstIndex(of: file) }
            .min()

        for file in files {
            do {
                try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
                imageFiles.removeAll { $0.id == file.id }
                selectedImageFileIDs.remove(file.id)
            } catch {
                print("Error moving file to trash: \(error)")
            }
        }

        if wasPreviewedDeleted {
            let remaining = imageFiles
            if let idx = previewIndex {
                let nextIdx = idx < remaining.count ? idx : (remaining.count - 1)
                if nextIdx >= 0, nextIdx < remaining.count {
                    let nextFile = remaining[nextIdx]
                    previewedImageFile = nextFile
                    selectedImageFileIDs = [nextFile.id]
                    lastSelectedImageFileID = nextFile.id
                    scrollToID = nextFile.id
                } else {
                    previewedImageFile = nil
                }
            } else {
                previewedImageFile = nil
            }
        } else {
            let remaining = imageFiles
            if let idx = anchorIndexBeforeDeletion {
                let candidate = idx < remaining.count ? idx : (remaining.count - 1)
                if candidate >= 0, remaining.indices.contains(candidate) {
                    let nextFile = remaining[candidate]
                    selectedImageFileIDs = [nextFile.id]
                    lastSelectedImageFileID = nextFile.id
                    scrollToID = nextFile.id
                } else {
                    selectedImageFileIDs = []
                    lastSelectedImageFileID = nil
                }
            } else if let first = remaining.first {
                selectedImageFileIDs = [first.id]
                lastSelectedImageFileID = first.id
                scrollToID = first.id
            } else {
                selectedImageFileIDs = []
                lastSelectedImageFileID = nil
            }
        }
    }

    // MARK: - Navigation

    private func handleArrowKey(_ direction: ArrowDirection) {
        guard !imageFiles.isEmpty else { return }

        if let currentFile = previewedImageFile, let currentIndex = imageFiles.firstIndex(of: currentFile) {
            var nextIndex: Int?

            switch direction {
            case .left:
                if currentIndex > 0 { nextIndex = currentIndex - 1 }
            case .right:
                if currentIndex < imageFiles.count - 1 { nextIndex = currentIndex + 1 }
            default:
                break
            }

            if let newIndex = nextIndex {
                let nextFile = imageFiles[newIndex]
                previewedImageFile = nextFile
                selectedImageFileIDs = [nextFile.id]
                lastSelectedImageFileID = nextFile.id
                scrollToID = nextFile.id
            }
            return
        }

        let sortedFiles = imageFiles

        guard let lastID = lastSelectedImageFileID,
              let currentIndex = sortedFiles.firstIndex(where: { $0.id == lastID }) else {
            if let firstFile = sortedFiles.first {
                selectedImageFileIDs = [firstFile.id]
                lastSelectedImageFileID = firstFile.id
                scrollToID = firstFile.id
            }
            return
        }

        var nextIndex: Int?

        switch direction {
        case .up:
            if currentIndex >= gridColumnCount { nextIndex = currentIndex - gridColumnCount }
        case .down:
            if currentIndex + gridColumnCount < sortedFiles.count { nextIndex = currentIndex + gridColumnCount }
        case .left:
            if currentIndex > 0 { nextIndex = currentIndex - 1 }
        case .right:
            if currentIndex < sortedFiles.count - 1 { nextIndex = currentIndex + 1 }
        }

        if let newIndex = nextIndex {
            let nextFile = sortedFiles[newIndex]
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                selectedImageFileIDs.insert(nextFile.id)
            } else {
                selectedImageFileIDs = [nextFile.id]
            }
            lastSelectedImageFileID = nextFile.id
            scrollToID = nextFile.id
        }
    }

    // MARK: - Rename

    private func renameFile(from oldURL: URL, to newName: String) {
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
            if let index = imageFiles.firstIndex(where: { $0.url == oldURL }) {
                imageFiles[index] = ImageFile(url: newURL)
            }
            if let index = folderURLs.firstIndex(of: oldURL) {
                folderURLs[index] = newURL
            }
        } catch {
            print("Error renaming file: \(error)")
        }
    }
}
