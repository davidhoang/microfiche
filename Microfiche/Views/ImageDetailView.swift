//
//  ImageDetailView.swift
//  Microfiche
//
//  Created by David Hoang on 6/8/25.
//

import SwiftUI
import PDFKit

// MARK: - Reusable Chip Section

struct EditableChipSection: View {
    let title: String
    let itemName: String
    @Binding var items: [String]
    @Binding var isEditing: Bool
    @Binding var newItem: String
    let chipColor: Color
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button(action: {
                    isEditing.toggle()
                    if !isEditing { onSave() }
                }) {
                    Image(systemName: isEditing ? "checkmark" : "plus")
                }
                .buttonStyle(BorderlessButtonStyle())
            }

            if isEditing {
                HStack {
                    TextField("Add \(itemName)", text: $newItem)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("Add") {
                        if !newItem.isEmpty && !items.contains(newItem) {
                            items.append(newItem)
                            newItem = ""
                            onSave()
                        }
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
            }

            if items.isEmpty {
                Text("No \(title.lowercased())")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 2), spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        HStack {
                            Text(item)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(chipColor)
                                .cornerRadius(8)
                            Spacer()
                            if isEditing {
                                Button(action: {
                                    items.removeAll { $0 == item }
                                    onSave()
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Image Detail View

struct ImageDetailView: View {
    let file: ImageFile
    @Binding var isInspectorPresented: Bool
    let onBack: () -> Void

    @State private var tags: [String] = []
    @State private var labels: [String] = []
    @State private var comments: String = ""
    @State private var whereFrom: String = ""
    @State private var isEditingTags = false
    @State private var isEditingLabels = false
    @State private var isEditingComments = false
    @State private var isEditingWhereFrom = false
    @State private var newTag: String = ""
    @State private var newLabel: String = ""
    @State private var detailImage: NSImage?
    @State private var isLoadingImage = true
    @State private var imageRequestURL: URL?

    var body: some View {
        ZStack {
            Color(NSColor.textBackgroundColor)
                .ignoresSafeArea()

            Group {
                if file.url.pathExtension.lowercased() == "pdf" {
                    PDFKitView(url: file.url)
                } else if file.url.pathExtension.lowercased() == "svg" {
                    SVGImageView(url: file.url)
                        .aspectRatio(contentMode: .fit)
                } else if let image = detailImage {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else if isLoadingImage {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(28)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: onBack) {
                    Image(systemName: "chevron.backward")
                }
                .help("Back to Library")
            }

            ToolbarItem(placement: .principal) {
                Text(file.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }

            ToolbarItemGroup {
                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help(isInspectorPresented ? "Hide Info" : "Show Info")

                ShareLink(item: file.url) {
                    Image(systemName: "square.and.arrow.up")
                }

                Button(action: {}) {
                    Image(systemName: "ellipsis")
                }
                .help("More")
            }
        }
        .inspector(isPresented: $isInspectorPresented) {
            metadataInspector
                .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
        }
        .task(id: file.id) {
            loadMetadata()
            loadDetailImage()
        }
        .onDisappear {
            saveMetadata()
        }
    }

    private var metadataInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                EditableChipSection(
                    title: "Tags",
                    itemName: "tag",
                    items: $tags,
                    isEditing: $isEditingTags,
                    newItem: $newTag,
                    chipColor: Color.accentColor.opacity(0.16),
                    onSave: saveMetadata
                )

                EditableChipSection(
                    title: "Labels",
                    itemName: "label",
                    items: $labels,
                    isEditing: $isEditingLabels,
                    newItem: $newLabel,
                    chipColor: Color.orange.opacity(0.16),
                    onSave: saveMetadata
                )

                editableTextSection(
                    title: "Comments",
                    placeholder: "No comments",
                    text: $comments,
                    isEditing: $isEditingComments,
                    isMultiline: true
                )

                editableTextSection(
                    title: "Where From",
                    placeholder: "No source specified",
                    text: $whereFrom,
                    isEditing: $isEditingWhereFrom,
                    isMultiline: false
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("File Info")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 6) {
                        InfoRow(label: "Name", value: file.name)
                        InfoRow(label: "Path", value: file.url.path)
                        InfoRow(label: "Type", value: file.url.pathExtension.uppercased())

                        if let fileSize = file.url.formattedFileSize() {
                            InfoRow(label: "Size", value: fileSize)
                        }
                        if let creationDate = file.url.formattedCreationDate() {
                            InfoRow(label: "Created", value: creationDate)
                        }
                        if let modificationDate = file.url.formattedModificationDate() {
                            InfoRow(label: "Modified", value: modificationDate)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func editableTextSection(
        title: String,
        placeholder: String,
        text: Binding<String>,
        isEditing: Binding<Bool>,
        isMultiline: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button {
                    isEditing.wrappedValue.toggle()
                    if !isEditing.wrappedValue { saveMetadata() }
                } label: {
                    Image(systemName: isEditing.wrappedValue ? "checkmark" : "pencil")
                }
                .buttonStyle(.borderless)
            }

            if isEditing.wrappedValue {
                if isMultiline {
                    TextEditor(text: text)
                        .frame(minHeight: 88)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color(NSColor.separatorColor))
                        }
                } else {
                    TextField("Enter source", text: text)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { saveMetadata() }
                }
            } else {
                Text(text.wrappedValue.isEmpty ? placeholder : text.wrappedValue)
                    .foregroundStyle(text.wrappedValue.isEmpty ? .secondary : .primary)
                    .italic(text.wrappedValue.isEmpty)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Metadata

    private func loadMetadata() {
        tags = []
        labels = []
        comments = ""
        whereFrom = ""
        isEditingTags = false
        isEditingLabels = false
        isEditingComments = false
        isEditingWhereFrom = false

        var loadedFromFileSystem = false

        if let tagsData = try? file.url.extendedAttribute(forName: "com.microfiche.tags"),
           let tagsString = String(data: tagsData, encoding: .utf8) {
            tags = tagsString.components(separatedBy: ",").filter { !$0.isEmpty }
            loadedFromFileSystem = true
        }

        if let labelsData = try? file.url.extendedAttribute(forName: "com.microfiche.labels"),
           let labelsString = String(data: labelsData, encoding: .utf8) {
            labels = labelsString.components(separatedBy: ",").filter { !$0.isEmpty }
            loadedFromFileSystem = true
        }

        if let commentsData = try? file.url.extendedAttribute(forName: "com.microfiche.comments"),
           let commentsString = String(data: commentsData, encoding: .utf8) {
            comments = commentsString
            loadedFromFileSystem = true
        }

        if let whereFromData = try? file.url.extendedAttribute(forName: "com.microfiche.whereFrom"),
           let whereFromString = String(data: whereFromData, encoding: .utf8) {
            whereFrom = whereFromString
            loadedFromFileSystem = true
        }

        if !loadedFromFileSystem {
            loadFromUserDefaults()
        }
    }

    private func saveMetadata() {
        guard FileManager.default.isWritableFile(atPath: file.url.path) else {
            saveToUserDefaults()
            return
        }

        do {
            try file.url.setFinderComment(comments)
            try file.url.setFinderTagsAndLabels(tags: tags, labels: labels)
        } catch {
            saveToUserDefaults()
        }
    }

    private func saveToUserDefaults() {
        let metadata: [String: Any] = [
            "tags": tags,
            "labels": labels,
            "comments": comments,
            "whereFrom": whereFrom
        ]

        let key = "metadata_\(file.id.uuidString)"
        UserDefaults.standard.set(metadata, forKey: key)
    }

    private func loadFromUserDefaults() {
        let key = "metadata_\(file.id.uuidString)"
        if let metadata = UserDefaults.standard.dictionary(forKey: key) {
            tags = metadata["tags"] as? [String] ?? []
            labels = metadata["labels"] as? [String] ?? []
            comments = metadata["comments"] as? String ?? ""
            whereFrom = metadata["whereFrom"] as? String ?? ""
        }
    }

    private func loadDetailImage() {
        detailImage = nil
        isLoadingImage = true
        imageRequestURL = file.url

        guard !["pdf", "svg"].contains(file.url.pathExtension.lowercased()) else {
            isLoadingImage = false
            return
        }

        if let cached = PreviewImageCache.shared.getImage(for: file.url) {
            detailImage = cached
            isLoadingImage = false
            return
        }

        let requestedURL = file.url
        PreviewImageCache.shared.preloadImage(for: requestedURL) { image in
            guard imageRequestURL == requestedURL else { return }
            detailImage = image
            isLoadingImage = false
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
            Spacer()
        }
    }
}
