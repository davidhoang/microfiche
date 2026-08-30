//
//  MainContentView.swift
//  Microfiche
//
//  Created by David Hoang on 6/8/25.
//

import AppKit
import SwiftUI

enum ImageCellInteractionAction: Equatable {
    case select
    case openDetail
}

enum ImageCellInteraction {
    static func actions(forClickCount clickCount: Int) -> [ImageCellInteractionAction] {
        guard clickCount > 0 else { return [] }
        return clickCount == 2 ? [.select, .openDetail] : [.select]
    }
}

private final class NonHitTestingClickMonitorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct ImageCellClickMonitor: NSViewRepresentable {
    let onSelect: () -> Void
    let onDoubleClick: () -> Void

    final class Coordinator {
        weak var view: NSView?
        var monitor: Any?
        var onSelect: () -> Void
        var onDoubleClick: () -> Void

        init(onSelect: @escaping () -> Void, onDoubleClick: @escaping () -> Void) {
            self.onSelect = onSelect
            self.onDoubleClick = onDoubleClick
        }

        func installMonitor(for view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self,
                      let view = self.view,
                      event.window === view.window else { return event }

                let location = view.convert(event.locationInWindow, from: nil)
                guard view.bounds.contains(location) else { return event }

                for action in ImageCellInteraction.actions(forClickCount: event.clickCount) {
                    switch action {
                    case .select:
                        self.onSelect()
                    case .openDetail:
                        self.onDoubleClick()
                    }
                }
                return event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            removeMonitor()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onDoubleClick: onDoubleClick)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NonHitTestingClickMonitorView()
        context.coordinator.installMonitor(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.onDoubleClick = onDoubleClick
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }
}

// MARK: - Main Content

struct MainContentView: View {
    let imageFiles: [ImageFile]
    let unavailableLocation: LinkedLibraryFolder?
    let isFiltering: Bool
    let onRetryUnavailableLocation: () -> Void
    let showsToolbar: Bool
    @Binding var viewMode: ViewMode
    let gridThumbnailSize: CGFloat
    let isResizingGrid: Bool
    @Binding var gridColumnCount: Int
    @Binding var selectedImageFileIDs: Set<UUID>
    let focusedImageFileID: UUID?
    let onSelectImage: (UUID) -> Void
    let onDoubleClickImage: (UUID) -> Void
    @Binding var scrollToID: UUID?
    let onRename: (URL, String) -> Void
    let contactSheets: [ContactSheet]
    let activeContactSheet: ContactSheet?
    let onAddToContactSheet: (UUID, URL) -> Void
    let onDropToContactSheet: (UUID, [URL]) -> Void
    let onArchive: (ImageFile) -> Void
    @State private var isContactSheetDropTargeted = false

    var body: some View {
        ZStack {
            mainCanvasBackground

            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color(NSColor.separatorColor).opacity(0.45))
                    .frame(height: 1)

                VStack {
                    if imageFiles.isEmpty {
                        Spacer(minLength: 24)
                        EmptyLibraryStateView(
                            unavailableLocation: unavailableLocation,
                            activeContactSheet: activeContactSheet,
                            isFiltering: isFiltering,
                            onRetryUnavailableLocation: onRetryUnavailableLocation
                        )
                        Spacer(minLength: 24)
                    } else {
                        if viewMode == .grid {
                            ImageGridView(
                                imageFiles: imageFiles,
                                selectedImageFileIDs: $selectedImageFileIDs,
                                focusedImageFileID: focusedImageFileID,
                                onSelectImage: onSelectImage,
                                onDoubleClickImage: onDoubleClickImage,
                                thumbnailSize: gridThumbnailSize,
                                isResizing: isResizingGrid,
                                scrollToID: $scrollToID,
                                columnCount: $gridColumnCount,
                                onRename: onRename,
                                contactSheets: contactSheets,
                                onAddToContactSheet: onAddToContactSheet,
                                onArchive: onArchive
                            )
                        } else {
                            ImageListView(
                                imageFiles: imageFiles,
                                selectedImageFileIDs: $selectedImageFileIDs,
                                focusedImageFileID: focusedImageFileID,
                                onSelectImage: onSelectImage,
                                onDoubleClickImage: onDoubleClickImage,
                                scrollToID: $scrollToID,
                                onRename: onRename,
                                contactSheets: contactSheets,
                                onAddToContactSheet: onAddToContactSheet,
                                onArchive: onArchive
                            )
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if let activeContactSheet, isContactSheetDropTargeted {
                ContactSheetDropOverlay(contactSheetName: activeContactSheet.name)
                    .padding(18)
                    .transition(.opacity)
            }
        }
        .onDrop(
            of: ImageDropSupport.acceptedContentTypes,
            isTargeted: $isContactSheetDropTargeted,
            perform: handleContactSheetDrop
        )
        .overlay(alignment: .bottom) {
            if showsToolbar {
                FloatingViewModeControl(selection: $viewMode)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
    }

    private func handleContactSheetDrop(providers: [NSItemProvider]) -> Bool {
        guard let activeContactSheet,
              ImageDropSupport.canLoadFileURL(from: providers) else { return false }

        ImageDropSupport.loadFileURLs(from: providers) { urls in
            guard !urls.isEmpty else { return }
            onDropToContactSheet(activeContactSheet.id, urls)
        }
        return true
    }

    private var mainCanvasBackground: some View {
        Color(NSColor.controlBackgroundColor)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color(NSColor.separatorColor).opacity(0.55))
                    .frame(width: 1)
            }
    }

}

private struct FloatingViewModeControl: View {
    @Binding var selection: ViewMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ViewMode.allCases) { mode in
                Button {
                    withAnimation(MicroficheMotion.snap(reducedMotion: reduceMotion)) {
                        selection = mode
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(.system(size: 12, weight: selection == mode ? .semibold : .medium))
                        .foregroundStyle(selection == mode ? .primary : .secondary)
                        .frame(minWidth: 44)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .background {
                    if selection == mode {
                        Capsule()
                            .fill(Color.primary.opacity(0.12))
                    }
                }
                .accessibilityValue(selection == mode ? "Selected" : "")
                .accessibilityAddTraits(selection == mode ? [.isSelected] : [])
                .accessibilityIdentifier("viewMode.\(mode.rawValue.lowercased())")
                .keyboardShortcut(mode == .grid ? "1" : "2", modifiers: .command)
            }
        }
        .padding(3)
        .floatingViewModeGlass()
        .overlay {
            if contrast == .increased {
                Capsule()
                    .strokeBorder(Color.primary, lineWidth: 1)
            }
        }
        .shadow(
            color: contrast == .increased ? .clear : Color.black.opacity(0.08),
            radius: 6,
            y: 2
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("View mode")
    }
}

private extension View {
    func floatingViewModeGlass() -> some View {
        modifier(FloatingViewModeGlassModifier())
    }
}

private struct FloatingViewModeGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content
                .background(Color(NSColor.controlBackgroundColor), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
                }
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                }
        }
    }
}

private struct EmptyLibraryStateView: View {
    let unavailableLocation: LinkedLibraryFolder?
    let activeContactSheet: ContactSheet?
    let isFiltering: Bool
    let onRetryUnavailableLocation: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: emptyStateIcon)
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 56, height: 56)

            VStack(spacing: 6) {
                Text(emptyStateTitle)
                    .font(.system(size: 22, weight: .semibold))

                Text(emptyStateMessage)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            if unavailableLocation != nil, !isFiltering {
                Button("Try Again", action: onRetryUnavailableLocation)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("library-location.retry")
            }
        }
        .padding(.horizontal, 24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(emptyStateTitle)
        .accessibilityValue(emptyStateMessage)
        .accessibilityIdentifier(
            unavailableLocation == nil ? "library.empty" : "library-location.unavailable"
        )
    }

    private var emptyStateMessage: String {
        if isFiltering {
            return "Try a different name, tag, file type, or clear the active filters."
        }
        if let activeContactSheet {
            return "Drag image files into \(activeContactSheet.name) or drop them on its sidebar item."
        }
        guard let unavailableLocation else {
            return "Link a folder or drop images into a contact sheet to start building a library."
        }

        if unavailableLocation.isICloudDrive {
            return "Check your network connection and iCloud Drive status, then try again."
        }
        let driveName = unavailableLocation.volumeName ?? unavailableLocation.name
        return "Reconnect \(driveName) to restore \(unavailableLocation.displayName) automatically."
    }

    private var emptyStateIcon: String {
        if isFiltering { return "magnifyingglass" }
        if activeContactSheet != nil { return "photo.badge.plus" }
        guard let unavailableLocation else { return "photo.on.rectangle.angled" }
        return unavailableLocation.isICloudDrive ? "icloud.slash" : "externaldrive.badge.xmark"
    }

    private var emptyStateTitle: String {
        if isFiltering { return "No matches" }
        if activeContactSheet != nil { return "Drop images here" }
        guard let unavailableLocation else { return "No images yet" }
        return unavailableLocation.isICloudDrive ? "iCloud Drive unavailable" : "Reconnect the drive"
    }
}

private struct ContactSheetDropOverlay: View {
    let contactSheetName: String

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.accentColor.opacity(0.08))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
            }
            .overlay {
                Label("Add to \(contactSheetName)", systemImage: "photo.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .accessibilityIdentifier("contact-sheet-drop-target")
    }
}

// MARK: - Grid View

struct ImageGridView: View {
    enum Layout {
        static let aspectRatio: CGFloat = 3 / 2
        static let spacing: CGFloat = 14
        static let horizontalInset: CGFloat = 12
        static let selectionInset: CGFloat = 6

        static func columnCount(availableWidth: CGFloat, thumbnailWidth: CGFloat) -> Int {
            let usableWidth = max(0, availableWidth - (horizontalInset * 2))
            let cellWidth = thumbnailWidth + selectionInset
            return max(1, Int((usableWidth + spacing) / (cellWidth + spacing)))
        }

        static func columns(availableWidth: CGFloat, thumbnailWidth: CGFloat) -> [GridItem] {
            let cellWidth = thumbnailWidth + selectionInset
            return Array(
                repeating: GridItem(.fixed(cellWidth), spacing: spacing),
                count: columnCount(availableWidth: availableWidth, thumbnailWidth: thumbnailWidth)
            )
        }
    }

    let imageFiles: [ImageFile]
    @Binding var selectedImageFileIDs: Set<UUID>
    let focusedImageFileID: UUID?
    let onSelectImage: (UUID) -> Void
    let onDoubleClickImage: (UUID) -> Void
    let thumbnailSize: CGFloat
    let isResizing: Bool
    @Binding var scrollToID: UUID?
    @Binding var columnCount: Int
    let onRename: (URL, String) -> Void
    let contactSheets: [ContactSheet]
    let onAddToContactSheet: (UUID, URL) -> Void
    let onArchive: (ImageFile) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(
                        columns: Layout.columns(
                            availableWidth: geometry.size.width,
                            thumbnailWidth: thumbnailSize
                        ),
                        alignment: .leading,
                        spacing: Layout.spacing
                    ) {
                        ForEach(imageFiles) { file in
                            GridCell(
                                file: file,
                                isSelected: selectedImageFileIDs.contains(file.id),
                                isFocused: focusedImageFileID == file.id,
                                size: thumbnailSize,
                                isResizing: isResizing,
                                aspectRatio: Layout.aspectRatio,
                                onSelectImage: onSelectImage,
                                onDoubleClickImage: onDoubleClickImage,
                                onRename: onRename,
                                contactSheets: contactSheets,
                                onAddToContactSheet: onAddToContactSheet,
                                onArchive: onArchive
                            )
                            .id(file.id)
                            .onAppear {
                                guard !isResizing else { return }
                                ImagePrefetcher.prefetchNearby(
                                    for: file,
                                    in: imageFiles,
                                    thumbnailSize: GridThumbnailSizing.decodeSize
                                )
                            }
                        }
                    }
                    .padding(.horizontal, Layout.horizontalInset)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .onAppear {
                    updateColumnCount(for: geometry.size.width)
                }
                .onChange(of: geometry.size.width) { _, width in
                    updateColumnCount(for: width)
                }
                .onChange(of: thumbnailSize) {
                    updateColumnCount(for: geometry.size.width)
                }
                .onChange(of: isResizing) { _, resizing in
                    if !resizing {
                        updateColumnCount(for: geometry.size.width)
                    }
                }
                .onChange(of: scrollToID) { _, newID in
                    if let id = newID {
                        withAnimation(MicroficheMotion.snap(reducedMotion: reduceMotion)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                        DispatchQueue.main.async { scrollToID = nil }
                    }
                }
            }
        }
        .transaction { transaction in
            if isResizing {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .animation(
            isResizing ? nil : MicroficheMotion.snap(reducedMotion: reduceMotion),
            value: thumbnailSize
        )
        .accessibilityIdentifier("image.grid")
    }

    private func updateColumnCount(for width: CGFloat) {
        guard width > 0 else { return }
        // Avoid pushing column-count changes into ContentView on every drag tick.
        // Layout still uses the live thumbnail width locally via LazyVGrid columns.
        guard !isResizing else { return }

        let count = Layout.columnCount(
            availableWidth: width,
            thumbnailWidth: thumbnailSize
        )
        if count != columnCount {
            columnCount = count
        }
    }
}

// MARK: - Grid Cell

struct GridCell: View {
    let file: ImageFile
    let isSelected: Bool
    let isFocused: Bool
    let size: CGFloat
    let isResizing: Bool
    let aspectRatio: CGFloat
    let onSelectImage: (UUID) -> Void
    let onDoubleClickImage: (UUID) -> Void
    let onRename: (URL, String) -> Void
    let contactSheets: [ContactSheet]
    let onAddToContactSheet: (UUID, URL) -> Void
    let onArchive: (ImageFile) -> Void
    @State private var isHovered = false
    @AccessibilityFocusState private var isAccessibilityFocused: Bool

    var body: some View {
        FileThumbnailView(
            file: file,
            size: size,
            decodeSize: GridThumbnailSizing.decodeSize,
            aspectRatio: aspectRatio,
            isResizing: isResizing,
            onRename: onRename
        )
        .frame(width: size, height: size / aspectRatio)
        .contentSelectionChrome(
            isSelected: isSelected,
            isFocused: isFocused || isAccessibilityFocused
        )
        .contentHoverDynamics(
            isHovered: isResizing ? false : isHovered,
            isSelected: isSelected
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            guard !isResizing else {
                isHovered = false
                return
            }
            isHovered = hovering
        }
        .overlay {
            ImageCellClickMonitor(
                onSelect: { onSelectImage(file.id) },
                onDoubleClick: { onDoubleClickImage(file.id) }
            )
        }
        .onDrag {
            ImageDropSupport.itemProvider(for: file.url)
        }
        .imageLibraryContextMenu(
            file: file,
            contactSheets: contactSheets,
            onAddToContactSheet: onAddToContactSheet,
            onArchive: onArchive
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(file.name)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(
            isSelected ? [.isButton, .isSelected] : [.isButton]
        )
        .accessibilityIdentifier("image.\(file.name)")
        .accessibilityFocused($isAccessibilityFocused)
        .accessibilityAction(.default) {
            onSelectImage(file.id)
        }
        .accessibilityAction(named: "Open Image") {
            onDoubleClickImage(file.id)
        }
    }
}

// MARK: - List View

struct ImageListView: View {
    let imageFiles: [ImageFile]
    @Binding var selectedImageFileIDs: Set<UUID>
    let focusedImageFileID: UUID?
    let onSelectImage: (UUID) -> Void
    let onDoubleClickImage: (UUID) -> Void
    @Binding var scrollToID: UUID?
    let onRename: (URL, String) -> Void
    let contactSheets: [ContactSheet]
    let onAddToContactSheet: (UUID, URL) -> Void
    let onArchive: (ImageFile) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(imageFiles) { file in
                        ImageListRow(
                            file: file,
                            isSelected: selectedImageFileIDs.contains(file.id),
                            isFocused: focusedImageFileID == file.id,
                            onSelectImage: onSelectImage,
                            onDoubleClickImage: onDoubleClickImage,
                            onRename: onRename,
                            contactSheets: contactSheets,
                            onAddToContactSheet: onAddToContactSheet,
                            onArchive: onArchive
                        )
                        .id(file.id)
                        .onAppear {
                            ImagePrefetcher.prefetchNearby(
                                for: file,
                                in: imageFiles,
                                thumbnailSize: 40,
                                thumbnailRange: 10
                            )
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
            }
            .onChange(of: scrollToID) { _, newID in
                if let id = newID {
                    withAnimation(MicroficheMotion.snap(reducedMotion: reduceMotion)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                    DispatchQueue.main.async { scrollToID = nil }
                }
            }
        }
        .accessibilityIdentifier("image.list")
    }
}

// MARK: - List Row

struct ImageListRow: View {
    let file: ImageFile
    let isSelected: Bool
    let isFocused: Bool
    let onSelectImage: (UUID) -> Void
    let onDoubleClickImage: (UUID) -> Void
    let onRename: (URL, String) -> Void
    let contactSheets: [ContactSheet]
    let onAddToContactSheet: (UUID, URL) -> Void
    let onArchive: (ImageFile) -> Void
    @State private var isHovered = false
    @Environment(\.colorSchemeContrast) private var contrast
    @AccessibilityFocusState private var isAccessibilityFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            FileThumbnailView(file: file, size: 40, onRename: onRename)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                EditableFileNameView(
                    file: file,
                    isSelected: isSelected,
                    onSelect: { onSelectImage(file.id) },
                    onRename: onRename
                )
                    .font(.body)
                    .lineLimit(1)
                Text(file.url.path)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        }
        .overlay {
            if isSelected || isFocused || isAccessibilityFocused {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        Color.accentColor.opacity(
                            contrast == .increased
                                ? 1
                                : ((isFocused || isAccessibilityFocused) ? 0.95 : 0.55)
                        ),
                        lineWidth: contrast == .increased
                            ? 3
                            : ((isFocused || isAccessibilityFocused) ? 2 : 1.5)
                    )
            }
        }
        .sidebarHoverBackground(isHovered: isHovered, isSelected: isSelected, cornerRadius: 7)
        .onHover { isHovered = $0 }
        .onDrag {
            ImageDropSupport.itemProvider(for: file.url)
        }
        .imageLibraryContextMenu(
            file: file,
            contactSheets: contactSheets,
            onAddToContactSheet: onAddToContactSheet,
            onArchive: onArchive
        )
        .overlay {
            ImageCellClickMonitor(
                onSelect: { onSelectImage(file.id) },
                onDoubleClick: { onDoubleClickImage(file.id) }
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(file.name)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(
            isSelected ? [.isButton, .isSelected] : [.isButton]
        )
        .accessibilityIdentifier("image.\(file.name)")
        .accessibilityFocused($isAccessibilityFocused)
        .accessibilityAction(.default) {
            onSelectImage(file.id)
        }
        .accessibilityAction(named: "Open Image") {
            onDoubleClickImage(file.id)
        }
    }
}

private extension View {
    @ViewBuilder
    func imageLibraryContextMenu(
        file: ImageFile,
        contactSheets: [ContactSheet],
        onAddToContactSheet: @escaping (UUID, URL) -> Void,
        onArchive: @escaping (ImageFile) -> Void
    ) -> some View {
        contextMenu {
            if !contactSheets.isEmpty {
                Menu("Add to Contact Sheet") {
                    ForEach(contactSheets) { sheet in
                        Button(sheet.name) {
                            onAddToContactSheet(sheet.id, file.url)
                        }
                    }
                }
            }

            Button("Move to Archive") {
                onArchive(file)
            }
        }
    }
}

// MARK: - Editable File Name

struct EditableFileNameView: View {
    let file: ImageFile
    let isSelected: Bool
    let onSelect: () -> Void
    let onRename: (URL, String) -> Void

    @State private var isEditing = false
    @State private var newName: String
    @FocusState private var isFocused: Bool

    init(
        file: ImageFile,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onRename: @escaping (URL, String) -> Void
    ) {
        self.file = file
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onRename = onRename
        _newName = State(initialValue: file.name)
    }

    var body: some View {
        if isEditing {
            TextField("New name", text: $newName, onCommit: commitRename)
            .focused($isFocused)
            .onChange(of: isFocused) { _, isFocused in
                if !isFocused {
                    commitRename()
                }
            }
        } else {
            Text(file.name)
                .highPriorityGesture(
                    TapGesture(count: 1)
                        .onEnded {
                            if isSelected {
                                beginRenaming()
                            } else {
                                onSelect()
                            }
                        }
                )
        }
    }

    private func beginRenaming() {
        newName = file.name
        isEditing = true
        DispatchQueue.main.async {
            isFocused = true
        }
    }

    private func commitRename() {
        guard isEditing else { return }

        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty, trimmedName != file.name {
            onRename(file.url, trimmedName)
        } else {
            newName = file.name
        }
        isEditing = false
    }
}
