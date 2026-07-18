//
//  MainContentView.swift
//  Microfiche
//
//  Created by David Hoang on 6/8/25.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main Content

struct MainContentView: View {
    let imageFiles: [ImageFile]
    @Binding var viewMode: ViewMode
    @Binding var gridThumbnailSize: CGFloat
    @Binding var gridColumnCount: Int
    @Binding var selectedImageFileIDs: Set<UUID>
    let onSelectImage: (UUID) -> Void
    let onDoubleClickImage: (UUID) -> Void
    @Binding var scrollToID: UUID?
    let onRename: (URL, String) -> Void
    let contactSheets: [ContactSheet]
    let onAddToContactSheet: (UUID, URL) -> Void
    @State private var isResizingGrid = false

    var body: some View {
        ZStack {
            mainCanvasBackground

            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.black.opacity(0.08))
                    .frame(height: 1)

                VStack {
                    if imageFiles.isEmpty {
                        Spacer(minLength: 24)
                        EmptyLibraryStateView()
                        Spacer(minLength: 24)
                    } else {
                        if viewMode == .grid {
                            ImageGridView(
                                imageFiles: imageFiles,
                                selectedImageFileIDs: $selectedImageFileIDs,
                                onSelectImage: onSelectImage,
                                onDoubleClickImage: onDoubleClickImage,
                                thumbnailSize: gridThumbnailSize,
                                isResizing: isResizingGrid,
                                scrollToID: $scrollToID,
                                columnCount: $gridColumnCount,
                                onRename: onRename,
                                contactSheets: contactSheets,
                                onAddToContactSheet: onAddToContactSheet
                            )
                        } else {
                            ImageListView(
                                imageFiles: imageFiles,
                                selectedImageFileIDs: $selectedImageFileIDs,
                                onSelectImage: onSelectImage,
                                onDoubleClickImage: onDoubleClickImage,
                                scrollToID: $scrollToID,
                                onRename: onRename
                            )
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            .hideSharedBackgroundIfAvailable()

            if viewMode == .grid {
                ToolbarItem {
                    HStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Slider(
                            value: $gridThumbnailSize,
                            in: GridThumbnailSizing.minimum...GridThumbnailSizing.maximum,
                            onEditingChanged: handleGridResize
                        )
                        .frame(width: 110)
                        .accessibilityLabel("Thumbnail size")
                        .accessibilityValue("\(Int(gridThumbnailSize.rounded())) points")

                        Image(systemName: "photo.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                    .help("Thumbnail Size")
                }
                .hideSharedBackgroundIfAvailable()
            }
        }
        .toolbarBackground(Color(NSColor.windowBackgroundColor), for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
    }

    private var mainCanvasBackground: some View {
        LinearGradient(
            colors: [
                Color(NSColor.textBackgroundColor),
                Color(NSColor.controlBackgroundColor).opacity(0.88)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 240, height: 240)
                .blur(radius: 88)
                .offset(x: -18, y: -86)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.black.opacity(0.04))
                .frame(width: 1)
        }
    }

    private func handleGridResize(_ isEditing: Bool) {
        isResizingGrid = isEditing

        if !isEditing, let selectedID = selectedImageFileIDs.first {
            DispatchQueue.main.async {
                scrollToID = selectedID
            }
        }
    }

}

private struct EmptyLibraryStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 96, height: 96)

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                Text("LIBRARY")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(.tertiary)

                Text("No images yet")
                    .font(.system(size: 26, weight: .semibold))

                Text("Link a folder or drop images into a contact sheet to start building a library.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Grid View

struct ImageGridView: View {
    enum Layout {
        static let aspectRatio: CGFloat = 3 / 2
        static let spacing: CGFloat = 20
        static let horizontalInset: CGFloat = 16
        static let selectionInset: CGFloat = 8

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
    let onSelectImage: (UUID) -> Void
    let onDoubleClickImage: (UUID) -> Void
    let thumbnailSize: CGFloat
    let isResizing: Bool
    @Binding var scrollToID: UUID?
    @Binding var columnCount: Int
    let onRename: (URL, String) -> Void
    let contactSheets: [ContactSheet]
    let onAddToContactSheet: (UUID, URL) -> Void

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
                                size: thumbnailSize,
                                aspectRatio: Layout.aspectRatio,
                                onSelectImage: onSelectImage,
                                onDoubleClickImage: onDoubleClickImage,
                                onRename: onRename,
                                contactSheets: contactSheets,
                                onAddToContactSheet: onAddToContactSheet
                            )
                            .id(file.id)
                            .onAppear {
                                ImagePrefetcher.prefetchNearby(
                                    for: file,
                                    in: imageFiles,
                                    thumbnailSize: thumbnailSize
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
                .onChange(of: scrollToID) { _, newID in
                    if let id = newID {
                        withAnimation(.easeInOut(duration: 0.2)) {
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
            }
        }
        .animation(isResizing ? nil : .snappy(duration: 0.22), value: thumbnailSize)
    }

    private func updateColumnCount(for width: CGFloat) {
        guard width > 0 else { return }
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
    let size: CGFloat
    let aspectRatio: CGFloat
    let onSelectImage: (UUID) -> Void
    let onDoubleClickImage: (UUID) -> Void
    let onRename: (URL, String) -> Void
    let contactSheets: [ContactSheet]
    let onAddToContactSheet: (UUID, URL) -> Void
    @State private var isHovered = false

    var body: some View {
        FileThumbnailView(
            file: file,
            size: size,
            aspectRatio: aspectRatio,
            onRename: onRename
        )
        .frame(width: size, height: size / aspectRatio)
        .contentSelectionChrome(isSelected: isSelected)
        .contentHoverDynamics(isHovered: isHovered, isSelected: isSelected)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { onDoubleClickImage(file.id) }
        .onTapGesture { onSelectImage(file.id) }
        .onDrag {
            imageFileProvider(for: file.url)
        }
        .contextMenu {
            if !contactSheets.isEmpty {
                Menu("Add to Contact Sheet") {
                    ForEach(contactSheets) { sheet in
                        Button(sheet.name) {
                            onAddToContactSheet(sheet.id, file.url)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - List View

struct ImageListView: View {
    let imageFiles: [ImageFile]
    @Binding var selectedImageFileIDs: Set<UUID>
    let onSelectImage: (UUID) -> Void
    let onDoubleClickImage: (UUID) -> Void
    @Binding var scrollToID: UUID?
    let onRename: (URL, String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(imageFiles) { file in
                        ImageListRow(
                            file: file,
                            isSelected: selectedImageFileIDs.contains(file.id),
                            onSelectImage: onSelectImage,
                            onDoubleClickImage: onDoubleClickImage,
                            onRename: onRename
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
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                    DispatchQueue.main.async { scrollToID = nil }
                }
            }
        }
    }
}

// MARK: - List Row

struct ImageListRow: View {
    let file: ImageFile
    let isSelected: Bool
    let onSelectImage: (UUID) -> Void
    let onDoubleClickImage: (UUID) -> Void
    let onRename: (URL, String) -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            FileThumbnailView(file: file, size: 40, onRename: onRename)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
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
        .padding(.vertical, 7)
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.28), lineWidth: 1)
            }
        }
        .sidebarHoverBackground(isHovered: isHovered, isSelected: isSelected, cornerRadius: 9)
        .onHover { isHovered = $0 }
        .onDrag {
            imageFileProvider(for: file.url)
        }
        .simultaneousGesture(
            TapGesture(count: 1)
                .onEnded { _ in onSelectImage(file.id) }
        )
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { _ in onDoubleClickImage(file.id) }
        )
    }
}

private func imageFileProvider(for url: URL) -> NSItemProvider {
    NSItemProvider(
        item: url as NSURL,
        typeIdentifier: UTType.fileURL.identifier
    )
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
