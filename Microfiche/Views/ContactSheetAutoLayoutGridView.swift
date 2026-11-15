//
//  ContactSheetAutoLayoutGridView.swift
//  Microfiche
//

import SwiftUI

struct ContactSheetAutoLayoutGridView: View {
    let imageFiles: [ImageFile]
    @Binding var selectedImageFileIDs: Set<UUID>
    let focusedImageFileID: UUID?
    let onSelectImage: (UUID) -> Void
    let onDoubleClickImage: (UUID) -> Void
    let targetRowHeight: CGFloat
    let isResizing: Bool
    @Binding var scrollToID: UUID?
    let onRename: (URL, String) -> Void
    let onReorderContactSheetImage: (URL, URL) -> Void
    let contactSheets: [ContactSheet]
    let activeContactSheetID: UUID?
    let onAddToContactSheet: (UUID, URL) -> Void
    let onRemoveFromActiveContactSheet: ((ImageFile) -> Void)?
    let onArchive: (ImageFile) -> Void

    @State private var aspectRatios: [UUID: CGFloat] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var prefetcher = ViewportImagePrefetcher()

    private var layoutConfiguration: ContactSheetAutoLayout.Configuration {
        var configuration = ContactSheetAutoLayout.Configuration()
        configuration.targetRowHeight = targetRowHeight
        configuration.minRowHeight = max(72, targetRowHeight * 0.55)
        configuration.maxRowHeight = max(
            ContactSheetLayoutMetrics.preferredThumbnailSize,
            targetRowHeight * 1.65
        )
        return configuration
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    autoLayoutCanvas(width: geometry.size.width)
                }
                .accessibilityIdentifier("contact-sheet.auto-layout.grid")
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
        .task(id: aspectLoadSignature) {
            await loadMissingAspectRatios()
        }
        .onChange(of: imageFiles.map(\.id)) { _, ids in
            let active = Set(ids)
            aspectRatios = aspectRatios.filter { active.contains($0.key) }
            prefetcher.refresh(
                imageFiles: imageFiles,
                thumbnailSize: GridThumbnailSizing.decodeSize
            )
        }
        .onChange(of: focusedImageFileID) { _, id in
            prefetcher.prioritize(
                id: id,
                in: imageFiles,
                thumbnailSize: GridThumbnailSizing.decodeSize
            )
        }
        .onAppear {
            prefetcher.refresh(
                imageFiles: imageFiles,
                thumbnailSize: GridThumbnailSizing.decodeSize
            )
        }
        .onDisappear {
            prefetcher.cancel()
        }
    }

    private var aspectLoadSignature: String {
        imageFiles.map { file in
            let aspect = aspectRatios[file.id].map { String(format: "%.3f", $0) } ?? "pending"
            return "\(file.id.uuidString):\(aspect)"
        }.joined(separator: "|")
    }

    @ViewBuilder
    private func autoLayoutCanvas(width: CGFloat) -> some View {
        let items = imageFiles.map { file in
            ContactSheetLayoutItem(
                id: file.id,
                aspectRatio: aspectRatios[file.id] ?? 1
            )
        }
        let plan = ContactSheetAutoLayout.plan(
            items: items,
            availableWidth: width,
            configuration: layoutConfiguration
        )

        VStack(alignment: .leading, spacing: layoutConfiguration.spacing) {
            ForEach(Array(plan.rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: layoutConfiguration.spacing) {
                    ForEach(row.placements) { placement in
                        if let file = imageFiles.first(where: { $0.id == placement.id }),
                           let index = imageFiles.firstIndex(where: { $0.id == placement.id }) {
                            ContactSheetJustifiedCell(
                                file: file,
                                width: placement.width,
                                height: placement.height,
                                isSelected: selectedImageFileIDs.contains(file.id),
                                isFocused: focusedImageFileID == file.id,
                                isResizing: isResizing,
                                onSelectImage: onSelectImage,
                                onDoubleClickImage: onDoubleClickImage,
                                onRename: onRename,
                                onReorderContactSheetImage: onReorderContactSheetImage,
                                contactSheets: contactSheets,
                                activeContactSheetID: activeContactSheetID,
                                onAddToContactSheet: onAddToContactSheet,
                                onRemoveFromActiveContactSheet: onRemoveFromActiveContactSheet,
                                onArchive: onArchive
                            )
                            .id(file.id)
                            .onAppear {
                                guard !isResizing else { return }
                                prefetcher.itemDidAppear(
                                    at: index,
                                    in: imageFiles,
                                    thumbnailSize: GridThumbnailSizing.decodeSize
                                )
                            }
                            .onDisappear {
                                prefetcher.itemDidDisappear(
                                    at: index,
                                    in: imageFiles,
                                    thumbnailSize: GridThumbnailSizing.decodeSize
                                )
                            }
                        }
                    }
                }
                .frame(height: row.height, alignment: .topLeading)
            }
        }
        .padding(.horizontal, layoutConfiguration.horizontalInset)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: plan.contentHeight + 32, alignment: .topLeading)
    }

    private func loadMissingAspectRatios() async {
        for file in imageFiles {
            guard aspectRatios[file.id] == nil else { continue }
            let ratio = await Task.detached(priority: .utility) {
                ContactSheetImageDimensions.aspectRatio(for: file.url) ?? 1
            }.value
            guard !Task.isCancelled else { return }
            aspectRatios[file.id] = ratio
        }
    }
}

private struct ContactSheetJustifiedCell: View {
    let file: ImageFile
    let width: CGFloat
    let height: CGFloat
    let isSelected: Bool
    let isFocused: Bool
    let isResizing: Bool
    let onSelectImage: (UUID) -> Void
    let onDoubleClickImage: (UUID) -> Void
    let onRename: (URL, String) -> Void
    let onReorderContactSheetImage: (URL, URL) -> Void
    let contactSheets: [ContactSheet]
    let activeContactSheetID: UUID?
    let onAddToContactSheet: (UUID, URL) -> Void
    let onRemoveFromActiveContactSheet: ((ImageFile) -> Void)?
    let onArchive: (ImageFile) -> Void

    @State private var isHovered = false
    @State private var isReorderDropTargeted = false
    @AccessibilityFocusState private var isAccessibilityFocused: Bool

    private var decodeEdge: CGFloat {
        max(width, height, GridThumbnailSizing.decodeSize)
    }

    var body: some View {
        let aspectRatio = width / max(height, 1)

        FileThumbnailView(
            file: file,
            size: max(width, height),
            decodeSize: decodeEdge,
            aspectRatio: aspectRatio,
            isResizing: isResizing,
            onRename: onRename
        )
        .frame(width: width, height: height)
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
        .onDrop(
            of: ImageDropSupport.acceptedContentTypes,
            isTargeted: $isReorderDropTargeted,
            perform: handleContactSheetReorderDrop
        )
        .overlay {
            if isReorderDropTargeted {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .imageLibraryContextMenu(
            file: file,
            contactSheets: contactSheets,
            activeContactSheetID: activeContactSheetID,
            onAddToContactSheet: onAddToContactSheet,
            onRemoveFromActiveContactSheet: onRemoveFromActiveContactSheet,
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

    private func handleContactSheetReorderDrop(providers: [NSItemProvider]) -> Bool {
        guard ImageDropSupport.canLoadFileURL(from: providers) else { return false }

        ImageDropSupport.loadFileURLs(from: providers) { urls in
            guard let draggedURL = urls.first else { return }
            let normalizedDragged = draggedURL.standardizedFileURL
            let normalizedTarget = file.url.standardizedFileURL
            guard normalizedDragged != normalizedTarget else { return }
            onReorderContactSheetImage(normalizedDragged, normalizedTarget)
        }
        return true
    }
}