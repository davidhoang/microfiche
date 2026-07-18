//
//  SidebarView.swift
//  Microfiche
//
//  Created by David Hoang on 6/8/25.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Sidebar

struct SidebarView: View {
    let folderURLs: [URL]
    let contactSheets: [ContactSheet]
    let selection: Selection?
    let onWidthChange: (CGFloat) -> Void
    let onLinkFolder: () -> Void
    let onSelect: (Selection) -> Void
    let onRemoveFolder: (URL) -> Void
    let onCreateContactSheet: () -> Void
    let onRenameContactSheet: (UUID, String) -> Void
    let onDeleteContactSheet: (UUID) -> Void
    let onDropToContactSheet: (UUID, [URL]) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                SidebarSection(
                    eyebrow: "Library",
                    title: "Folders",
                    detail: folderSectionDetail,
                    actionHelp: "Add Folder",
                    action: onLinkFolder
                ) {
                    SidebarStaticRow(
                        title: "All Images",
                        systemImage: "photo.stack",
                        isSelected: selection == .all,
                        action: { onSelect(.all) }
                    )

                    if folderURLs.isEmpty {
                        SidebarEmptyMessage("No folders linked. Add one to start browsing.")
                    } else {
                        ForEach(folderURLs, id: \.self) { url in
                            SidebarStaticRow(
                                title: url.lastPathComponent,
                                systemImage: "folder",
                                isSelected: selection == .folder(url),
                                action: { onSelect(.folder(url)) }
                            )
                            .contextMenu {
                                Button("Remove Folder", role: .destructive) {
                                    onRemoveFolder(url)
                                }
                            }
                        }
                    }
                }

                SidebarSection(
                    eyebrow: "Collections",
                    title: "Contact Sheets",
                    detail: contactSheetSectionDetail,
                    actionHelp: "New Contact Sheet",
                    action: onCreateContactSheet
                ) {
                    if contactSheets.isEmpty {
                        SidebarEmptyMessage("No contact sheets yet. Create one to collect a review set.")
                    } else {
                        ForEach(contactSheets) { sheet in
                            ContactSheetSidebarItem(
                                contactSheet: sheet,
                                isSelected: selection == .contactSheet(sheet.id),
                                onSelect: {
                                    onSelect(.contactSheet(sheet.id))
                                },
                                onRename: { newName in
                                    onRenameContactSheet(sheet.id, newName)
                                },
                                onDelete: {
                                    onDeleteContactSheet(sheet.id)
                                },
                                onDrop: { urls in
                                    onDropToContactSheet(sheet.id, urls)
                                }
                            )
                        }
                    }
                }
            }
            .padding(14)
            .background(sidebarSurface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(sidebarBackground)
        .background(WidthReader(onChange: onWidthChange))
    }

    private var folderSectionDetail: String {
        if folderURLs.isEmpty {
            return "Link folders once, then browse everything from one place."
        }

        return "\(folderURLs.count) linked \(folderURLs.count == 1 ? "folder" : "folders")"
    }

    private var contactSheetSectionDetail: String {
        if contactSheets.isEmpty {
            return "Curated sets stay organized here for quick review."
        }

        return "\(contactSheets.count) saved \(contactSheets.count == 1 ? "collection" : "collections")"
    }

    private var sidebarBackground: some View {
        LinearGradient(
            colors: [
                Color(NSColor.windowBackgroundColor),
                Color(NSColor.windowBackgroundColor).opacity(0.97),
                Color(NSColor.underPageBackgroundColor).opacity(0.28)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var sidebarSurface: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.24))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
            }
    }
}

// MARK: - Shared Sidebar Components

private struct SidebarSection<Content: View>: View {
    let eyebrow: String
    let title: String
    let detail: String
    let actionHelp: String
    let action: () -> Void
    let content: Content

    init(
        eyebrow: String,
        title: String,
        detail: String,
        actionHelp: String,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.detail = detail
        self.actionHelp = actionHelp
        self.action = action
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 10, weight: .medium))
                        .tracking(0.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(.secondary)

                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(.primary)

                    Text(detail)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)

                Spacer(minLength: 12)

                SidebarAddButton(action: action)
                    .help(actionHelp)
            }

            VStack(alignment: .leading, spacing: 4) {
                content
            }
        }
    }
}

private struct SidebarAddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary.opacity(0.82))
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(0.055))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarStaticRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 24, height: 24)

            Text(title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)
        }
        .sidebarRow(isSelected: isSelected)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: action)
    }
}

private struct SidebarRowModifier: ViewModifier {
    let isSelected: Bool
    let isDropTargeted: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isDropTargeted ? 2 : 1)
            )
            .animation(.easeInOut(duration: 0.18), value: isSelected)
            .animation(.easeInOut(duration: 0.18), value: isDropTargeted)
    }

    private var borderColor: Color {
        if isDropTargeted {
            return Color.accentColor.opacity(0.82)
        }

        if isSelected {
            return Color.accentColor.opacity(0.35)
        }

        return Color.clear
    }
}

private extension View {
    func sidebarRow(isSelected: Bool, isDropTargeted: Bool = false) -> some View {
        modifier(SidebarRowModifier(isSelected: isSelected, isDropTargeted: isDropTargeted))
    }
}

private struct SidebarEmptyMessage: View {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
    }
}

// MARK: - Contact Sheet Sidebar Item

struct ContactSheetSidebarItem: View {
    let contactSheet: ContactSheet
    let isSelected: Bool
    @State private var isEditing: Bool = false
    @State private var editedName: String
    @State private var isDropTargeted: Bool = false
    @FocusState private var isNameFocused: Bool
    let onSelect: () -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void
    let onDrop: ([URL]) -> Void

    init(contactSheet: ContactSheet, isSelected: Bool, onSelect: @escaping () -> Void, onRename: @escaping (String) -> Void, onDelete: @escaping () -> Void, onDrop: @escaping ([URL]) -> Void) {
        self.contactSheet = contactSheet
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onRename = onRename
        self.onDelete = onDelete
        self.onDrop = onDrop
        _editedName = State(initialValue: contactSheet.name)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 24, height: 24)

            if isEditing {
                TextField("Name", text: $editedName, onCommit: commitRename)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
                    .onChange(of: isNameFocused) { _, isFocused in
                        if !isFocused {
                            commitRename()
                        }
                    }
            } else {
                Text(contactSheet.name)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
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

            Spacer(minLength: 8)

            Text("\(contactSheet.imageIDs.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.black.opacity(0.05))
                )
        }
        .sidebarRow(isSelected: isSelected, isDropTargeted: isDropTargeted)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture {
            if !isEditing {
                onSelect()
            }
        }
        .onDrop(of: [UTType.fileURL, UTType.url, UTType.image], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
        .contextMenu {
            Button("Rename") {
                beginRenaming()
            }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }

    private func commitRename() {
        guard isEditing else { return }

        let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            editedName = trimmedName
            onRename(trimmedName)
        }
        isEditing = false
    }

    private func beginRenaming() {
        editedName = contactSheet.name
        isEditing = true
        DispatchQueue.main.async {
            isNameFocused = true
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            let typeIdentifiers = [
                UTType.fileURL.identifier,
                UTType.url.identifier,
                "public.file-url"
            ]

            for typeIdentifier in typeIdentifiers {
                if provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
                    provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { (urlData, error) in
                        DispatchQueue.main.async {
                            guard error == nil else { return }

                            var fileURL: URL?

                            if let url = urlData as? URL {
                                fileURL = url
                            } else if let url = urlData as? NSURL {
                                fileURL = url as URL
                            } else if let data = urlData as? Data {
                                fileURL = URL(dataRepresentation: data, relativeTo: nil)
                            } else if let path = urlData as? String {
                                fileURL = URL(fileURLWithPath: path)
                            }

                            if let fileURL = fileURL, fileURL.isFileURL {
                                self.onDrop([fileURL])
                            }
                        }
                    }
                    break
                }
            }
        }
    }
}
