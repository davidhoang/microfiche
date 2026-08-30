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
    @Binding var isMetadataPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        extendedImageCanvas
            .inspector(isPresented: $isMetadataPresented) {
                ImageMetadataInspectorView(files: [file])
                    .id(file.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(file.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }

                ToolbarItemGroup {
                    Button {
                        withAnimation(MicroficheMotion.panel(reducedMotion: reduceMotion)) {
                            isMetadataPresented.toggle()
                        }
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .help(isMetadataPresented ? "Hide Info" : "Show Info")
                    .accessibilityLabel(
                        isMetadataPresented ? "Hide inspector" : "Show inspector"
                    )
                    .accessibilityIdentifier("detail.inspector.toggle")

                    ShareLink(item: file.url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share \(file.name)")
                    .accessibilityIdentifier("detail.share")

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
                    .accessibilityLabel("More actions for \(file.name)")
                    .accessibilityIdentifier("detail.more")
                }
            }
    }

    @ViewBuilder
    private var extendedImageCanvas: some View {
        if reduceTransparency {
            imageCanvas
        } else if #available(macOS 26.0, *) {
            imageCanvas.backgroundExtensionEffect()
        } else {
            imageCanvas
        }
    }

    private var imageCanvas: some View {
        ZStack {
            Color(NSColor.textBackgroundColor)
                .ignoresSafeArea()

            Group {
                if file.url.pathExtension.lowercased() == "pdf" {
                    PDFKitView(url: file.url)
                } else if file.url.pathExtension.lowercased() == "svg" {
                    SVGImageView(url: file.url)
                        .aspectRatio(contentMode: .fit)
                } else {
                    RecoverablePreviewImage(url: file.url)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(28)
        }
        .accessibilityLabel(file.name)
        .accessibilityIdentifier("image.detail")
    }

}

// MARK: - Metadata Inspector

struct ImageMetadataInspectorView: View {
    let files: [ImageFile]

    @State private var summary = BatchMetadataSummary(
        fileCount: 0,
        label: .empty,
        sharedTags: [],
        mixedTags: [],
        comments: .empty,
        whereFrom: .empty
    )
    @State private var tags: [String] = []
    @State private var mixedTags: [String] = []
    @State private var comments = ""
    @State private var whereFrom = ""
    @State private var commentsDraft = ""
    @State private var whereFromDraft = ""
    @State private var isEditingTags = false
    @State private var isEditingComments = false
    @State private var isEditingWhereFrom = false
    @State private var newTag = ""
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var writeTask: Task<Void, Never>?
    @State private var writeGeneration = UUID()
    @State private var technicalMetadata = PhotoTechnicalMetadataLoadState()
    @State private var technicalMetadataReloadID = UUID()

    private var file: ImageFile? { files.count == 1 ? files.first : nil }
    private var isBatch: Bool { files.count > 1 }
    private var selectionSignature: [UUID] { files.map(\.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                headerSection

                FinderLabelPicker(selection: selectedLabel) { label in
                    apply(.setLabel(label))
                }
                .disabled(isSaving)

                EditableChipSection(
                    title: "Tags",
                    subtitle: isBatch ? "Finder tags across \(files.count) images" : "Finder tags",
                    itemName: "tag",
                    items: $tags,
                    mixedItems: mixedTags,
                    isEditing: $isEditingTags,
                    newItem: $newTag,
                    chipColor: Color.accentColor.opacity(0.16),
                    onSave: {
                        // Single-file chip edits write immediately via add/remove hooks.
                    },
                    onAdd: { tag in
                        apply(.addTag(tag))
                    },
                    onRemove: { tag in
                        apply(.removeTag(tag))
                    }
                )
                .disabled(isSaving)

                replaceableTextSection(
                    title: "Comments",
                    subtitle: "Finder comments",
                    placeholder: "No comments",
                    field: summary.comments,
                    displayed: comments,
                    draft: $commentsDraft,
                    isEditing: $isEditingComments,
                    isMultiline: true,
                    replaceIdentifier: "inspector.replace-comments",
                    onReplace: { apply(.replaceComments($0)) }
                )

                replaceableTextSection(
                    title: "Where From",
                    subtitle: "Stored in Microfiche",
                    placeholder: "No source specified",
                    field: summary.whereFrom,
                    displayed: whereFrom,
                    draft: $whereFromDraft,
                    isEditing: $isEditingWhereFrom,
                    isMultiline: false,
                    replaceIdentifier: "inspector.replace-where-from",
                    onReplace: { apply(.replaceWhereFrom($0)) }
                )

                if isSaving {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Updating \(files.count) images…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel") {
                            writeTask?.cancel()
                        }
                        .controlSize(.small)
                        .accessibilityIdentifier("inspector.cancel-write")
                    }
                }

                if !isBatch {
                    fileInfoSection
                    technicalMetadataSection
                }

                if let saveError {
                    Text(saveError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("inspector.save-error")
                }
            }
            .padding(20)
        }
        .task(id: selectionSignature) {
            loadMetadata()
        }
        .task(id: technicalMetadataReloadID) {
            await loadTechnicalMetadata()
        }
        .onDisappear {
            writeTask?.cancel()
            guard !isBatch else { return }
            let urls = files.map(\.url)
            let commentsToSave = isEditingComments ? commentsDraft : comments
            let sourceToSave = isEditingWhereFrom ? whereFromDraft : whereFrom
            Task { @MainActor in
                let writer = BatchMetadataWriter.live()
                _ = await writer.apply(.replaceComments(commentsToSave), to: urls)
                _ = await writer.apply(.replaceWhereFrom(sourceToSave), to: urls)
            }
        }
        .onChange(of: saveError) { _, error in
            guard let error else { return }
            MicroficheAccessibility.announce(error, priority: .high)
        }
        .microficheInspectorContentChrome()
        .accessibilityIdentifier("inspector.content")
    }

    private var selectedLabel: FinderLabel? {
        switch summary.label {
        case .empty:
            return .none
        case .shared(let label):
            return label
        case .mixed:
            return nil
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let file {
                Text(file.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("inspector.current-file")

                Text(file.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            } else {
                Text("\(files.count) images selected")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityIdentifier("inspector.selection-summary")

                Text("Shared values apply to every selected image. Mixed tags can be removed from the images that have them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fileInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("File Info")
                .font(.headline)

            if let file {
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
    }

    private var technicalMetadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Technical")
                .font(.headline)

            switch technicalMetadata.phase {
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Reading image metadata…")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .accessibilityIdentifier("inspector.technical.loading")

            case .available(let metadata):
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(metadata.rows, id: \.0) { label, value in
                        InfoRow(label: label, value: value)
                    }
                }

            case .unavailable:
                Text("No embedded photo metadata")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
                    .accessibilityIdentifier("inspector.technical.empty")

            case .failed(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Try Again") {
                        technicalMetadataReloadID = UUID()
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("inspector.technical.retry")
                }
                .accessibilityIdentifier("inspector.technical.failed")
            }
        }
    }

    @ViewBuilder
    private func replaceableTextSection(
        title: String,
        subtitle: String? = nil,
        placeholder: String,
        field: BatchFieldValue<String>,
        displayed: String,
        draft: Binding<String>,
        isEditing: Binding<Bool>,
        isMultiline: Bool,
        replaceIdentifier: String,
        onReplace: @escaping (String) -> Void
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
                    if isEditing.wrappedValue {
                        onReplace(draft.wrappedValue)
                        isEditing.wrappedValue = false
                    } else {
                        draft.wrappedValue = displayed
                        isEditing.wrappedValue = true
                    }
                } label: {
                    Image(systemName: isEditing.wrappedValue ? "checkmark" : (isBatch ? "square.and.pencil" : "pencil"))
                }
                .buttonStyle(.borderless)
                .disabled(isSaving)
                .help(isEditing.wrappedValue ? "Replace \(title)" : "Replace \(title)")
                .accessibilityLabel(
                    isEditing.wrappedValue ? "Apply \(title)" : "Edit \(title)"
                )
                .accessibilityIdentifier(replaceIdentifier)
            }

            if isEditing.wrappedValue {
                if isMultiline {
                    TextEditor(text: draft)
                        .frame(minHeight: 88)
                        .accessibilityLabel(title)
                        .accessibilityIdentifier("\(replaceIdentifier).editor")
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color(NSColor.separatorColor))
                        }
                } else {
                    TextField("Enter source", text: draft)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(title)
                        .accessibilityIdentifier("\(replaceIdentifier).editor")
                        .onSubmit {
                            onReplace(draft.wrappedValue)
                            isEditing.wrappedValue = false
                        }
                }

                if isBatch {
                    Text("This replaces \(title.lowercased()) on every selected image.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Cancel") {
                    isEditing.wrappedValue = false
                    draft.wrappedValue = displayed
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityIdentifier("\(replaceIdentifier).cancel")
            } else {
                Text(displayText(for: field, placeholder: placeholder))
                    .foregroundStyle(fieldDisplayIsPlaceholder(field) ? .secondary : .primary)
                    .italic(fieldDisplayIsPlaceholder(field))
                    .textSelection(.enabled)
            }
        }
    }

    private func displayText(
        for field: BatchFieldValue<String>,
        placeholder: String
    ) -> String {
        switch field {
        case .empty:
            return placeholder
        case .shared(let value):
            return value
        case .mixed:
            return "Multiple values"
        }
    }

    private func fieldDisplayIsPlaceholder(_ field: BatchFieldValue<String>) -> Bool {
        switch field {
        case .empty, .mixed:
            return true
        case .shared:
            return false
        }
    }

    private func loadMetadata() {
        writeTask?.cancel()
        isEditingTags = false
        isEditingComments = false
        isEditingWhereFrom = false
        newTag = ""
        saveError = nil
        isSaving = false

        let resolved = files.map { file in
            BatchMetadataAggregation.resolved(
                native: NativeFileMetadataService.load(from: file.url),
                local: ImageMetadataStore.shared.metadata(for: file.url)
            )
        }
        let next = BatchMetadataAggregation.summarize(resolved)
        summary = next
        tags = next.sharedTags
        mixedTags = next.mixedTags
        comments = {
            if case .shared(let value) = next.comments { return value }
            return ""
        }()
        whereFrom = {
            if case .shared(let value) = next.whereFrom { return value }
            return ""
        }()
        commentsDraft = comments
        whereFromDraft = whereFrom

        if files.count == 1,
           let file = files.first,
           NativeFileMetadataService.load(from: file.url).label == .none,
           let migrated = FinderLabel.migrating(
            from: ImageMetadataStore.shared.metadata(for: file.url).labels
           ) {
            apply(.setLabel(migrated))
        }
    }

    private func loadTechnicalMetadata() async {
        guard let file else { return }
        let requestID = technicalMetadata.beginLoading()
        let requestedURL = file.url
        let outcome = await Task.detached(priority: .utility) {
            do {
                return PhotoTechnicalMetadataReadOutcome.success(
                    try PhotoMetadataReader.read(from: requestedURL)
                )
            } catch {
                return PhotoTechnicalMetadataReadOutcome.failure(error.localizedDescription)
            }
        }.value

        if Task.isCancelled {
            technicalMetadata.cancel(requestID: requestID)
        } else {
            technicalMetadata.finish(outcome, requestID: requestID)
        }
    }

    private func apply(_ operation: BatchMetadataOperation) {
        let urls = files.map(\.url)
        let generation = UUID()
        writeGeneration = generation
        writeTask?.cancel()

        let task = Task { @MainActor in
            isSaving = urls.count > 1
            let result = await BatchMetadataWriter.live().apply(operation, to: urls)
            guard writeGeneration == generation else { return }
            isSaving = false
            writeTask = nil
            loadMetadata()
            saveError = result.errorMessage
        }
        writeTask = task
    }
}

// MARK: - Finder Label Picker

struct FinderLabelPicker: View {
    let selection: FinderLabel?
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

            Text(labelCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var labelCaption: String {
        switch selection {
        case nil:
            return "Multiple labels"
        case .some(.none):
            return "No label"
        case .some(let label):
            return label.displayName
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
    var mixedItems: [String] = []
    @Binding var isEditing: Bool
    @Binding var newItem: String
    let chipColor: Color
    let onSave: () -> Void
    var onAdd: ((String) -> Void)? = nil
    var onRemove: ((String) -> Void)? = nil

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
                .accessibilityLabel(isEditing ? "Finish editing \(title)" : "Add \(itemName)")
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

            if items.isEmpty, mixedItems.isEmpty {
                Text("No \(title.lowercased())")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88))], spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        chip(item, mixed: false)
                    }
                    ForEach(mixedItems, id: \.self) { item in
                        chip(item, mixed: true)
                    }
                }
            }
        }
    }

    private func chip(_ item: String, mixed: Bool) -> some View {
        HStack(spacing: 4) {
            Text(item)
                .lineLimit(1)
            Spacer(minLength: 2)
            if isEditing {
                Button {
                    items.removeAll { $0 == item }
                    if let onRemove {
                        onRemove(item)
                    } else {
                        onSave()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(item)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            (mixed ? Color.secondary.opacity(0.14) : chipColor),
            in: RoundedRectangle(cornerRadius: 7)
        )
        .overlay {
            if mixed {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityLabel(mixed ? "\(item), mixed" : item)
    }

    private func addItem() {
        let value = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !items.contains(value) else { return }
        items.append(value)
        newItem = ""
        if let onAdd {
            onAdd(value)
        } else {
            onSave()
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}
