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

enum LibraryRoute: Hashable {
    case image(UUID)

    var imageID: UUID {
        switch self {
        case .image(let id):
            return id
        }
    }
}

enum LibraryNavigation {
    static func path(toImage id: UUID) -> [LibraryRoute] {
        [.image(id)]
    }

    static func detailImageID(in path: [LibraryRoute]) -> UUID? {
        path.last?.imageID
    }
}

extension Notification.Name {
    static let microficheMoveSelectionToArchive = Notification.Name("microficheMoveSelectionToArchive")
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
    @State private var liveGridThumbnailSize: CGFloat?
    @State private var isResizingGrid = false
    @State private var selectedImageFileIDs: Set<UUID> = []
    @State private var focusedImageFileID: UUID?
    @State private var showDeleteAlert: Bool = false
    @State private var dontAskAgain: Bool = UserDefaults.standard.bool(forKey: "dontAskDeleteConfirm")
    @State private var pendingDeleteFiles: [ImageFile] = []
    @State private var showChooseArchiveAlert = false
    @State private var pendingArchiveFiles: [ImageFile] = []
    @State private var archiveErrorMessage: String?
    @State private var isQuickPreviewPresented = false
    @State private var scrollToID: UUID?
    @State private var gridColumnCount: Int = 1
    @State private var libraryPath: [LibraryRoute] = []
    @AppStorage("libraryMetadataInspectorPresented") private var isMetadataInspectorPresented = false
    @AppStorage("detailMetadataPresented") private var isDetailMetadataPresented = true
    @AppStorage("librarySidebarCollapsed") private var isLibrarySidebarCollapsed = false
    @State private var externalDriveNotice: String?
    @AppStorage("lastSelectedLibraryFolderID") private var lastSelectedLibraryFolderID = ""
    @StateObject private var libraryStorage = LibraryStorage.shared
    @StateObject private var contactSheetStorage = ContactSheetStorage.shared
    @StateObject private var userPreferences = UserPreferences.shared
    @StateObject private var archiveFolderStore = ArchiveFolderStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let supportedExtensions = ["jpg", "jpeg", "png", "pdf", "svg", "gif", "tiff"]

    private var displayedGridThumbnailSize: CGFloat {
        liveGridThumbnailSize ?? gridThumbnailSize
    }

    var body: some View {
        ZStack {
            libraryContainer
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
                    case .none:
                        imageFiles = []
                    }
                    selectedImageFileIDs = []
                    focusedImageFileID = nil
                    isQuickPreviewPresented = false
                    libraryPath.removeAll()
                }
                .onChange(of: libraryStorage.linkedFolders) {
                    reloadSelectedLibraryLocation()
                }
                .onChange(of: libraryPath) { oldPath, newPath in
                    if LibraryNavigation.detailImageID(in: oldPath) != nil,
                       LibraryNavigation.detailImageID(in: newPath) == nil {
                        requestScrollToFocusedImage()
                    }
                }
                .onChange(of: viewMode) {
                    requestScrollToFocusedImage()
                }
                .onChange(of: showDeleteAlert) { _, isShowing in
                    if !isShowing {
                        pendingDeleteFiles = []
                    }
                }
                .onChange(of: showChooseArchiveAlert) { _, isShowing in
                    if !isShowing, archiveFolderStore.resolvedURL() == nil {
                        pendingArchiveFiles = []
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .microficheMoveSelectionToArchive)) { _ in
                    guard !userPreferences.isPresentingOnboarding else { return }
                    let selected = imageFiles.filter { selectedImageFileIDs.contains($0.id) }
                    guard !selected.isEmpty else { return }
                    requestArchive(for: selected)
                }
                .background(KeyboardEventHandlingView(
                    onDeletePressed: { bypassConfirmation in
                        guard !userPreferences.isPresentingOnboarding else { return }
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
                        if userPreferences.isPresentingOnboarding {
                            userPreferences.completeOnboarding()
                        } else if isImageDetailPresented {
                            closeImageDetail()
                        } else if isQuickPreviewPresented {
                            dismissQuickPreview()
                        } else if !selectedImageFileIDs.isEmpty {
                            selectedImageFileIDs = []
                            focusedImageFileID = nil
                        }
                    },
                    onSpacebarPressed: {
                        guard !userPreferences.isPresentingOnboarding else { return }
                        toggleQuickPreview()
                    },
                    onArrowPressed: { direction in
                        guard !userPreferences.isPresentingOnboarding else { return }
                        handleArrowKey(direction)
                    }
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
                .alert("Choose Archive Folder", isPresented: $showChooseArchiveAlert) {
                    Button("Choose…") {
                        if archiveFolderStore.chooseFolder() {
                            moveFilesToArchive(pendingArchiveFiles)
                        }
                        pendingArchiveFiles = []
                    }
                    .keyboardShortcut(.defaultAction)

                    Button("Cancel", role: .cancel) {
                        pendingArchiveFiles = []
                    }
                } message: {
                    Text("Pick a folder where Microfiche should move archived images.")
                }
                .alert(
                    "Couldn’t Archive",
                    isPresented: Binding(
                        get: { archiveErrorMessage != nil },
                        set: { if !$0 { archiveErrorMessage = nil } }
                    )
                ) {
                    Button("OK") { archiveErrorMessage = nil }
                } message: {
                    Text(archiveErrorMessage ?? "")
                }

                if isQuickPreviewPresented, let file = focusedImageFile {
                    PreviewView(file: file) {
                        dismissQuickPreview()
                    }
                    .transition(.opacity)
                }

                if userPreferences.isPresentingOnboarding {
                    OnboardingView(
                        onLinkFolder: linkFolder,
                        onFinished: {
                            userPreferences.completeOnboarding()
                        }
                    )
                    .transition(.opacity)
                    .zIndex(10)
                }
        }
        .animation(MicroficheMotion.snap, value: isQuickPreviewPresented)
        .animation(MicroficheMotion.transition, value: userPreferences.isPresentingOnboarding)
        .task {
            restoreLibrarySelection()
            userPreferences.evaluateLaunchPresentation()
        }
    }

    private var libraryContainer: AnyView {
        AnyView(
            NavigationSplitView(columnVisibility: splitViewVisibilityBinding) {
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
                .microficheSidebarChrome()
            } detail: {
                libraryDetailNavigation
            }
            .navigationTitle("")
            .toolbar {
                libraryToolbar
            }
            .microficheToolbarChrome()
        )
    }

    private var libraryDetailNavigation: some View {
        NavigationStack(path: $libraryPath) {
            MainContentView(
                imageFiles: imageFiles,
                unavailableLocation: unavailableSelectedFolder,
                showsToolbar: true,
                viewMode: $viewMode,
                gridThumbnailSize: displayedGridThumbnailSize,
                isResizingGrid: isResizingGrid,
                gridColumnCount: $gridColumnCount,
                selectedImageFileIDs: $selectedImageFileIDs,
                onSelectImage: handleImageSelection,
                onDoubleClickImage: handleDoubleClickImage,
                scrollToID: $scrollToID,
                onRename: renameFile,
                contactSheets: contactSheetStorage.contactSheets,
                onAddToContactSheet: handleAddToContactSheet,
                onArchive: handleArchiveRequest(for:)
            )
            .inspector(isPresented: libraryInspectorBinding) {
                if let focusedImageFile {
                    ImageMetadataInspectorView(file: focusedImageFile)
                        .id(focusedImageFile.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .microficheSidebarChrome()
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
                }
            }
            .navigationDestination(for: LibraryRoute.self) { route in
                imageDetailDestination(for: route)
            }
        }
    }

    @ToolbarContentBuilder
    private var libraryToolbar: some ToolbarContent {
        if !isImageDetailPresented {
            ToolbarItem(placement: .principal) {
                if viewMode == .grid {
                    HStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Slider(
                            value: gridThumbnailSizeBinding,
                            in: GridThumbnailSizing.minimum...GridThumbnailSizing.maximum,
                            onEditingChanged: handleGridResize
                        )
                        .frame(width: 110)
                        .accessibilityLabel("Thumbnail size")
                        .accessibilityValue("\(Int(displayedGridThumbnailSize.rounded())) points")

                        Image(systemName: "photo.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                    .help("Thumbnail Size")
                } else {
                    Color.clear
                        .frame(width: 168, height: 1)
                        .accessibilityHidden(true)
                }
            }
            .hideSharedBackgroundIfAvailable()

            ToolbarItem {
                Button {
                    withAnimation(MicroficheMotion.panel(reducedMotion: reduceMotion)) {
                        isMetadataInspectorPresented.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .disabled(focusedImageFile == nil)
                .help(isMetadataInspectorPresented ? "Hide Info" : "Show Info")
            }
            .hideSharedBackgroundIfAvailable()
        }
    }

    private var focusedImageFile: ImageFile? {
        guard let focusedImageFileID else { return nil }
        return imageFiles.first { $0.id == focusedImageFileID }
    }

    private var detailImageID: UUID? {
        LibraryNavigation.detailImageID(in: libraryPath)
    }

    private var detailImageFile: ImageFile? {
        guard let detailImageID else { return nil }
        return imageFiles.first { $0.id == detailImageID }
    }

    private var isImageDetailPresented: Bool {
        detailImageID != nil
    }

    private var libraryInspectorBinding: Binding<Bool> {
        Binding(
            get: {
                !isImageDetailPresented
                    && focusedImageFile != nil
                    && isMetadataInspectorPresented
            },
            set: { isPresented in
                guard !isImageDetailPresented, focusedImageFile != nil else { return }
                isMetadataInspectorPresented = isPresented
            }
        )
    }

    private var splitViewVisibilityBinding: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { isLibrarySidebarCollapsed ? .detailOnly : .all },
            set: { isLibrarySidebarCollapsed = ($0 == .detailOnly) }
        )
    }

    @ViewBuilder
    private func imageDetailDestination(for route: LibraryRoute) -> some View {
        if let file = imageFiles.first(where: { $0.id == route.imageID }) {
            ImageDetailView(
                file: file,
                isMetadataPresented: $isDetailMetadataPresented
            )
        } else {
            ContentUnavailableView(
                "Image Unavailable",
                systemImage: "photo.badge.exclamationmark",
                description: Text("The image is no longer part of this library.")
            )
        }
    }

    private var unavailableSelectedFolder: LinkedLibraryFolder? {
        guard case .folder(let id) = selection,
              let folder = libraryStorage.folder(id: id),
              !folder.isAvailable else { return nil }
        return folder
    }

    private var gridThumbnailSizeBinding: Binding<CGFloat> {
        Binding(
            get: { displayedGridThumbnailSize },
            set: { newValue in
                liveGridThumbnailSize = newValue
                if !isResizingGrid {
                    gridThumbnailSize = newValue
                }
            }
        )
    }

    private func handleGridResize(_ isEditing: Bool) {
        if isEditing {
            isResizingGrid = true
            if liveGridThumbnailSize == nil {
                liveGridThumbnailSize = gridThumbnailSize
            }
            return
        }

        if let liveGridThumbnailSize {
            gridThumbnailSize = liveGridThumbnailSize
        }
        liveGridThumbnailSize = nil
        isResizingGrid = false
        requestScrollToFocusedImage()
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
        guard !isLibrarySidebarCollapsed else { return }

        if width < SidebarLayout.autoCollapseWidth {
            withAnimation(MicroficheMotion.transition) {
                isLibrarySidebarCollapsed = true
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
            libraryPath = LibraryNavigation.path(toImage: file.id)
        }
    }

    private func closeImageDetail() {
        guard !libraryPath.isEmpty else { return }
        libraryPath.removeLast()
    }

    // MARK: - Archive

    private func handleArchiveRequest(for file: ImageFile) {
        if selectedImageFileIDs.contains(file.id), selectedImageFileIDs.count > 1 {
            let selected = imageFiles.filter { selectedImageFileIDs.contains($0.id) }
            requestArchive(for: selected)
        } else {
            requestArchive(for: [file])
        }
    }

    private func requestArchive(for files: [ImageFile]) {
        guard !files.isEmpty else { return }

        if archiveFolderStore.resolvedURL() != nil {
            moveFilesToArchive(files)
            return
        }

        pendingArchiveFiles = files
        showChooseArchiveAlert = true
    }

    private func moveFilesToArchive(_ files: [ImageFile]) {
        guard let archiveURL = archiveFolderStore.resolvedURL() else {
            pendingArchiveFiles = files
            showChooseArchiveAlert = true
            return
        }

        let archivedIDs = Set(files.map(\.id))
        let deletedDetailIndex = detailImageFile.flatMap { detailFile in
            archivedIDs.contains(detailFile.id)
                ? imageFiles.firstIndex(where: { $0.id == detailFile.id })
                : nil
        }
        let wasPreviewedArchived = isQuickPreviewPresented
            && focusedImageFileID.map(archivedIDs.contains) == true
        var previewIndex: Int?
        if wasPreviewedArchived,
           let focusedImageFileID,
           let idx = imageFiles.firstIndex(where: { $0.id == focusedImageFileID }) {
            previewIndex = idx
        }
        let originalFilesSnapshot = imageFiles
        let anchorIndexBeforeArchive: Int? = files
            .compactMap { file in originalFilesSnapshot.firstIndex(of: file) }
            .min()

        var movedCount = 0
        var lastError: Error?

        for file in files {
            do {
                let destination = try FileArchiver.move(file.url, intoArchive: archiveURL)
                ImageMetadataStore.shared.move(from: file.url, to: destination)
                ImageCache.shared.clearCacheForFile(at: file.url)
                PreviewImageCache.shared.clearCacheForFile(at: file.url)
                imageFiles.removeAll { $0.id == file.id }
                selectedImageFileIDs.remove(file.id)
                movedCount += 1
            } catch {
                lastError = error
                print("Error archiving file: \(error)")
            }
        }

        if movedCount == 0 {
            archiveErrorMessage = lastError?.localizedDescription
                ?? "Unable to move the selected images to the archive folder."
            return
        }

        if movedCount < files.count {
            archiveErrorMessage = "Moved \(movedCount) of \(files.count) images. \(lastError?.localizedDescription ?? "Some files could not be archived.")"
        }

        updateFocusAfterRemovingFiles(
            removedDetailIndex: deletedDetailIndex,
            wasPreviewedRemoved: wasPreviewedArchived,
            previewIndex: previewIndex,
            anchorIndexBeforeRemoval: anchorIndexBeforeArchive
        )
    }

    // MARK: - Delete

    private func moveFilesToTrash(_ files: [ImageFile]) {
        let deletedIDs = Set(files.map { $0.id })
        let deletedDetailIndex = detailImageFile.flatMap { detailFile in
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

        var trashedURLs: [URL] = []
        for file in files {
            do {
                try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
                imageFiles.removeAll { $0.id == file.id }
                selectedImageFileIDs.remove(file.id)
                trashedURLs.append(file.url)
            } catch {
                print("Error moving file to trash: \(error)")
            }
        }
        ImageMetadataStore.shared.remove(for: trashedURLs)
        for url in trashedURLs {
            ImageCache.shared.clearCacheForFile(at: url)
            PreviewImageCache.shared.clearCacheForFile(at: url)
        }

        updateFocusAfterRemovingFiles(
            removedDetailIndex: deletedDetailIndex,
            wasPreviewedRemoved: wasPreviewedDeleted,
            previewIndex: previewIndex,
            anchorIndexBeforeRemoval: anchorIndexBeforeDeletion
        )
    }

    private func updateFocusAfterRemovingFiles(
        removedDetailIndex: Int?,
        wasPreviewedRemoved: Bool,
        previewIndex: Int?,
        anchorIndexBeforeRemoval: Int?
    ) {
        if let removedDetailIndex {
            let nextIndex = min(removedDetailIndex, imageFiles.count - 1)
            if imageFiles.indices.contains(nextIndex) {
                let nextFile = imageFiles[nextIndex]
                libraryPath = LibraryNavigation.path(toImage: nextFile.id)
                selectedImageFileIDs = [nextFile.id]
                focusedImageFileID = nextFile.id
                scrollToID = nextFile.id
            } else {
                libraryPath.removeAll()
                selectedImageFileIDs = []
                focusedImageFileID = nil
            }
            return
        }

        if wasPreviewedRemoved {
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
            return
        }

        let remaining = imageFiles
        if let idx = anchorIndexBeforeRemoval {
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
        if isQuickPreviewPresented || isImageDetailPresented {
            selectedImageFileIDs = [nextFile.id]
        } else if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            selectedImageFileIDs.insert(nextFile.id)
        } else {
            selectedImageFileIDs = [nextFile.id]
        }
        self.focusedImageFileID = nextFile.id
        if isImageDetailPresented {
            libraryPath = LibraryNavigation.path(toImage: nextFile.id)
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
        guard !isImageDetailPresented else { return }

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
            ImageMetadataStore.shared.move(from: oldURL, to: newURL)
            ImageCache.shared.clearCacheForFile(at: oldURL)
            PreviewImageCache.shared.clearCacheForFile(at: oldURL)

            if let index = imageFiles.firstIndex(where: { $0.url == oldURL }) {
                let oldID = imageFiles[index].id
                let renamedFile = ImageFile(url: newURL)
                imageFiles[index] = renamedFile

                if selectedImageFileIDs.remove(oldID) != nil {
                    selectedImageFileIDs.insert(renamedFile.id)
                }
                if focusedImageFileID == oldID {
                    focusedImageFileID = renamedFile.id
                }
                if scrollToID == oldID {
                    scrollToID = renamedFile.id
                }
                if detailImageID == oldID {
                    libraryPath = LibraryNavigation.path(toImage: renamedFile.id)
                }
            }
        } catch {
            print("Error renaming file: \(error)")
        }
    }
}
