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
    let onLinkFolder: () -> Void
    let onSelect: (Selection) -> Void
    let onRemoveFolder: (URL) -> Void
    let onCreateContactSheet: () -> Void
    let onRenameContactSheet: (UUID, String) -> Void
    let onDeleteContactSheet: (UUID) -> Void
    let onDropToContactSheet: (UUID, [URL]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Folders")
                    .font(.headline)
                Spacer()
                Button(action: onLinkFolder) {
                    Image(systemName: "plus")
                }
                .microficheIconButton()
                .help("Add Folder")
            }
            .padding([.top, .horizontal])

            List {
                HStack {
                    Image(systemName: "photo.stack")
                    Text("All")
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onSelect(.all)
                }
                .sidebarSelectionBackground(isSelected: selection == .all)
                .listRowSeparator(.hidden)

                ForEach(folderURLs, id: \.self) { url in
                    HStack {
                        Image(systemName: "folder")
                        Text(url.lastPathComponent)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelect(.folder(url))
                    }
                    .sidebarSelectionBackground(isSelected: selection == .folder(url))
                    .listRowSeparator(.hidden)
                    .contextMenu {
                        Button("Remove Folder", role: .destructive) {
                            onRemoveFolder(url)
                        }
                    }
                }
            }
            .listStyle(PlainListStyle())
            .scrollContentBackground(.hidden)

            Spacer()
                .frame(height: 24)

            HStack {
                Text("Contact Sheets")
                    .font(.headline)
                Spacer()
                Button(action: onCreateContactSheet) {
                    Image(systemName: "plus")
                }
                .microficheIconButton()
                .help("New Contact Sheet")
            }
            .padding([.horizontal])

            List {
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
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(PlainListStyle())
            .scrollContentBackground(.hidden)

            Spacer()
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
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
        HStack {
            Image(systemName: "square.grid.2x2")
            if isEditing {
                TextField("Name", text: $editedName, onCommit: {
                    if !editedName.isEmpty {
                        onRename(editedName)
                    }
                    isEditing = false
                })
                .textFieldStyle(RoundedBorderTextFieldStyle())
            } else {
                Text(contactSheet.name)
                    .onTapGesture(count: 2) {
                        isEditing = true
                    }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditing {
                onSelect()
            }
        }
        .sidebarSelectionBackground(isSelected: isSelected)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
        )
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
