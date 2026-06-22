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
            LazyVStack(alignment: .leading, spacing: 18) {
                SidebarSectionCard(
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
                        SidebarEmptyMessage(
                            title: "No folders linked",
                            message: "Use the plus button to add a folder and start browsing."
                        )
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

                SidebarSectionCard(
                    eyebrow: "Collections",
                    title: "Contact Sheets",
                    detail: contactSheetSectionDetail,
                    actionHelp: "New Contact Sheet",
                    action: onCreateContactSheet
                ) {
                    if contactSheets.isEmpty {
                        SidebarEmptyMessage(
                            title: "No contact sheets yet",
                            message: "Create one to group a delivery set, moodboard, or review pass."
                        )
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
                Color(NSColor.underPageBackgroundColor).opacity(0.96)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.white.opacity(0.22))
                .frame(width: 180, height: 180)
                .blur(radius: 72)
                .offset(x: 54, y: -58)
        }
    }
}

// MARK: - Shared Sidebar Components

private struct SidebarSectionCard<Content: View>: View {
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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(.secondary)

                    Text(title)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(.primary)

                    Text(detail)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)

                Spacer(minLength: 12)

                SidebarAddButton(action: action)
                    .help(actionHelp)
            }

            Rectangle()
                .fill(Color.white.opacity(0.32))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
        .padding(14)
        .background(sectionBackground)
    }

    private var sectionBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.58))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.48), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 10)
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
                        .fill(.thinMaterial)
                        .overlay(
                            Circle()
                                .fill(Color.white.opacity(0.22))
                        )
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
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
        SidebarRowSurface(isSelected: isSelected) {
            SidebarSymbolBadge(systemImage: systemImage, isSelected: isSelected)

            Text(title)
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: action)
    }
}

private struct SidebarRowSurface<Content: View>: View {
    let isSelected: Bool
    let isDropTargeted: Bool
    let content: Content

    init(
        isSelected: Bool,
        isDropTargeted: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.isDropTargeted = isDropTargeted
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.34))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isDropTargeted ? 2 : 1)
        )
        .shadow(
            color: isSelected ? Color.accentColor.opacity(0.16) : Color.black.opacity(0.04),
            radius: isSelected ? 10 : 6,
            x: 0,
            y: 4
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

        return Color.white.opacity(0.52)
    }
}

private struct SidebarSymbolBadge: View {
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.44))

            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
        }
        .frame(width: 28, height: 28)
    }
}

private struct SidebarCountBadge: View {
    let text: String
    let isSelected: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.black.opacity(0.05))
            )
    }
}

private struct SidebarEmptyMessage: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary.opacity(0.84))

            Text(message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.36), lineWidth: 1)
        )
    }
}

// MARK: - Contact Sheet Sidebar Item

struct ContactSheetSidebarItem: View {
    let contactSheet: ContactSheet
    let isSelected: Bool
    @State private var isEditing: Bool = false
    @State private var editedName: String
    @State private var isDropTargeted: Bool = false
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
        SidebarRowSurface(isSelected: isSelected, isDropTargeted: isDropTargeted) {
            SidebarSymbolBadge(systemImage: "square.grid.2x2", isSelected: isSelected)

            if isEditing {
                TextField("Name", text: $editedName, onCommit: commitRename)
                    .textFieldStyle(.roundedBorder)
            } else {
                Text(contactSheet.name)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .onTapGesture(count: 2) {
                        isEditing = true
                    }
            }

            Spacer(minLength: 8)

            SidebarCountBadge(
                text: "\(contactSheet.imageIDs.count)",
                isSelected: isSelected
            )
        }
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
                isEditing = true
            }
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }

    private func commitRename() {
        let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            editedName = trimmedName
            onRename(trimmedName)
        }
        isEditing = false
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
