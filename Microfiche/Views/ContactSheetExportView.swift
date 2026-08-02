//
//  ContactSheetExportView.swift
//  Microfiche
//

import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct ContactSheetExportView: View {
    let contactSheet: ContactSheet
    let items: [ContactSheetExportItem]

    @Environment(\.dismiss) private var dismiss
    @State private var options = ContactSheetExportOptions()
    @State private var previewState = ContactSheetExportPreviewState()
    @State private var temporaryShareURL: URL?
    @State private var lastSavedURL: URL?
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                settingsPanel
                    .frame(width: 270)

                Divider()

                previewPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Export \(contactSheet.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItemGroup {
                    if let shareURL = lastSavedURL ?? temporaryShareURL {
                        ShareLink(item: shareURL) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .help("Share PDF")
                        .accessibilityIdentifier("share-contact-sheet-pdf")
                    }

                    Button {
                        revealLastExport()
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                    .disabled(lastSavedURL == nil)
                    .help("Reveal Last Export in Finder")
                    .accessibilityIdentifier("reveal-contact-sheet-pdf")

                    Button("Save PDF…") {
                        savePDF()
                    }
                    .disabled(currentExport == nil)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("save-contact-sheet-pdf")
                }
            }
        }
        .frame(minWidth: 860, idealWidth: 980, minHeight: 620, idealHeight: 720)
        .accessibilityIdentifier("contact-sheet-export-view")
        .task(id: options) {
            await renderPreview()
        }
        .alert(
            "Couldn’t Export Contact Sheet",
            isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )
        ) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                pageSettings
                captionSettings
                exportSummary
            }
            .padding(20)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
    }

    private var pageSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Page")
                .font(.headline)

            Picker("Paper", selection: $options.paperSize) {
                ForEach(ContactSheetPaperSize.allCases) { paperSize in
                    Text(paperSize.rawValue).tag(paperSize)
                }
            }

            Picker("Orientation", selection: $options.orientation) {
                ForEach(ContactSheetPageOrientation.allCases) { orientation in
                    Text(orientation.rawValue).tag(orientation)
                }
            }
            .pickerStyle(.segmented)

            Stepper("Columns: \(options.columns)", value: $options.columns, in: 2...6)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Margins")
                    Spacer()
                    Text("\(Int(options.margin)) pt")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $options.margin, in: 24...72, step: 6)
                    .accessibilityLabel("Page margins")
                    .accessibilityValue("\(Int(options.margin)) points")
            }
        }
    }

    private var captionSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Captions")
                .font(.headline)

            Toggle("Filename", isOn: $options.captions.includesFilename)
            Toggle("Finder label", isOn: $options.captions.includesFinderLabel)
            Toggle("Tags", isOn: $options.captions.includesTags)
            Toggle("Comments", isOn: $options.captions.includesComments)
            Toggle("Source", isOn: $options.captions.includesSource)
        }
    }

    @ViewBuilder
    private var exportSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.headline)

            switch previewState.phase {
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Building PDF…")
                }
                .foregroundStyle(.secondary)

            case .ready(let export):
                let count = export.layout.pageCount
                Label(
                    "\(count) \(count == 1 ? "page" : "pages")",
                    systemImage: "doc"
                )
                .foregroundStyle(.secondary)

                if items.isEmpty {
                    Label("Contact sheet is empty", systemImage: "photo.on.rectangle.angled")
                        .foregroundStyle(.secondary)
                }

                if !export.unavailableImageNames.isEmpty {
                    Label(
                        "\(export.unavailableImageNames.count) unavailable",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)

                    Text(export.unavailableImageNames.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }

            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)

                Button("Try Again") {
                    Task { await renderPreview() }
                }
                .controlSize(.small)
            }
        }
    }

    private var previewPanel: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)

            switch previewState.phase {
            case .ready(let export):
                ContactSheetPDFDataView(data: export.data)
                    .padding(18)

            case .failed:
                ContentUnavailableView(
                    "Preview Unavailable",
                    systemImage: "doc.badge.ellipsis",
                    description: Text("Adjust an option or try again.")
                )

            case .idle, .loading:
                ProgressView("Building preview…")
                    .controlSize(.large)
            }
        }
    }

    private var currentExport: ContactSheetPDFExport? {
        guard case .ready(let export) = previewState.phase else { return nil }
        return export
    }

    private func renderPreview() async {
        let requestID = previewState.beginLoading()
        lastSavedURL = nil
        temporaryShareURL = nil
        let requestedOptions = options
        let requestedItems = items
        let title = contactSheet.name

        let result = await Task.detached(priority: .userInitiated) {
            do {
                return Result<ContactSheetPDFExport, ContactSheetPDFExportError>.success(
                    try ContactSheetPDFExporter.render(
                        title: title,
                        items: requestedItems,
                        options: requestedOptions
                    )
                )
            } catch let error as ContactSheetPDFExportError {
                return .failure(error)
            } catch {
                return .failure(.unableToCreateContext)
            }
        }.value

        if Task.isCancelled {
            previewState.cancel(requestID: requestID)
            return
        }

        guard previewState.finish(result, requestID: requestID) else { return }
        if case .success(let export) = result {
            prepareTemporaryShareFile(using: export.data)
        }
    }

    private func prepareTemporaryShareFile(using data: Data) {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("Microfiche", isDirectory: true)
            .appendingPathComponent("ContactSheetExports", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(
                ContactSheetPDFExporter.suggestedFilename(for: contactSheet.name)
            )
            try data.write(to: url, options: .atomic)
            temporaryShareURL = url
        } catch {
            temporaryShareURL = nil
        }
    }

    private func savePDF() {
        guard let export = currentExport else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = ContactSheetPDFExporter.suggestedFilename(
            for: contactSheet.name
        )

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try export.data.write(to: url, options: .atomic)
            lastSavedURL = url
            exportError = nil
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func revealLastExport() {
        guard let lastSavedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastSavedURL])
    }
}

private struct ContactSheetPDFDataView: NSViewRepresentable {
    let data: Data

    final class Coordinator {
        var data: Data?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.backgroundColor = .windowBackgroundColor
        updateDocument(in: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        updateDocument(in: nsView, coordinator: context.coordinator)
    }

    private func updateDocument(in view: PDFView, coordinator: Coordinator) {
        guard coordinator.data != data else { return }
        view.document = PDFDocument(data: data)
        coordinator.data = data
    }
}
