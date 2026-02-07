//
//  MainContentView.swift
//  Microfiche
//
//  Created by David Hoang on 6/8/25.
//

import SwiftUI

// MARK: - Main Content

struct MainContentView: View {
    let imageFiles: [ImageFile]
    @Binding var viewMode: ViewMode
    @Binding var gridThumbnailSize: GridThumbnailSize
    @Binding var gridColumnCount: Int
    @Binding var selectedImageFileIDs: Set<UUID>
    let onSelectImage: (UUID) -> Void
    let onDoubleClickImage: (UUID) -> Void
    @Binding var scrollToID: UUID?
    let onRename: (URL, String) -> Void
    let contactSheets: [ContactSheet]
    let onAddToContactSheet: (UUID, URL) -> Void
    @State private var lastKnownWidth: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color(NSColor.separatorColor))

            VStack {
                if imageFiles.isEmpty {
                    Spacer()
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(.bottom)
                    Text("No images found. Link a folder to begin.")
                        .foregroundColor(.secondary)
                    Spacer()
                } else {
                    if viewMode == .grid {
                        ImageGridView(
                            imageFiles: imageFiles,
                            selectedImageFileIDs: $selectedImageFileIDs,
                            onSelectImage: onSelectImage,
                            onDoubleClickImage: onDoubleClickImage,
                            thumbnailSize: gridThumbnailSize,
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
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WidthReader { width in
            updateColumns(for: width)
        })
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            if viewMode == .grid {
                ToolbarItem {
                    Picker("Size", selection: $gridThumbnailSize) {
                        ForEach(GridThumbnailSize.allCases) { size in
                            Text(size.rawValue).tag(size)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 150)
                    .padding(.trailing)
                }
            }
        }
        .toolbarBackground(Color(NSColor.windowBackgroundColor), for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: -2, y: 0)
        .padding(.leading, 2)
        .padding(.trailing, 2)
        .padding(.vertical, 2)
        .onChange(of: gridThumbnailSize) {
            updateColumns(for: lastKnownWidth)
        }
    }

    private func updateColumns(for width: CGFloat) {
        lastKnownWidth = width
        let horizontalPadding: CGFloat = 64
        let spacing: CGFloat = 20
        let thumb = gridThumbnailSize.pointSize
        let itemOuterWidth: CGFloat = thumb + 12
        let usableWidth = max(0, width - horizontalPadding)
        let computed = max(1, Int((usableWidth + spacing) / (itemOuterWidth + spacing)))
        if computed != gridColumnCount { gridColumnCount = computed }
    }
}

// MARK: - Grid View

struct ImageGridView: View {
    let imageFiles: [ImageFile]
    @Binding var selectedImageFileIDs: Set<UUID>
    let onSelectImage: (UUID) -> Void
    let onDoubleClickImage: (UUID) -> Void
    let thumbnailSize: GridThumbnailSize
    @Binding var scrollToID: UUID?
    @Binding var columnCount: Int
    let onRename: (URL, String) -> Void
    let contactSheets: [ContactSheet]
    let onAddToContactSheet: (UUID, URL) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 20) {
                    ForEach(imageFiles) { file in
                        GridCell(
                            file: file,
                            isSelected: selectedImageFileIDs.contains(file.id),
                            size: thumbnailSize.pointSize,
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
                                thumbnailSize: thumbnailSize.pointSize
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .onChange(of: scrollToID) { _, newID in
                if let id = newID {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                    DispatchQueue.main.async { scrollToID = nil }
                }
            }
        }
        .animation(.spring(), value: thumbnailSize)
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 20), count: max(1, columnCount))
    }
}

// MARK: - Grid Cell

struct GridCell: View {
    let file: ImageFile
    let isSelected: Bool
    let size: CGFloat
    let onSelectImage: (UUID) -> Void
    let onDoubleClickImage: (UUID) -> Void
    let onRename: (URL, String) -> Void
    let contactSheets: [ContactSheet]
    let onAddToContactSheet: (UUID, URL) -> Void

    var body: some View {
        VStack {
            FileThumbnailView(file: file, size: size, onRename: onRename)
                .frame(width: size, height: size)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: isSelected ? 4 : 3)
        )
        .shadow(color: isSelected ? Color.accentColor.opacity(0.4) : .clear, radius: isSelected ? 10 : 0)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleClickImage(file.id) }
        .onTapGesture { onSelectImage(file.id) }
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
            List {
                ForEach(imageFiles) { file in
                    HStack {
                        FileThumbnailView(file: file, size: 40, onRename: onRename)
                            .frame(width: 40, height: 40)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                        VStack(alignment: .leading) {
                            EditableFileNameView(file: file, onRename: onRename)
                                .font(.body)
                                .lineLimit(1)
                            Text(file.url.path)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .background(selectedImageFileIDs.contains(file.id) ? Color.accentColor.opacity(0.2) : Color.clear)
                    .simultaneousGesture(
                        TapGesture(count: 1)
                            .onEnded { _ in onSelectImage(file.id) }
                    )
                    .simultaneousGesture(
                        TapGesture(count: 2)
                            .onEnded { _ in onDoubleClickImage(file.id) }
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
            .listStyle(PlainListStyle())
            .onChange(of: scrollToID) { _, newID in
                if let id = newID {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                    DispatchQueue.main.async { scrollToID = nil }
                }
            }
        }
    }
}

// MARK: - Editable File Name

struct EditableFileNameView: View {
    let file: ImageFile
    let onRename: (URL, String) -> Void

    @State private var isEditing = false
    @State private var newName: String
    @FocusState private var isFocused: Bool

    init(file: ImageFile, onRename: @escaping (URL, String) -> Void) {
        self.file = file
        self.onRename = onRename
        _newName = State(initialValue: file.name)
    }

    var body: some View {
        if isEditing {
            TextField("New name", text: $newName, onCommit: {
                onRename(file.url, newName)
                isEditing = false
            })
            .focused($isFocused)
            .onChange(of: isFocused) { _, isFocused in
                if !isFocused {
                    isEditing = false
                }
            }
        } else {
            Text(file.name)
                .highPriorityGesture(
                    TapGesture(count: 2)
                        .onEnded {
                            self.isEditing = true
                            self.isFocused = true
                        }
                )
        }
    }
}
