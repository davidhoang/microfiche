//
//  ImageDetailView.swift
//  Microfiche
//
//  Focused image canvas and the persistent library metadata inspector.
//

import PDFKit
import SwiftUI

// MARK: - Focused Image Canvas

struct ImageDetailView: View {
    let file: ImageFile
    @Binding var isInspectorPresented: Bool
    let onBack: () -> Void

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
        .task(id: file.id) {
            loadDetailImage()
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
// MARK: - Metadata Inspector

struct ImageMetadataInspectorView: View {
    let file: ImageFile

    @State private var tags: [String] = []
    @State private var labels: [String] = []
    @State private var comments = ""
    @State private var whereFrom = ""
    @State private var isEditingTags = false
    @State private var isEditingLabels = false
    @State private var isEditingComments = false
    @State private var isEditingWhereFrom = false
    @State private var newTag = ""
    @State private var newLabel = ""

    var body: some View {
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
        .task(id: file.id) {
            loadMetadata()
        }
        .onDisappear {
            saveMetadata()
        }
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

        if let data = try? file.url.extendedAttribute(forName: "com.microfiche.tags"),
           let string = String(data: data, encoding: .utf8) {
            tags = string.components(separatedBy: ",").filter { !$0.isEmpty }
            loadedFromFileSystem = true
        }
        if let data = try? file.url.extendedAttribute(forName: "com.microfiche.labels"),
           let string = String(data: data, encoding: .utf8) {
            labels = string.components(separatedBy: ",").filter { !$0.isEmpty }
            loadedFromFileSystem = true
        }
        if let data = try? file.url.extendedAttribute(forName: "com.microfiche.comments"),
           let string = String(data: data, encoding: .utf8) {
            comments = string
            loadedFromFileSystem = true
        }
        if let data = try? file.url.extendedAttribute(forName: "com.microfiche.whereFrom"),
           let string = String(data: data, encoding: .utf8) {
            whereFrom = string
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
        UserDefaults.standard.set(metadata, forKey: "metadata_\(file.id.uuidString)")
    }

    private func loadFromUserDefaults() {
        guard let metadata = UserDefaults.standard.dictionary(
            forKey: "metadata_\(file.id.uuidString)"
        ) else { return }

        tags = metadata["tags"] as? [String] ?? []
        labels = metadata["labels"] as? [String] ?? []
        comments = metadata["comments"] as? String ?? ""
        whereFrom = metadata["whereFrom"] as? String ?? ""
    }
}

// MARK: - Shared Inspector Components

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
                Button {
                    isEditing.toggle()
                    if !isEditing { onSave() }
                } label: {
                    Image(systemName: isEditing ? "checkmark" : "plus")
                }
                .buttonStyle(.borderless)
            }

            if isEditing {
                HStack {
                    TextField("Add \(itemName)", text: $newItem)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let value = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !value.isEmpty && !items.contains(value) {
                            items.append(value)
                            newItem = ""
                            onSave()
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }

            if items.isEmpty {
                Text("No \(title.lowercased())")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88))], spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        HStack(spacing: 4) {
                            Text(item)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            if isEditing {
                                Button {
                                    items.removeAll { $0 == item }
                                    onSave()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(chipColor, in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
