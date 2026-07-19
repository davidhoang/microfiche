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
    case folder(UUID)
    case contactSheet(UUID)
}

enum ViewMode: String, CaseIterable, Identifiable {
    case grid = "Grid"
    case list = "List"
    var id: String { rawValue }
}

enum GridThumbnailSizing {
    static let minimum: CGFloat = 80
    static let defaultValue: CGFloat = 120
    static let maximum: CGFloat = 180

    /// Decode once at the largest grid size so the size slider only changes
    /// layout frames and can scale already-resident bitmaps without reloading.
    static var decodeSize: CGFloat { maximum }
}

enum ArrowDirection {
    case up, down, left, right
}

enum ImageNavigation {
    static func nextIndex(
        from currentIndex: Int,
        itemCount: Int,
        direction: ArrowDirection,
        viewMode: ViewMode,
        gridColumnCount: Int
    ) -> Int? {
        let verticalStep = viewMode == .grid ? max(1, gridColumnCount) : 1
        let candidate: Int

        switch direction {
        case .left:
            candidate = currentIndex - 1
        case .right:
            candidate = currentIndex + 1
        case .up:
            candidate = currentIndex - verticalStep
        case .down:
            candidate = currentIndex + verticalStep
        }

        return (0..<itemCount).contains(candidate) ? candidate : nil
    }
}

// MARK: - Content View

struct ContentView: View {
    private enum SidebarLayout {
        static let minimumWidth: CGFloat = 240
        static let idealWidth: CGFloat = 280
        static let maximumWidth: CGFloat = 360
        static let autoCollapseWidth: CGFloat = 220
    }

    @State private var selection: Selection?
    @State private var imageFiles: [ImageFile] = []
    @State private var libraryLoadGeneration = UUID()
    @State private var viewMode: ViewMode = .grid
    @State private var gridThumbnailSize: CGFloat = GridThumbnailSizing.defaultValue
    @State private var selectedImageFileIDs: Set<UUID> = []
    @State private var focusedImageFileID: UUID?
    @State private var showDeleteAlert: Bool = false
    @State private var dontAskAgain: Bool = UserDefaults.standard.bool(forKey: "dontAskDeleteConfirm")
    @State private var pendingDeleteFiles: [ImageFile] = []
    @State private var isQuickPreviewPresented = false
    @State private var scrollToID: UUID?
    @State private var gridColumnCount: Int = 1
    @State private var detailViewFile: ImageFile?
    @State private var isMetadataInspectorPresented = false
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all
    @State private var externalDriveNotice: String?
    @AppStorage("lastSelectedLibraryFolderID") private var lastSelectedLibraryFolderID = ""
    @StateObject private var libraryStorage = LibraryStorage.shared
    @StateObject private var contactSheetStorage = ContactSheetStorage.shared

    let supportedExtensions = ["jpg", "jpeg", "png", "pdf", "svg", "gif", "tiff"]

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $splitViewVisibility) {
                    SidebarView(
                        folders: libraryStorage.linkedFolders,
                        externalVolumes: libraryStorage.rememberedExternalVolumes,
                        contactSheets: contactSheetStorage.contactSheets,
                        selection: selection,
                        onWidthChange: handleSidebarWidthChange,
                        onLinkFolder: linkFolder,
                        onSelect: { newSelection in
                            selection = newSelection
                        },
                        onRemoveFolder: removeFolder,
                        onForgetExternalVolume: libraryStorage.forgetExternalVolume,
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
                if let detailFile = detailViewFile {
                    ImageDetailView(
                        file: detailFile,
                        isInspectorPresented: $isMetadataInspectorPresented,
                        onBack: closeImageDetail
                    )
                } else {
                    MainContentView(
                        imageFiles: imageFiles,
                        unavailableLocation: unavailableSelectedFolder,
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
            }
                .navigationTitle("")
                .onChange(of: selection) { _, newValue in
                    switch newValue {
                    case .all:
                        loadImages(from: libraryStorage.availableFolderURLs)
                        lastSelectedLibraryFolderID = ""
                    case .folder(let id):
                        let urls = libraryStorage.folder(id: id)?.resolvedURL.map { [$0] } ?? []
                        loadImages(from: urls)
                        lastSelectedLibraryFolderID = id.uuidString
                    case .contactSheet(let id):
                        libraryLoadGeneration = UUID()
                        imageFiles = contactSheetStorage.getImages(for: id)
                        let urls = imageFiles.map { $0.url }
                        PreviewImageCache.shared.preloadLibrary(urls: urls, priority: .utility)
                    case .none:
                        imageFiles = []
                    }
                    selectedImageFileIDs = []
                    focusedImageFileID = nil
                    isQuickPreviewPresented = false
                    detailViewFile = nil
                    isMetadataInspectorPresented = false
                }
                .onChange(of: libraryStorage.linkedFolders) {
                    reloadSelectedLibraryLocation()
                }
                .onChange(of: viewMode) {
                    requestScrollToFocusedImage()
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
                        if detailViewFile != nil {
                            closeImageDetail()
                        } else if isQuickPreviewPresented {
                            dismissQuickPreview()
                        } else if !selectedImageFileIDs.isEmpty {
                            selectedImageFileIDs = []
                            focusedImageFileID = nil
                        }
                    },
                    onSpacebarPressed: toggleQuickPreview,
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
                .alert(
                    "External Drive Remembered",
                    isPresented: Binding(
                        get: { externalDriveNotice != nil },
                        set: { if !$0 { externalDriveNotice = nil } }
                    )
                ) {
                    Button("OK") { externalDriveNotice = nil }
                } message: {
                    Text(externalDriveNotice ?? "")
                }

                if isQuickPreviewPresented, let file = focusedImageFile {
                    PreviewView(file: file) {
                        dismissQuickPreview()
                    }
                    .transition(.opacity)
                }
        }
        .animation(.easeOut(duration: 0.18), value: detailViewFile)
        .animation(.easeInOut(duration: 0.12), value: isQuickPreviewPresented)
        .task {
            restoreLibrarySelection()
        }
    }

    private var focusedImageFile: ImageFile? {
        guard let focusedImageFileID else { return nil }
        return imageFiles.first { $0.id == focusedImageFileID }
    }

    private var unavailableSelectedFolder: LinkedLibraryFolder? {
        guard case .folder(let id) = selection,
              let folder = libraryStorage.folder(id: id),
              !folder.isAvailable else { return nil }
        return folder
    }

    // MARK: - Folder Management

    private func linkFolder() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = true

        if openPanel.runModal() == .OK {
            let result = libraryStorage.addFolders(openPanel.urls)
            if selection == nil, let firstFolder = result.folders.first {
                selection = .folder(firstFolder.id)
            }
            if !result.newlyRememberedVolumes.isEmpty {
                let names = result.newlyRememberedVolumes.map(\.name).joined(separator: ", ")
                externalDriveNotice = "\(names) will stay in Locations when disconnected and reconnect automatically when available."
            }
        }
    }

    private func removeFolder(_ id: UUID) {
        if let index = libraryStorage.linkedFolders.firstIndex(where: { $0.id == id }) {
            let wasSelected = (selection == .folder(id))
            libraryStorage.removeFolder(id: id)

            if wasSelected {
                let remainingFolders = libraryStorage.linkedFolders
                if !remainingFolders.isEmpty {
                    let newIndex = min(index, remainingFolders.count - 1)
                    selection = .folder(remainingFolders[newIndex].id)
                } else {
                    selection = .all
                }
            }
        }
    }

    private func restoreLibrarySelection() {
        guard selection == nil else { return }
        if let id = UUID(uuidString: lastSelectedLibraryFolderID),
           libraryStorage.folder(id: id) != nil {
            selection = .folder(id)
        } else if !libraryStorage.linkedFolders.isEmpty {
            selection = .all
        }
    }

    private func reloadSelectedLibraryLocation() {
        switch selection {
        case .all:
            loadImages(from: libraryStorage.availableFolderURLs)
        case .folder(let id):
            let urls = libraryStorage.folder(id: id)?.resolvedURL.map { [$0] } ?? []
            loadImages(from: urls)
        case .contactSheet, .none:
            break
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
        let generation = UUID()
        libraryLoadGeneration = generation
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
                guard self.libraryLoadGeneration == generation else { return }
                self.imageFiles = newImageFiles
                let urls = newImageFiles.map { $0.url }
                PreviewImageCache.shared.preloadLibrary(urls: urls, priority: .utility)
            }
        }
    }

    // MARK: - Selection

    private func handleImageSelection(for fileID: UUID) {
        var nextFocusedID: UUID? = fileID

        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true,
           let lastID = focusedImageFileID,
           let lastIndex = imageFiles.firstIndex(where: { $0.id == lastID }),
           let currentIndex = imageFiles.firstIndex(where: { $0.id == fileID }) {
            let range = min(lastIndex, currentIndex)...max(lastIndex, currentIndex)
            selectedImageFileIDs = Set(imageFiles[range].map { $0.id })
        } else if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            if selectedImageFileIDs.contains(fileID) {
                selectedImageFileIDs.remove(fileID)
                nextFocusedID = imageFiles.first {
                    selectedImageFileIDs.contains($0.id)
                }?.id
            } else {
                selectedImageFileIDs.insert(fileID)
            }
        } else {
            selectedImageFileIDs = [fileID]
        }
        focusedImageFileID = nextFocusedID

        if let file = imageFiles.first(where: { $0.id == fileID }) {
            PreviewImageCache.shared.preloadImage(for: file.url)
        }
    }

    private func handleDoubleClickImage(for fileID: UUID) {
        if let file = imageFiles.first(where: { $0.id == fileID }) {
            isQuickPreviewPresented = false
            selectedImageFileIDs = [fileID]
            focusedImageFileID = fileID
            withAnimation(.easeOut(duration: 0.18)) {
                detailViewFile = file
                isMetadataInspectorPresented = true
            }
        }
    }

    private func closeImageDetail() {
        withAnimation(.easeInOut(duration: 0.2)) {
            detailViewFile = nil
            isMetadataInspectorPresented = false
        }
        requestScrollToFocusedImage()
    }

    // MARK: - Delete

    private func moveFilesToTrash(_ files: [ImageFile]) {
        let deletedIDs = Set(files.map { $0.id })
        let deletedDetailIndex = detailViewFile.flatMap { detailFile in
            deletedIDs.contains(detailFile.id)
                ? imageFiles.firstIndex(where: { $0.id == detailFile.id })
                : nil
        }
        let wasPreviewedDeleted = isQuickPreviewPresented
            && focusedImageFileID.map(deletedIDs.contains) == true
        var previewIndex: Int? = nil
        if wasPreviewedDeleted,
           let focusedImageFileID,
           let idx = imageFiles.firstIndex(where: { $0.id == focusedImageFileID }) {
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

        if let deletedDetailIndex {
            let nextIndex = min(deletedDetailIndex, imageFiles.count - 1)
            if imageFiles.indices.contains(nextIndex) {
                let nextFile = imageFiles[nextIndex]
                detailViewFile = nextFile
                selectedImageFileIDs = [nextFile.id]
                focusedImageFileID = nextFile.id
                scrollToID = nextFile.id
            } else {
                detailViewFile = nil
                isMetadataInspectorPresented = false
                selectedImageFileIDs = []
                focusedImageFileID = nil
            }
            return
        }

        if wasPreviewedDeleted {
            let remaining = imageFiles
            if let idx = previewIndex {
                let nextIdx = idx < remaining.count ? idx : (remaining.count - 1)
                if nextIdx >= 0, nextIdx < remaining.count {
                    let nextFile = remaining[nextIdx]
                    selectedImageFileIDs = [nextFile.id]
                    focusedImageFileID = nextFile.id
                    scrollToID = nextFile.id
                } else {
                    isQuickPreviewPresented = false
                    focusedImageFileID = nil
                }
            } else {
                isQuickPreviewPresented = false
                focusedImageFileID = nil
            }
        } else {
            let remaining = imageFiles
            if let idx = anchorIndexBeforeDeletion {
                let candidate = idx < remaining.count ? idx : (remaining.count - 1)
                if candidate >= 0, remaining.indices.contains(candidate) {
                    let nextFile = remaining[candidate]
                    selectedImageFileIDs = [nextFile.id]
                    focusedImageFileID = nextFile.id
                    scrollToID = nextFile.id
                } else {
                    selectedImageFileIDs = []
                    focusedImageFileID = nil
                }
            } else if let first = remaining.first {
                selectedImageFileIDs = [first.id]
                focusedImageFileID = first.id
                scrollToID = first.id
            } else {
                selectedImageFileIDs = []
                focusedImageFileID = nil
            }
        }
    }

    // MARK: - Navigation

    private func handleArrowKey(_ direction: ArrowDirection) {
        guard !imageFiles.isEmpty else { return }

        guard let currentFocusedID = focusedImageFileID,
              let currentIndex = imageFiles.firstIndex(where: { $0.id == currentFocusedID }) else {
            if let firstFile = imageFiles.first {
                selectedImageFileIDs = [firstFile.id]
                self.focusedImageFileID = firstFile.id
                scrollToID = firstFile.id
            }
            return
        }

        guard let nextIndex = nextImageIndex(from: currentIndex, direction: direction) else { return }

        let nextFile = imageFiles[nextIndex]
        if isQuickPreviewPresented || detailViewFile != nil {
            selectedImageFileIDs = [nextFile.id]
        } else if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            selectedImageFileIDs.insert(nextFile.id)
        } else {
            selectedImageFileIDs = [nextFile.id]
        }
        self.focusedImageFileID = nextFile.id
        if detailViewFile != nil {
            detailViewFile = nextFile
        }
        scrollToID = nextFile.id
        PreviewImageCache.shared.preloadImage(for: nextFile.url)
    }

    private func nextImageIndex(from currentIndex: Int, direction: ArrowDirection) -> Int? {
        ImageNavigation.nextIndex(
            from: currentIndex,
            itemCount: imageFiles.count,
            direction: direction,
            viewMode: viewMode,
            gridColumnCount: gridColumnCount
        )
    }

    private func toggleQuickPreview() {
        guard detailViewFile == nil else { return }

        if isQuickPreviewPresented {
            dismissQuickPreview()
            return
        }

        guard let file = focusedImageFile,
              selectedImageFileIDs.contains(file.id) else { return }

        selectedImageFileIDs = [file.id]
        isQuickPreviewPresented = true
        PreviewImageCache.shared.preloadImage(for: file.url)
    }

    private func dismissQuickPreview() {
        isQuickPreviewPresented = false
        requestScrollToFocusedImage()
    }

    private func requestScrollToFocusedImage() {
        guard let focusedImageFileID else { return }
        DispatchQueue.main.async {
            scrollToID = focusedImageFileID
        }
    }

    // MARK: - Rename

    private func renameFile(from oldURL: URL, to newName: String) {
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
            if let index = imageFiles.firstIndex(where: { $0.url == oldURL }) {
                imageFiles[index] = ImageFile(id: imageFiles[index].id, url: newURL)
                if detailViewFile?.id == imageFiles[index].id {
                    detailViewFile = imageFiles[index]
                }
            }
        } catch {
            print("Error renaming file: \(error)")
        }
    }
}
