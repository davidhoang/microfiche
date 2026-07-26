//
//  ImageDetailView.swift
//  Microfiche
//
//  Focused image canvas and the persistent library metadata inspector.
//

import AppKit
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

                Menu {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([file.url])
                    }
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(file.url.path, forType: .string)
                    }
                } label: {
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

    @State private var finderLabel: FinderLabel = .none
    @State private var tags: [String] = []
    @State private var comments = ""
    @State private var whereFrom = ""
    @State private var isEditingTags = false
    @State private var isEditingComments = false
    @State private var isEditingWhereFrom = false
    @State private var newTag = ""
    @State private var saveError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                headerSection

                FinderLabelPicker(selection: finderLabel) { label in
                    applyFinderLabel(label)
                }

                EditableChipSection(
                    title: "Tags",
                    subtitle: "Finder tags",
                    itemName: "tag",
                    items: $tags,
                    isEditing: $isEditingTags,
                    newItem: $newTag,
                    chipColor: Color.accentColor.opacity(0.16),
                    onSave: saveMetadata
                )

                editableTextSection(
                    title: "Comments",
                    subtitle: "Finder comments",
                    placeholder: "No comments",
                    text: $comments,
                    isEditing: $isEditingComments,
                    isMultiline: true
                )

                editableTextSection(
                    title: "Where From",
                    subtitle: "Stored in Microfiche",
                    placeholder: "No source specified",
                    text: $whereFrom,
                    isEditing: $isEditingWhereFrom,
                    isMultiline: false
                )

                fileInfoSection

                if let saveError {
                    Text(saveError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
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

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(file.name)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(2)
                .textSelection(.enabled)

            Text(file.url.deletingLastPathComponent().path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private var fileInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("File Info")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
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

    @ViewBuilder
    private func editableTextSection(
        title: String,
        subtitle: String? = nil,
        placeholder: String,
        text: Binding<String>,
        isEditing: Binding<Bool>,
        isMultiline: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Button {
                    isEditing.wrappedValue.toggle()
                    if !isEditing.wrappedValue { saveMetadata() }
                } label: {
                    Image(systemName: isEditing.wrappedValue ? "checkmark" : "pencil")
                }
                .buttonStyle(.borderless)
                .help(isEditing.wrappedValue ? "Done" : "Edit \(title)")
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
        isEditingTags = false
        isEditingComments = false
        isEditingWhereFrom = false
        newTag = ""
        saveError = nil

        let local = ImageMetadataStore.shared.metadata(for: file.url)
        let native = NativeFileMetadataService.load(from: file.url)

        finderLabel = native.label
        tags = native.tagNames.isEmpty ? local.tags : native.tagNames
        comments = native.comment.isEmpty ? local.comments : native.comment
        whereFrom = local.whereFrom

        if native.label == .none,
           let migrated = FinderLabel.migrating(from: local.labels) {
            applyFinderLabel(migrated)
        } else if !local.labels.isEmpty {
            // Drop obsolete free-text labels once native labels own this field.
            persistLocalMetadata()
        }
    }

    private func applyFinderLabel(_ label: FinderLabel) {
        finderLabel = label
        do {
            try NativeFileMetadataService.setLabel(label, for: file.url)
            persistLocalMetadata()
            saveError = nil
        } catch {
            saveError = "Couldn’t update Finder label: \(error.localizedDescription)"
        }
    }

    private func saveMetadata() {
        do {
            try NativeFileMetadataService.save(
                NativeFileMetadata(
                    label: finderLabel,
                    tagNames: tags,
                    comment: comments
                ),
                for: file.url
            )
            persistLocalMetadata()
            saveError = nil
        } catch {
            // Keep a local copy even when the file system rejects native writes.
            persistLocalMetadata()
            saveError = "Couldn’t write Finder metadata: \(error.localizedDescription)"
        }
    }

    private func persistLocalMetadata() {
        ImageMetadataStore.shared.save(
            ImageMetadata(
                tags: tags,
                labels: [],
                comments: comments,
                whereFrom: whereFrom
            ),
            for: file.url
        )
    }
}

// MARK: - Finder Label Picker

struct FinderLabelPicker: View {
    let selection: FinderLabel
    let onSelect: (FinderLabel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Label")
                    .font(.headline)
                Text("Finder color label")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 10) {
                labelDot(for: .none)

                ForEach(FinderLabel.coloredCases) { label in
                    labelDot(for: label)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Finder label")

            Text(selection == .none ? "No label" : selection.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func labelDot(for label: FinderLabel) -> some View {
        let isSelected = selection == label

        return Button {
            onSelect(label)
        } label: {
            ZStack {
                if label == .none {
                    Circle()
                        .strokeBorder(Color(NSColor.tertiaryLabelColor), lineWidth: 1.5)
                        .background(Circle().fill(Color(NSColor.controlBackgroundColor)))
                        .overlay {
                            Image(systemName: "nosign")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                } else if let color = label.swatchColor {
                    Circle()
                        .fill(color)
                        .overlay {
                            Circle()
                                .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
                        }
                }
            }
            .frame(width: 22, height: 22)
            .padding(3)
            .overlay {
                if isSelected {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.85), lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .help(label.displayName)
        .accessibilityLabel(label.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Shared Inspector Components

struct EditableChipSection: View {
    let title: String
    var subtitle: String? = nil
    let itemName: String
    @Binding var items: [String]
    @Binding var isEditing: Bool
    @Binding var newItem: String
    let chipColor: Color
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Button {
                    isEditing.toggle()
                    if !isEditing { onSave() }
                } label: {
                    Image(systemName: isEditing ? "checkmark" : "plus")
                }
                .buttonStyle(.borderless)
                .help(isEditing ? "Done" : "Add \(itemName)")
            }

            if isEditing {
                HStack {
                    TextField("Add \(itemName)", text: $newItem)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addItem)
                    Button("Add", action: addItem)
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

    private func addItem() {
        let value = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !items.contains(value) else { return }
        items.append(value)
        newItem = ""
        onSave()
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
